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
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }

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
        val state = savedState
        if (state != null) {
            window.statusBarColor = state.statusBarColor
            window.navigationBarColor = state.navigationBarColor
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                state.statusBarContrastEnforced?.let { value ->
                    window.isStatusBarContrastEnforced = value
                }
                state.navigationBarContrastEnforced?.let { value ->
                    window.isNavigationBarContrastEnforced = value
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(true)
            window.insetsController?.let { controller ->
                state?.systemBarsAppearance?.let { appearance ->
                    controller.setSystemBarsAppearance(
                        appearance,
                        lightBarAppearanceMask,
                    )
                }
                state?.systemBarsBehavior?.let { behavior ->
                    controller.systemBarsBehavior = behavior
                }
                controller.show(WindowInsets.Type.systemBars())
            }
        } else {
            window.decorView.systemUiVisibility =
                state?.systemUiVisibility ?: View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
        savedState = null
    }

    private fun captureState(): SavedSystemBarState {
        val controller = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController
        } else {
            null
        }
        return SavedSystemBarState(
            statusBarColor = window.statusBarColor,
            navigationBarColor = window.navigationBarColor,
            systemUiVisibility = window.decorView.systemUiVisibility,
            statusBarContrastEnforced =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    window.isStatusBarContrastEnforced
                } else {
                    null
                },
            navigationBarContrastEnforced =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    window.isNavigationBarContrastEnforced
                } else {
                    null
                },
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
        val statusBarColor: Int,
        val navigationBarColor: Int,
        val systemUiVisibility: Int,
        val statusBarContrastEnforced: Boolean?,
        val navigationBarContrastEnforced: Boolean?,
        val systemBarsAppearance: Int?,
        val systemBarsBehavior: Int?,
    )

    private companion object {
        val lightBarAppearanceMask =
            WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
    }
}
