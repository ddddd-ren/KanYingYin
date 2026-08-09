package com.kanyingyin.player

import android.app.Activity
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.view.Display

internal data class RefreshRateSnapshot(
    val currentRefreshRate: Float = 0f,
    val supportedRefreshRates: List<Float> = emptyList(),
    val preferredModeId: Int = 0,
)

internal class AndroidHighRefreshRateController(
    private val activity: Activity,
) {
    var snapshot = RefreshRateSnapshot()
        private set

    fun applyPreferredMode() {
        if (isTelevision() || isInPictureInPicture()) return
        try {
            val display = currentDisplay() ?: return
            val current = display.mode.toCandidate()
            val supported = display.supportedModes.map { it.toCandidate() }
            val selected = HighRefreshRateModeSelector.select(
                current,
                supported,
            ) ?: return
            val attributes = activity.window.attributes
            if (attributes.preferredDisplayModeId != selected.modeId) {
                attributes.preferredDisplayModeId = selected.modeId
                activity.window.attributes = attributes
            }
            snapshot = RefreshRateSnapshot(
                currentRefreshRate = display.refreshRate,
                supportedRefreshRates = supported
                    .map { it.refreshRate }
                    .distinct()
                    .sorted(),
                preferredModeId = selected.modeId,
            )
        } catch (_: RuntimeException) {
            // 部分系统会拒绝第三方应用查询或设置显示模式，保留系统默认值。
        }
    }

    private fun isTelevision(): Boolean {
        val uiMode = activity.resources.configuration.uiMode and
            Configuration.UI_MODE_TYPE_MASK
        return activity.packageManager.hasSystemFeature(
            PackageManager.FEATURE_TELEVISION,
        ) || activity.packageManager.hasSystemFeature(
            PackageManager.FEATURE_LEANBACK,
        ) || uiMode == Configuration.UI_MODE_TYPE_TELEVISION
    }

    private fun isInPictureInPicture(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.isInPictureInPictureMode

    @Suppress("DEPRECATION")
    private fun currentDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            activity.windowManager.defaultDisplay
        }

    private fun Display.Mode.toCandidate() = DisplayModeCandidate(
        modeId = modeId,
        physicalWidth = physicalWidth,
        physicalHeight = physicalHeight,
        refreshRate = refreshRate,
    )
}
