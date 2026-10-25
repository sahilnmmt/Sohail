package com.sohail.videomerger

import android.graphics.Bitmap
import android.net.Uri

/** One input video and the edits applied to it. */
data class Clip(
    val id: Long,
    val uri: Uri,
    val name: String,
    val durationMs: Long,
    /** Size as the video is shown, with its rotation metadata already applied. */
    val width: Int,
    val height: Int,
    val thumbnail: Bitmap?,
    val trimStartMs: Long = 0,
    val trimEndMs: Long = durationMs,
    /** Extra clockwise rotation chosen by the user: 0, 90, 180 or 270. */
    val rotation: Int = 0,
) {
    val isTrimmed get() = trimStartMs > 0 || trimEndMs < durationMs
    val keptMs get() = trimEndMs - trimStartMs

    /** Size after the user's rotation. */
    val outputWidth get() = if (rotation % 180 == 0) width else height
    val outputHeight get() = if (rotation % 180 == 0) height else width
}

enum class Resolution(val shortSide: Int?, val label: String) {
    ORIGINAL(null, "Original"),
    P1080(1080, "1080p"),
    P720(720, "720p"),
    P480(480, "480p"),
}

data class ExportSettings(val resolution: Resolution, val muteAudio: Boolean)

sealed interface ExportState {
    data object Idle : ExportState
    data class Running(val percent: Int) : ExportState
    data class Done(val uri: Uri) : ExportState
    data class Failed(val message: String) : ExportState
}
