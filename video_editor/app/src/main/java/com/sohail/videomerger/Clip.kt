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

/** Short side of the output in pixels. Smaller clips are scaled up, so output is never below 1080p. */
enum class Resolution(val shortSide: Int) {
    P1080(1080),
    P1440(1440), // 2K
}

data class ExportSettings(
    val resolution: Resolution,
    /** Drop the clips' own sound. An [audio] source is still added. */
    val muteAudio: Boolean,
    val audio: AudioSource? = null,
)

sealed interface ExportState {
    data object Idle : ExportState
    data class Running(val percent: Int) : ExportState
    data class Done(val uri: Uri) : ExportState
    data class Failed(val message: String) : ExportState
}

/** Sound taken from another video or an audio file and laid over the merged video. */
data class AudioSource(
    val uri: Uri,
    val name: String,
    val durationMs: Long,
    val trimStartMs: Long = 0,
    val trimEndMs: Long = durationMs,
    /** Repeat the sound when it is shorter than the video. */
    val loop: Boolean = true,
) {
    val isTrimmed get() = trimStartMs > 0 || trimEndMs < durationMs
    val keptMs get() = trimEndMs - trimStartMs
}
