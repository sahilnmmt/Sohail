package com.sohail.videomerger

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns

object ClipLoader {
    /** Reads a video's length, size and a thumbnail, or returns null if it is not a readable video. */
    fun load(context: Context, uri: Uri, id: Long): Clip? = try {
        MediaMetadataRetriever().use { retriever ->
            retriever.setDataSource(context, uri)
            if (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes") return null
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()?.takeIf { it > 0 } ?: return null
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: return null
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: return null
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val sideways = rotation % 180 != 0
            val thumbnail = retriever.getScaledFrameAtTime(
                minOf(1_000_000L, durationMs * 500), // 1 s in, or halfway for short clips (in microseconds)
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                320,
                320,
            )
            Clip(
                id = id,
                uri = uri,
                name = displayName(context, uri) ?: "Video $id",
                durationMs = durationMs,
                width = if (sideways) height else width,
                height = if (sideways) width else height,
                thumbnail = thumbnail,
            )
        }
    } catch (e: Exception) {
        null
    }

    private fun displayName(context: Context, uri: Uri): String? =
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
}
