package com.kanyingyin.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImmersiveModeControllerTest {
    @Test
    fun initializeAppliesVisibleEdgeToEdgeMode() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled -> calls += enabled }

        controller.initialize()

        assertFalse(controller.isRequested)
        assertEquals(listOf(false), calls)
    }

    @Test
    fun enablingStoresRequestAndAppliesImmersiveMode() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled -> calls += enabled }

        controller.setEnabled(true)

        assertTrue(controller.isRequested)
        assertEquals(listOf(true), calls)
    }

    @Test
    fun lifecycleReapplyUsesCurrentRequestedMode() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled -> calls += enabled }

        controller.initialize()
        controller.reapplyCurrent()
        controller.setEnabled(true)
        controller.reapplyCurrent()

        assertEquals(listOf(false, false, true, true), calls)
    }

    @Test
    fun disablingReturnsToVisibleEdgeToEdgeAndKeepsReapplyingIt() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled -> calls += enabled }

        controller.setEnabled(true)
        controller.setEnabled(false)
        controller.reapplyCurrent()

        assertFalse(controller.isRequested)
        assertEquals(listOf(true, false, false), calls)
    }
}
