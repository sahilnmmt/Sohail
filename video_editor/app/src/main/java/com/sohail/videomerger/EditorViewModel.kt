package com.sohail.videomerger

import android.app.Application
import android.content.ContentValues
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Holds the clip list and export across screen rotations. */
class EditorViewModel(application: Application) : AndroidViewModel(application) {
    private val _clips = MutableLiveData<List<Clip>>(emptyList())
    val clips: LiveData<List<Clip>> = _clips

    private val _export = MutableLiveData<ExportState>(ExportState.Idle)
    val export: LiveData<ExportState> = _export

    /** One-off messages for a toast; cleared once shown. */
    val message = MutableLiveData<String?>()

    var resolution = Resolution.P720
    var muteAudio = false

    private var nextId = 1L
    private val exporter = Exporter(
        application,
        onProgress = { _export.value = ExportState.Running(it) },
        onFinished = ::saveToGallery,
        onError = { _export.value = ExportState.Failed(it) },
    )

    private val current get() = _clips.value.orEmpty()

    fun addVideos(uris: List<Uri>) {
        if (uris.isEmpty()) return
        val ids = uris.map { nextId++ }
        viewModelScope.launch {
            val loaded = withContext(Dispatchers.IO) {
                uris.zip(ids).mapNotNull { (uri, id) -> ClipLoader.load(getApplication(), uri, id) }
            }
            _clips.value = current + loaded
            val skipped = uris.size - loaded.size
            if (skipped > 0) message.value = "$skipped file(s) could not be read as video"
            resetExport()
        }
    }

    fun move(from: Int, to: Int) {
        val list = current.toMutableList()
        if (from !in list.indices || to !in list.indices) return
        list.add(to, list.removeAt(from))
        update(list)
    }

    fun remove(id: Long) = update(current.filterNot { it.id == id })

    fun rotate(id: Long) = edit(id) { it.copy(rotation = (it.rotation + 90) % 360) }

    fun trim(id: Long, startMs: Long, endMs: Long) = edit(id) { it.copy(trimStartMs = startMs, trimEndMs = endMs) }

    fun clip(id: Long) = current.firstOrNull { it.id == id }

    fun startExport() {
        val clips = current
        if (clips.isEmpty() || _export.value is ExportState.Running) return
        _export.value = ExportState.Running(0)
        exporter.start(clips, ExportSettings(resolution, muteAudio))
    }

    fun cancelExport() {
        exporter.cancel()
        _export.value = ExportState.Idle
    }

    /** Any edit makes a finished export out of date. */
    fun resetExport() {
        if (_export.value !is ExportState.Running) _export.value = ExportState.Idle
    }

    private fun edit(id: Long, change: (Clip) -> Clip) = update(current.map { if (it.id == id) change(it) else it })

    private fun update(list: List<Clip>) {
        _clips.value = list
        resetExport()
    }

    private fun saveToGallery(file: File) {
        viewModelScope.launch {
            val uri = withContext(Dispatchers.IO) {
                runCatching { copyToMovies(file) }.also { file.delete() }.getOrNull()
            }
            _export.value = if (uri != null) ExportState.Done(uri) else ExportState.Failed("Could not save the video to the gallery")
        }
    }

    private fun copyToMovies(file: File): Uri {
        val resolver = getApplication<Application>().contentResolver
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, "merged_$stamp.mp4")
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/Video Merger")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: error("MediaStore insert failed")
        try {
            resolver.openOutputStream(uri)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri
    }

    override fun onCleared() {
        exporter.cancel()
    }
}
