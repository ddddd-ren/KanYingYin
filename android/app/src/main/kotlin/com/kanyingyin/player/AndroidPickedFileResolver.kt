package com.kanyingyin.player

internal object AndroidPickedFileResolver {
    fun resolveExtension(
        displayName: String?,
        uriPath: String?,
        uriText: String?,
        allowedExtensions: Set<String>,
    ): String? {
        val normalizedAllowed = allowedExtensions
            .map(String::lowercase)
            .toSet()
        if (normalizedAllowed.isEmpty()) return null

        for (candidate in listOfNotNull(displayName, uriPath, uriText)) {
            val fileName = candidate
                .substringBefore('?')
                .substringBefore('#')
                .substringAfterLast('/')
                .substringAfterLast(':')
            val extension = fileName.substringAfterLast('.', "").lowercase()
            if (extension in normalizedAllowed) return extension
        }
        if (normalizedAllowed.size == 1) {
            return normalizedAllowed.single()
        }
        return null
    }
}
