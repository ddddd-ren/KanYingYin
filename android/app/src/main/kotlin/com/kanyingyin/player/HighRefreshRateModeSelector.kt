package com.kanyingyin.player

internal data class DisplayModeCandidate(
    val modeId: Int,
    val physicalWidth: Int,
    val physicalHeight: Int,
    val refreshRate: Float,
)

internal object HighRefreshRateModeSelector {
    fun select(
        current: DisplayModeCandidate?,
        supported: List<DisplayModeCandidate>,
    ): DisplayModeCandidate? {
        current ?: return null
        return supported
            .asSequence()
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .maxWithOrNull(
                compareBy<DisplayModeCandidate> { it.refreshRate }
                    .thenBy { -it.modeId },
            ) ?: current
    }
}
