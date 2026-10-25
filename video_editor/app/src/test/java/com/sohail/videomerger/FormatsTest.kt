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
        assertEquals(1920 to 1080, outputSize(1920, 1080, 1080))
        assertEquals(2560 to 1440, outputSize(1280, 720, 1440)) // 720p clip scaled up to 2K
        assertEquals(1080 to 1920, outputSize(1080, 1920, 1080))
    }

    @Test
    fun outputSizeIsEven() {
        assertEquals(1440 to 1080, outputSize(640, 480, 1080)) // 4:3
        assertEquals(1080 to 1080, outputSize(1000, 1001, 1080)) // rounds down to even
    }

    @Test
    fun soundStopsWithTheVideoUnlessLooping() {
        // 60 s song, video 20 s: cut at 20 s after the trim start.
        assertEquals(30_000, soundEndMs(10_000, 60_000, loop = false, videoMs = 20_000))
        // A shorter sound just ends.
        assertEquals(15_000, soundEndMs(5_000, 15_000, loop = false, videoMs = 20_000))
        // Looping keeps the whole kept part; Media3 repeats it until the video ends.
        assertEquals(15_000, soundEndMs(5_000, 15_000, loop = true, videoMs = 20_000))
    }
}
