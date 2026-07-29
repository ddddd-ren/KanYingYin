package com.kanyingyin.player

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Rational
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.kanyingyin.player/android"

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
                    else -> result.notImplemented()
                }
            }
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

    @Suppress("DEPRECATION")
    private fun handleSetImmersive(enabled: Boolean, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (enabled) {
                    controller.hide(WindowInsets.Type.systemBars())
                } else {
                    controller.show(WindowInsets.Type.systemBars())
                }
            }
        } else {
            window.decorView.systemUiVisibility = if (enabled) {
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            } else {
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            }
        }
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
            result.error("PermissionDenied", "未获得图片保存权限", null)
            return
        }

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
