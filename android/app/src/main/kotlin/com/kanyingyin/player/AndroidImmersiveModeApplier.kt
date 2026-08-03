package com.kanyingyin.player

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowInsets
import android.view.WindowInsetsController

@Suppress("DEPRECATION")
internal class AndroidImmersiveModeApplier(
    activity: Activity,
) : ImmersiveModeApplier {
    private val window: Window = activity.window
    private var savedState: SavedSystemBarState? = null

    override fun apply(enabled: Boolean) {
        if (enabled) {
            enableImmersiveMode()
        } else {
            disableImmersiveMode()
        }
    }

    private fun enableImmersiveMode() {
        if (savedState == null) {
            savedState = captureState()
        }
        applyTransparentSystemBars()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { controller ->
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.setSystemBarsAppearance(0, lightBarAppearanceMask)
                controller.hide(WindowInsets.Type.systemBars())
            }
        } else {
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }

    private fun disableImmersiveMode() {
        applyTransparentSystemBars()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { controller ->
                savedState?.systemBarsAppearance?.let { appearance ->
                    controller.setSystemBarsAppearance(
                        appearance,
                        lightBarAppearanceMask,
                    )
                }
                savedState?.systemBarsBehavior?.let { behavior ->
                    controller.systemBarsBehavior = behavior
                }
                controller.show(WindowInsets.Type.systemBars())
            }
        } else {
            val lightAppearance = (savedState?.systemUiVisibility
                ?: window.decorView.systemUiVisibility) and lightLegacyMask
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    lightAppearance
        }
        savedState = null
    }

    private fun applyTransparentSystemBars() {
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    private fun captureState(): SavedSystemBarState {
        val controller = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController
        } else {
            null
        }
        return SavedSystemBarState(
            systemUiVisibility = window.decorView.systemUiVisibility,
            systemBarsAppearance =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    controller?.systemBarsAppearance
                } else {
                    null
                },
            systemBarsBehavior =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    controller?.systemBarsBehavior
                } else {
                    null
                },
        )
    }

    private data class SavedSystemBarState(
        val systemUiVisibility: Int,
        val systemBarsAppearance: Int?,
        val systemBarsBehavior: Int?,
    )

    private companion object {
        val lightBarAppearanceMask =
            WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS

        val lightLegacyMask =
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                } else {
                    0
                }
    }
}
