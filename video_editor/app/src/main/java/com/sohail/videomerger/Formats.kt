package com.sohail.videomerger

import kotlin.math.roundToInt

/** Formats a duration as m:ss, or m:ss.d when [tenths] is set. */
fun formatDuration(ms: Long, tenths: Boolean = false): String {
    val totalTenths = ms / 100
    val minutes = totalTenths / 600
    val seconds = (totalTenths / 10) % 60
    return if (tenths) "%d:%02d.%d".format(minutes, seconds, totalTenths % 10)
    else "%d:%02d".format(minutes, seconds)
}

/**
 * Output frame size for a merge. The first clip sets the shape (landscape or
 * portrait); [shortSide] sets its size. Encoders need even dimensions.
 */
fun outputSize(firstWidth: Int, firstHeight: Int, shortSide: Int): Pair<Int, Int> {
    val scale = shortSide.toDouble() / minOf(firstWidth, firstHeight)
    return even((firstWidth * scale).roundToInt()) to even((firstHeight * scale).roundToInt())
}

/**
 * Where an added sound stops, in the sound file's own time. A looping sound
 * plays its whole kept part and repeats until the video ends; otherwise it is
 * cut where the video stops, so the output is never longer than the video.
 */
fun soundEndMs(trimStartMs: Long, trimEndMs: Long, loop: Boolean, videoMs: Long): Long =
    if (loop) trimEndMs else minOf(trimEndMs, trimStartMs + videoMs)

private fun even(value: Int) = maxOf(2, value - value % 2)
