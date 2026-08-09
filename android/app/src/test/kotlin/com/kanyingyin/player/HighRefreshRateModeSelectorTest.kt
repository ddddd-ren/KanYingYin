package com.kanyingyin.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HighRefreshRateModeSelectorTest {
    private val current = DisplayModeCandidate(1, 1080, 2400, 60f)

    @Test
    fun selectsHighestRefreshRateAtCurrentResolution() {
        val selected = HighRefreshRateModeSelector.select(
            current,
            listOf(
                current,
                DisplayModeCandidate(2, 1080, 2400, 90f),
                DisplayModeCandidate(3, 1080, 2400, 120f),
                DisplayModeCandidate(4, 1440, 3200, 144f),
            ),
        )

        assertEquals(3, selected?.modeId)
    }

    @Test
    fun returnsCurrentModeWhenNoFasterSameResolutionModeExists() {
        assertEquals(
            current,
            HighRefreshRateModeSelector.select(current, listOf(current)),
        )
    }

    @Test
    fun usesStableModeIdWhenRefreshRatesTie() {
        val selected = HighRefreshRateModeSelector.select(
            current,
            listOf(
                DisplayModeCandidate(7, 1080, 2400, 120f),
                DisplayModeCandidate(3, 1080, 2400, 120f),
            ),
        )

        assertEquals(3, selected?.modeId)
    }

    @Test
    fun returnsNullWhenModesAreUnavailable() {
        assertNull(HighRefreshRateModeSelector.select(null, emptyList()))
    }
}
