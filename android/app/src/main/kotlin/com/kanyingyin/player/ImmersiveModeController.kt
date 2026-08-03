package com.kanyingyin.player

internal fun interface ImmersiveModeApplier {
    fun apply(enabled: Boolean)
}

internal class ImmersiveModeController(
    private val applier: ImmersiveModeApplier,
) {
    var isRequested: Boolean = false
        private set

    fun initialize() {
        applier.apply(false)
    }

    fun setEnabled(enabled: Boolean) {
        isRequested = enabled
        applier.apply(enabled)
    }

    fun reapplyCurrent() {
        applier.apply(isRequested)
    }
}
