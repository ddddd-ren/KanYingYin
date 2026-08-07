package com.kanyingyin.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AndroidPickedFileResolverTest {
    @Test
    fun `从显示名或文档 URI 识别导入扩展名`() {
        assertEquals(
            "kyyconfig",
            AndroidPickedFileResolver.resolveExtension(
                displayName = "看影音配置.kyyconfig",
                uriPath = null,
                uriText = null,
                allowedExtensions = setOf("kyyconfig"),
            ),
        )
        assertEquals(
            "kyymeta",
            AndroidPickedFileResolver.resolveExtension(
                displayName = null,
                uriPath = "primary:Download/看影音刮削资料.kyymeta",
                uriText = null,
                allowedExtensions = setOf("kyymeta"),
            ),
        )
    }

    @Test
    fun `文件管理器不返回扩展名时使用唯一允许格式`() {
        assertEquals(
            "kyyconfig",
            AndroidPickedFileResolver.resolveExtension(
                displayName = null,
                uriPath = "42",
                uriText = "content://downloads/public_downloads/42",
                allowedExtensions = setOf("kyyconfig"),
            ),
        )
        assertNull(
            AndroidPickedFileResolver.resolveExtension(
                displayName = null,
                uriPath = "42",
                uriText = "content://downloads/public_downloads/42",
                allowedExtensions = setOf("kyyconfig", "kyymeta"),
            ),
        )
    }
}
