package com.sohail.videomerger

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File

/** Runs one Media3 Transformer export at a time. Call from the main thread. */
@OptIn(UnstableApi::class)
class Exporter(
    private val context: Context,
    private val onProgress: (Int) -> Unit,
    private val onFinished: (File) -> Unit,
    private val onError: (String) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val progressHolder = ProgressHolder()
    private var transformer: Transformer? = null

    private val pollProgress = object : Runnable {
        override fun run() {
            val current = transformer ?: return
            if (current.getProgress(progressHolder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                onProgress(progressHolder.progress)
            }
            handler.postDelayed(this, 250)
        }
    }

    fun start(clips: List<Clip>, settings: ExportSettings) {
        val output = File(context.cacheDir, "export/merged.mp4")
        output.parentFile?.mkdirs()
        output.delete()

        transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    stop()
                    onFinished(output)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    stop()
                    output.delete()
                    onError(exportException.message ?: "Export failed (error ${exportException.errorCode})")
                }
            })
            .build()
            .also { it.start(buildComposition(clips, settings), output.absolutePath) }
        handler.post(pollProgress)
    }

    fun cancel() {
        transformer?.cancel()
        stop()
    }

    private fun stop() {
        transformer = null
        handler.removeCallbacks(pollProgress)
    }
}
