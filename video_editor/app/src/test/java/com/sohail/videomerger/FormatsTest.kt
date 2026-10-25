package com.sohail.videomerger

import org.junit.Assert.assertEquals
import org.junit.Test

class FormatsTest {
    @Test
    fun formatsDurations() {
        assertEquals("0:00", formatDuration(0))
        assertEquals("1:05", formatDuration(65_400))
        assertEquals("1:05.4", formatDuration(65_400, tenths = true))
        assertEquals("61:01", formatDuration(3_661_000))
    }

    @Test
    fun outputSizeFollowsFirstClipShape() {
        assertEquals(1280 to 720, outputSize(1920, 1080, 720))
        assertEquals(720 to 1280, outputSize(1080, 1920, 720))
        assertEquals(1920 to 1080, outputSize(1920, 1080, null))
    }

    @Test
    fun outputSizeIsEven() {
        // 4:3 at 480p is 640x480; an odd source keeps its shape but rounds down to even.
        assertEquals(640 to 480, outputSize(1440, 1080, 480))
        assertEquals(1278 to 720, outputSize(1279, 721, null))
    }
}
