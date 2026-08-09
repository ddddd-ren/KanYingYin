package com.kanyingyin.player

import android.Manifest
import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Rational
import android.webkit.WebView
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.kanyingyin.player/android"
    private val immersiveModeController by lazy {
        ImmersiveModeController(AndroidImmersiveModeApplier(this))
    }
    private val highRefreshRateController by lazy {
        AndroidHighRefreshRateController(this)
    }
    private val directoryPickerRequestCode = 4201
    private val notificationPermissionRequestCode = 4202
    private val screenshotPermissionRequestCode = 4203
    private val filePickerRequestCode = 4204
    private var pendingDirectoryPicker: MethodChannel.Result? = null
    private var pendingFilePicker: PendingFilePicker? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private var pendingScreenshot: Pair<ByteArray, MethodChannel.Result>? = null
    private var tabletLandscapeLocked = false

    private data class PendingFilePicker(
        val result: MethodChannel.Result,
        val allowedExtensions: Set<String>,
        val maxBytes: Long,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        immersiveModeController.initialize()
        applyTabletLandscapePolicy(resources.configuration)
        highRefreshRateController.applyPreferredMode()
    }

    override fun onResume() {
        super.onResume()
        immersiveModeController.reapplyCurrent()
        highRefreshRateController.applyPreferredMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            immersiveModeController.reapplyCurrent()
            highRefreshRateController.applyPreferredMode()
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyTabletLandscapePolicy(newConfig)
        immersiveModeController.reapplyCurrent()
        highRefreshRateController.applyPreferredMode()
    }

    private fun applyTabletLandscapePolicy(configuration: Configuration) {
        val shouldLockLandscape = configuration.smallestScreenWidthDp >= 600
        if (shouldLockLandscape) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } else if (tabletLandscapeLocked) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        tabletLandscapeLocked = shouldLockLandscape
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPictureInPicture" -> handleEnterPictureInPicture(call, result)
                    "setImmersive" -> handleSetImmersive(call.arguments == true, result)
                    "setBrightness" -> handleSetBrightness(call.arguments, result)
                    "saveScreenshot" -> handleSaveScreenshot(call.arguments, result)
                    "openWithMime" -> handleOpenWithMime(call.arguments, result)
                    "requestNotificationPermission" ->
                        handleRequestNotificationPermission(result)
                    "getDeviceCapabilities" -> handleGetDeviceCapabilities(result)
                    "pickDirectory" -> handlePickDirectory(result)
                    "pickFile" -> handlePickFile(call, result)
                    "canAccessDocument" -> handleCanAccessDocument(call, result)
                    "listDocumentChildren" -> handleListDocumentChildren(call, result)
                    "readSmallDocument" -> handleReadSmallDocument(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleGetDeviceCapabilities(result: MethodChannel.Result) {
        try {
            result.success(deviceCapabilities())
        } catch (_: Exception) {
            result.error("CapabilityProbeFailed", "无法读取 Android 设备能力", null)
        }
    }

    private fun deviceCapabilities(): Map<String, Any> {
        val uiMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "leanback" to packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK),
            "television" to (
                packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
                    uiMode == Configuration.UI_MODE_TYPE_TELEVISION
                ),
            "touchscreen" to packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN),
            "webView" to (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    WebView.getCurrentWebViewPackage() != null
                ),
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "hardware" to Build.HARDWARE,
            "socModel" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Build.SOC_MODEL
            } else {
                ""
            },
            "currentRefreshRate" to
                highRefreshRateController.snapshot.currentRefreshRate.toDouble(),
            "supportedRefreshRates" to highRefreshRateController.snapshot
                .supportedRefreshRates
                .map { it.toDouble() },
            "preferredDisplayModeId" to
                highRefreshRateController.snapshot.preferredModeId,
        )
    }

    private fun handlePickDirectory(result: MethodChannel.Result) {
        if (pendingDirectoryPicker != null) {
            result.error("PickerBusy", "目录选择器正在使用", null)
            return
        }
        pendingDirectoryPicker = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, directoryPickerRequestCode)
        } catch (_: Exception) {
            pendingDirectoryPicker = null
            result.error("PickerUnavailable", "无法打开系统目录选择器", null)
        }
    }

    private fun handlePickFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingFilePicker != null) {
            result.error("PickerBusy", "文件选择器正在使用", null)
            return
        }
        val extensions = call.argument<List<*>>("allowedExtensions")
            ?.mapNotNull { (it as? String)?.trim()?.lowercase() }
            ?.filter { it.matches(Regex("[a-z0-9]{1,16}")) }
            ?.toSet()
            .orEmpty()
        val maxBytes = call.argument<Number>("maxBytes")?.toLong() ?: 0L
        if (extensions.isEmpty() || maxBytes <= 0L || maxBytes > 10L * 1024 * 1024 * 1024) {
            result.error("InvalidInput", "文件选择参数无效", null)
            return
        }

        val openDocument = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val intent = if (openDocument.resolveActivity(packageManager) != null) {
            openDocument
        } else {
            Intent(Intent.ACTION_GET_CONTENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error("PickerUnavailable", "电视没有可用的系统文件选择器", null)
            return
        }

        pendingFilePicker = PendingFilePicker(result, extensions, maxBytes)
        try {
            startActivityForResult(intent, filePickerRequestCode)
        } catch (_: Exception) {
            pendingFilePicker = null
            result.error("PickerUnavailable", "无法打开系统文件选择器", null)
        }
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == filePickerRequestCode) {
            handleFilePickerResult(resultCode, data)
            return
        }
        if (requestCode != directoryPickerRequestCode) return
        val result = pendingDirectoryPicker ?: return
        pendingDirectoryPicker = null
        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            result.success(null)
            return
        }
        try {
            val takeFlags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(treeUri, takeFlags)
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
            val name = queryDocumentName(documentUri) ?: "已选目录"
            result.success(
                mapOf(
                    "treeUri" to treeUri.toString(),
                    "documentUri" to documentUri.toString(),
                    "name" to name,
                ),
            )
        } catch (_: SecurityException) {
            result.error("PermissionDenied", "无法保留目录访问权限", null)
        } catch (_: Exception) {
            result.error("InvalidDocument", "系统返回的目录无效", null)
        }
    }

    private fun handleFilePickerResult(resultCode: Int, data: Intent?) {
        val pending = pendingFilePicker ?: return
        pendingFilePicker = null
        val documentUri = data?.data
        if (resultCode != Activity.RESULT_OK || documentUri == null) {
            pending.result.success(null)
            return
        }

        var cacheFile: File? = null
        try {
            val queriedName = queryDocumentName(documentUri)
            val extension = resolvePickedFileExtension(
                queriedName,
                documentUri,
                pending.allowedExtensions,
            )
            if (extension == null) {
                pending.result.error("InvalidExtension", "请选择指定格式的文件", null)
                return
            }
            val name = queriedName?.takeIf { it.isNotBlank() } ?: "导入文件.$extension"
            val directory = File(cacheDir, "tv-file-picker")
            if (!directory.exists() && !directory.mkdirs()) {
                pending.result.error("CacheUnavailable", "无法创建文件缓存目录", null)
                return
            }
            val outputFile = File.createTempFile("import-", ".$extension", directory)
            cacheFile = outputFile
            var totalBytes = 0L
            contentResolver.openInputStream(documentUri)?.use { input ->
                outputFile.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        totalBytes += count
                        if (totalBytes > pending.maxBytes) {
                            outputFile.delete()
                            pending.result.error("FileTooLarge", "文件超过允许的大小", null)
                            return
                        }
                        output.write(buffer, 0, count)
                    }
                    output.flush()
                }
            } ?: run {
                outputFile.delete()
                pending.result.error("ReadFailed", "无法打开所选文件", null)
                return
            }
            pending.result.success(
                mapOf(
                    "path" to outputFile.absolutePath,
                    "name" to name,
                    "size" to totalBytes,
                ),
            )
        } catch (_: SecurityException) {
            cacheFile?.delete()
            pending.result.error("PermissionDenied", "无法读取所选文件", null)
        } catch (_: Exception) {
            cacheFile?.delete()
            pending.result.error("ReadFailed", "无法缓存所选文件", null)
        }
    }

    override fun onDestroy() {
        pendingDirectoryPicker?.error("ActivityDestroyed", "目录选择已取消", null)
        pendingDirectoryPicker = null
        pendingFilePicker?.result?.error("ActivityDestroyed", "文件选择已取消", null)
        pendingFilePicker = null
        pendingNotificationPermission?.error(
            "ActivityDestroyed",
            "通知授权请求已取消",
            null,
        )
        pendingNotificationPermission = null
        pendingScreenshot?.second?.error(
            "ActivityDestroyed",
            "截图保存请求已取消",
            null,
        )
        pendingScreenshot = null
        super.onDestroy()
    }

    private fun handleRequestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotificationPermission != null) {
            result.error("PermissionRequestBusy", "通知授权请求正在进行", null)
            return
        }
        pendingNotificationPermission = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            notificationPermissionRequestCode -> {
                val result = pendingNotificationPermission ?: return
                pendingNotificationPermission = null
                result.success(
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED,
                )
            }
            screenshotPermissionRequestCode -> {
                val pending = pendingScreenshot ?: return
                pendingScreenshot = null
                if (
                    grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                ) {
                    saveScreenshotBytes(pending.first, pending.second)
                } else {
                    pending.second.error("PermissionDenied", "未获得图片保存权限", null)
                }
            }
        }
    }

    private fun handleCanAccessDocument(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = readContentUri(call, "documentUri", result) ?: return
        if (readContentUri(call, "treeUri", result) == null) return
        try {
            contentResolver.query(
                documentUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { cursor ->
                result.success(cursor.moveToFirst())
            } ?: result.success(false)
        } catch (_: SecurityException) {
            result.error("PermissionRevoked", "目录授权已失效", null)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun handleListDocumentChildren(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = readContentUri(call, "documentUri", result) ?: return
        val treeUri = readContentUri(call, "treeUri", result) ?: return
        try {
            val childUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getDocumentId(documentUri),
            )
            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            val children = mutableListOf<Map<String, Any>>()
            contentResolver.query(childUri, projection, null, null, null)?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(projection[0])
                val nameColumn = cursor.getColumnIndexOrThrow(projection[1])
                val mimeColumn = cursor.getColumnIndexOrThrow(projection[2])
                val sizeColumn = cursor.getColumnIndex(projection[3])
                val modifiedColumn = cursor.getColumnIndex(projection[4])
                while (cursor.moveToNext()) {
                    val childDocumentUri = DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        cursor.getString(idColumn),
                    )
                    children.add(
                        mapOf(
                            "documentUri" to childDocumentUri.toString(),
                            "name" to (cursor.getString(nameColumn) ?: "未命名"),
                            "mimeType" to (cursor.getString(mimeColumn) ?: "application/octet-stream"),
                            "size" to if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) cursor.getLong(sizeColumn) else 0L,
                            "modified" to if (modifiedColumn >= 0 && !cursor.isNull(modifiedColumn)) cursor.getLong(modifiedColumn) else 0L,
                        ),
                    )
                }
            }
            result.success(children)
        } catch (_: SecurityException) {
            result.error("PermissionRevoked", "目录授权已失效", null)
        } catch (_: Exception) {
            result.error("ReadFailed", "无法读取目录内容", null)
        }
    }

    private fun handleReadSmallDocument(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = readContentUri(call, "documentUri", result) ?: return
        val maxBytes = call.argument<Number>("maxBytes")?.toInt() ?: 0
        if (maxBytes <= 0 || maxBytes > 20 * 1024 * 1024) {
            result.error("InvalidInput", "小文件读取上限无效", null)
            return
        }
        try {
            val output = ByteArrayOutputStream()
            contentResolver.openInputStream(documentUri)?.use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > maxBytes) {
                        result.error("FileTooLarge", "文件超过允许的读取大小", null)
                        return
                    }
                    output.write(buffer, 0, count)
                }
            } ?: run {
                result.error("ReadFailed", "无法打开文档", null)
                return
            }
            result.success(output.toByteArray())
        } catch (_: SecurityException) {
            result.error("PermissionRevoked", "文档授权已失效", null)
        } catch (_: Exception) {
            result.error("ReadFailed", "无法读取文档", null)
        }
    }

    private fun readContentUri(
        call: MethodCall,
        key: String,
        result: MethodChannel.Result,
    ): Uri? {
        val value = call.argument<String>(key)?.trim().orEmpty()
        val uri = Uri.parse(value)
        if (value.isEmpty() || uri.scheme != "content") {
            result.error("InvalidInput", "文档参数无效", null)
            return null
        }
        return uri
    }

    private fun queryDocumentName(documentUri: Uri): String? {
        try {
            contentResolver.query(
                documentUri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    return cursor.getString(0)?.takeIf { it.isNotBlank() }
                }
            }
        } catch (_: Exception) {
            // 部分电视文件管理器不提供显示名，稍后从 URI 或唯一扩展名恢复。
        }
        return documentUri.lastPathSegment
            ?.let(Uri::decode)
            ?.substringAfterLast('/')
            ?.substringAfterLast(':')
            ?.takeIf { it.isNotBlank() }
    }

    private fun resolvePickedFileExtension(
        displayName: String?,
        documentUri: Uri,
        allowedExtensions: Set<String>,
    ): String? {
        return AndroidPickedFileResolver.resolveExtension(
            displayName = displayName,
            uriPath = documentUri.lastPathSegment?.let(Uri::decode),
            uriText = Uri.decode(documentUri.toString()),
            allowedExtensions = allowedExtensions,
        )
    }

    private fun handleEnterPictureInPicture(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }
        val width = call.argument<Int>("width")?.coerceAtLeast(1) ?: 16
        val height = call.argument<Int>("height")?.coerceAtLeast(1) ?: 9
        try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(width, height))
                .build()
            result.success(enterPictureInPictureMode(params))
        } catch (_: IllegalArgumentException) {
            result.error("InvalidAspectRatio", "画中画宽高比无效", null)
        } catch (_: IllegalStateException) {
            result.error("PictureInPictureUnavailable", "当前无法进入画中画", null)
        }
    }

    private fun handleSetImmersive(enabled: Boolean, result: MethodChannel.Result) {
        immersiveModeController.setEnabled(enabled)
        result.success(null)
    }

    private fun handleSetBrightness(arguments: Any?, result: MethodChannel.Result) {
        val value = (arguments as? Number)?.toFloat()
        if (value == null || !value.isFinite()) {
            result.error("InvalidInput", "亮度参数无效", null)
            return
        }
        val attributes = window.attributes
        attributes.screenBrightness = value.coerceIn(0.01f, 1.0f)
        window.attributes = attributes
        result.success(null)
    }

    private fun handleSaveScreenshot(arguments: Any?, result: MethodChannel.Result) {
        val bytes = arguments as? ByteArray
        if (bytes == null || bytes.isEmpty()) {
            result.error("InvalidInput", "截图数据为空", null)
            return
        }
        if (
            Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingScreenshot != null) {
                result.error("PermissionRequestBusy", "截图保存授权正在进行", null)
                return
            }
            pendingScreenshot = Pair(bytes, result)
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                screenshotPermissionRequestCode,
            )
            return
        }

        saveScreenshotBytes(bytes, result)
    }

    private fun saveScreenshotBytes(bytes: ByteArray, result: MethodChannel.Result) {
        val resolver = contentResolver
        val displayName = "看影音-${System.currentTimeMillis()}.png"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/看影音")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            } else {
                val directory = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "看影音",
                )
                if (!directory.exists() && !directory.mkdirs()) {
                    result.error("SaveFailed", "无法创建截图目录", null)
                    return
                }
                put(MediaStore.Images.Media.DATA, File(directory, displayName).absolutePath)
            }
        }

        var uri: Uri? = null
        try {
            uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                result.error("SaveFailed", "系统未创建截图条目", null)
                return
            }
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IllegalStateException("系统无法打开截图输出流")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(
                    uri,
                    ContentValues().apply {
                        put(MediaStore.Images.Media.IS_PENDING, 0)
                    },
                    null,
                    null,
                )
            }
            result.success(uri.toString())
        } catch (_: Exception) {
            uri?.let { resolver.delete(it, null, null) }
            result.error("SaveFailed", "截图保存失败", null)
        }
    }

    private fun handleOpenWithMime(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *>
        val url = (values?.get("url") as? String)?.trim().orEmpty()
        val mimeType = (values?.get("mimeType") as? String)?.trim().orEmpty()
        val uri = Uri.parse(url)
        if (
            url.isEmpty() ||
            mimeType.isEmpty() ||
            uri.scheme !in setOf("content", "http", "https")
        ) {
            result.error("InvalidInput", "外部播放参数无效", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.success(false)
            return
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (_: Exception) {
            result.error("LaunchFailed", "无法打开外部播放器", null)
        }
    }
}
