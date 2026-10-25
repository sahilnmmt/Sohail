package com.sohail.videomerger

import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects

/**
 * Turns the clip list into one Media3 sequence: clips play back to back in a
 * single output. An audio source becomes a second, sound-only sequence that
 * Media3 mixes with the first.
 */
@OptIn(UnstableApi::class)
fun buildComposition(clips: List<Clip>, settings: ExportSettings): Composition {
    val first = clips.first()
    val (width, height) = outputSize(first.outputWidth, first.outputHeight, settings.resolution.shortSide)

    val items = clips.map { clip ->
        val mediaItem = MediaItem.Builder().setUri(clip.uri).apply {
            if (clip.isTrimmed) {
                setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(clip.trimStartMs)
                        .setEndPositionMs(clip.trimEndMs)
                        .build(),
                )
            }
        }.build()

        val videoEffects = buildList<Effect> {
            if (clip.rotation != 0) {
                // Media3 rotates counter-clockwise; the app's rotation is clockwise.
                add(ScaleAndRotateTransformation.Builder().setRotationDegrees((360 - clip.rotation).toFloat()).build())
            }
            // Every clip is fitted into the same frame, with black bars where the shape differs.
            add(Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT))
        }

        EditedMediaItem.Builder(mediaItem)
            .setRemoveAudio(settings.muteAudio)
            .setEffects(Effects(emptyList(), videoEffects))
            .build()
    }

    val sequences = mutableListOf(EditedMediaItemSequence(items))
    settings.audio?.let { sequences += audioSequence(it, clips.sumOf { clip -> clip.keptMs }) }

    return Composition.Builder(sequences)
        .apply {
            // Adds silence for clips that have no sound, so a merge can mix clips with and without audio.
            if (!settings.muteAudio) experimentalSetForceAudioTrack(true)
        }
        .build()
}

@OptIn(UnstableApi::class)
private fun audioSequence(audio: AudioSource, videoMs: Long): EditedMediaItemSequence {
    val endMs = soundEndMs(audio.trimStartMs, audio.trimEndMs, audio.loop, videoMs)
    val mediaItem = MediaItem.Builder()
        .setUri(audio.uri)
        .setClippingConfiguration(
            MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(audio.trimStartMs)
                .setEndPositionMs(endMs)
                .build(),
        )
        .build()
    val item = EditedMediaItem.Builder(mediaItem).setRemoveVideo(true).build()
    return EditedMediaItemSequence(listOf(item), audio.loop)
}
