package com.kanyingyin.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImmersiveModeControllerTest {
    @Test
    fun enablingStoresRequestAndAppliesImmersiveMode() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled ->
            calls += enabled
        }

        controller.setEnabled(true)

        assertTrue(controller.isRequested)
        assertEquals(listOf(true), calls)
    }

    @Test
    fun lifecycleReapplyRunsOnlyWhileImmersiveIsRequested() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled ->
            calls += enabled
        }

        controller.reapplyIfRequested()
        controller.setEnabled(true)
        controller.reapplyIfRequested()

        assertEquals(listOf(true, true), calls)
    }

    @Test
    fun disablingRestoresBarsAndStopsFutureReapply() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled ->
            calls += enabled
        }

        controller.setEnabled(true)
        controller.setEnabled(false)
        controller.reapplyIfRequested()

        assertFalse(controller.isRequested)
        assertEquals(listOf(true, false), calls)
    }
}
