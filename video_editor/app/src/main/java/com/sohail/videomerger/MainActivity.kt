package com.sohail.videomerger

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isVisible
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.ChipGroup
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.materialswitch.MaterialSwitch
import com.google.android.material.progressindicator.LinearProgressIndicator
import com.google.android.material.slider.RangeSlider
import kotlin.math.roundToLong

class MainActivity : AppCompatActivity(), ClipAdapter.Actions {
    private val viewModel: EditorViewModel by viewModels()
    private val adapter = ClipAdapter(this)

    private lateinit var empty: TextView
    private lateinit var total: TextView
    private lateinit var resolutions: ChipGroup
    private lateinit var mute: MaterialSwitch
    private lateinit var progress: LinearProgressIndicator
    private lateinit var status: TextView
    private lateinit var addButton: Button
    private lateinit var mergeButton: Button
    private lateinit var cancelButton: Button
    private lateinit var resultRow: View
    private lateinit var playButton: Button
    private lateinit var shareButton: Button
    private lateinit var soundInfo: TextView
    private lateinit var soundAdd: Button
    private lateinit var soundTrim: View
    private lateinit var soundRemove: View
    private lateinit var soundLoop: MaterialSwitch

    private val pickVideos = registerForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { uris ->
        viewModel.addVideos(uris)
    }

    private val pickSoundVideo = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let(viewModel::setAudio)
    }

    private val pickSoundFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(viewModel::setAudio)
    }

    private val resolutionChips = mapOf(
        R.id.res_1080 to Resolution.P1080,
        R.id.res_1440 to Resolution.P1440,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.root)) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            WindowInsetsCompat.CONSUMED
        }

        empty = findViewById(R.id.empty)
        total = findViewById(R.id.total)
        resolutions = findViewById(R.id.resolutions)
        mute = findViewById(R.id.mute)
        progress = findViewById(R.id.progress)
        status = findViewById(R.id.status)
        addButton = findViewById(R.id.add)
        mergeButton = findViewById(R.id.merge)
        cancelButton = findViewById(R.id.cancel)
        resultRow = findViewById(R.id.result_row)
        playButton = findViewById(R.id.play)
        shareButton = findViewById(R.id.share)
        soundInfo = findViewById(R.id.sound_info)
        soundAdd = findViewById(R.id.sound_add)
        soundTrim = findViewById(R.id.sound_trim)
        soundRemove = findViewById(R.id.sound_remove)
        soundLoop = findViewById(R.id.sound_loop)

        findViewById<RecyclerView>(R.id.clips).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = this@MainActivity.adapter
        }

        resolutionChips.entries.first { it.value == viewModel.resolution }.let { resolutions.check(it.key) }
        resolutions.setOnCheckedStateChangeListener { _, ids ->
            resolutionChips[ids.firstOrNull()]?.let {
                viewModel.resolution = it
                viewModel.resetExport()
            }
        }
        mute.isChecked = viewModel.muteAudio
        mute.setOnCheckedChangeListener { _, checked ->
            viewModel.muteAudio = checked
            viewModel.resetExport()
            renderAudio(viewModel.audio.value)
        }

        soundAdd.setOnClickListener { chooseSound() }
        soundRemove.setOnClickListener { viewModel.removeAudio() }
        soundTrim.setOnClickListener {
            val audio = viewModel.audio.value ?: return@setOnClickListener
            showTrimDialog(audio.name, audio.durationMs, audio.trimStartMs, audio.trimEndMs, viewModel::trimAudio)
        }
        soundLoop.setOnCheckedChangeListener { _, checked ->
            if (viewModel.audio.value?.loop != checked) viewModel.setAudioLoop(checked)
        }

        addButton.setOnClickListener {
            pickVideos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
        }
        mergeButton.setOnClickListener { viewModel.startExport() }
        cancelButton.setOnClickListener { viewModel.cancelExport() }

        viewModel.clips.observe(this) { clips ->
            // Moves keep item contents equal, so rebind everything to refresh the numbering.
            adapter.submitList(clips) { adapter.notifyItemRangeChanged(0, adapter.itemCount) }
            empty.isVisible = clips.isEmpty()
            total.text = getString(R.string.total, clips.size, formatDuration(clips.sumOf { it.keptMs }))
            renderExport(viewModel.export.value ?: ExportState.Idle)
        }
        viewModel.audio.observe(this, ::renderAudio)
        viewModel.export.observe(this, ::renderExport)
        viewModel.message.observe(this) { text ->
            if (text != null) {
                Toast.makeText(this, text, Toast.LENGTH_LONG).show()
                viewModel.message.value = null
            }
        }
    }

    private fun renderExport(state: ExportState) {
        val running = state is ExportState.Running
        val hasClips = viewModel.clips.value.orEmpty().isNotEmpty()

        adapter.enabled = !running
        addButton.isEnabled = !running
        mergeButton.isEnabled = !running && hasClips
        mergeButton.text = getString(if (hasClips && viewModel.clips.value!!.size == 1) R.string.save_one else R.string.merge)
        cancelButton.isVisible = running
        mute.isEnabled = !running
        listOf(soundAdd, soundTrim, soundRemove, soundLoop).forEach { it.isEnabled = !running }
        for (i in 0 until resolutions.childCount) resolutions.getChildAt(i).isEnabled = !running

        progress.isVisible = running
        if (state is ExportState.Running) progress.setProgressCompat(state.percent, true)
        resultRow.isVisible = state is ExportState.Done
        status.isVisible = state !is ExportState.Idle
        status.text = when (state) {
            is ExportState.Running -> getString(R.string.exporting, state.percent)
            is ExportState.Done -> getString(R.string.saved)
            is ExportState.Failed -> getString(R.string.failed, state.message)
            ExportState.Idle -> ""
        }

        if (running) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        if (state is ExportState.Done) {
            playButton.setOnClickListener { open(Intent(Intent.ACTION_VIEW).setDataAndType(state.uri, "video/mp4")) }
            shareButton.setOnClickListener {
                val send = Intent(Intent.ACTION_SEND).setType("video/mp4").putExtra(Intent.EXTRA_STREAM, state.uri)
                open(Intent.createChooser(send, getString(R.string.share)))
            }
        }
    }

    private fun renderAudio(audio: AudioSource?) {
        // The ViewModel may switch "remove the clips' own sound" on when a sound is added.
        if (mute.isChecked != viewModel.muteAudio) mute.isChecked = viewModel.muteAudio
        soundTrim.isVisible = audio != null
        soundRemove.isVisible = audio != null
        soundLoop.isVisible = audio != null
        soundAdd.setText(if (audio == null) R.string.sound_add else R.string.sound_replace)
        soundInfo.text = when {
            audio != null -> getString(
                R.string.sound_info,
                audio.name,
                if (audio.isTrimmed) {
                    "${formatDuration(audio.trimStartMs, tenths = true)}–${formatDuration(audio.trimEndMs, tenths = true)}"
                } else {
                    formatDuration(audio.durationMs)
                },
                getString(if (viewModel.muteAudio) R.string.sound_replaces else R.string.sound_mixed),
            )
            viewModel.muteAudio -> getString(R.string.sound_none)
            else -> getString(R.string.sound_original)
        }
        if (audio != null && soundLoop.isChecked != audio.loop) soundLoop.isChecked = audio.loop
    }

    private fun chooseSound() {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.sound_pick_title)
            .setItems(arrayOf(getString(R.string.sound_from_video), getString(R.string.sound_from_audio))) { _, which ->
                if (which == 0) {
                    pickSoundVideo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
                } else {
                    pickSoundFile.launch(arrayOf("audio/*"))
                }
            }
            .show()
    }

    private fun open(intent: Intent) {
        try {
            startActivity(intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, R.string.no_app, Toast.LENGTH_SHORT).show()
        }
    }

    override fun moveUp(position: Int) = viewModel.move(position, position - 1)

    override fun moveDown(position: Int) = viewModel.move(position, position + 1)

    override fun rotate(clip: Clip) = viewModel.rotate(clip.id)

    override fun remove(clip: Clip) = viewModel.remove(clip.id)

    override fun trim(clip: Clip) =
        showTrimDialog(clip.name, clip.durationMs, clip.trimStartMs, clip.trimEndMs) { start, end ->
            viewModel.trim(clip.id, start, end)
        }

    private fun showTrimDialog(
        name: String,
        durationMs: Long,
        startMs: Long,
        endMs: Long,
        onApply: (startMs: Long, endMs: Long) -> Unit,
    ) {
        val view = layoutInflater.inflate(R.layout.dialog_trim, null)
        val slider: RangeSlider = view.findViewById(R.id.range)
        val summary: TextView = view.findViewById(R.id.trim_summary)
        val seconds = durationMs / 1000f

        slider.valueFrom = 0f
        slider.valueTo = seconds
        if (seconds > 0.2f) slider.setMinSeparationValue(0.1f)
        slider.values = listOf(startMs / 1000f, endMs / 1000f)
        slider.setLabelFormatter { formatDuration((it * 1000).roundToLong(), tenths = true) }

        fun showSummary() {
            val (start, end) = slider.values.map { (it * 1000).roundToLong() }
            summary.text = getString(
                R.string.trim_summary,
                formatDuration(start, tenths = true),
                formatDuration(end, tenths = true),
                formatDuration(end - start, tenths = true),
            )
        }
        showSummary()
        slider.addOnChangeListener { _, _, _ -> showSummary() }

        MaterialAlertDialogBuilder(this)
            .setTitle(getString(R.string.trim_title, name))
            .setView(view)
            .setPositiveButton(R.string.apply) { _, _ ->
                val (start, end) = slider.values.map { (it * 1000).roundToLong().coerceIn(0, durationMs) }
                onApply(start, maxOf(end, start + 100).coerceAtMost(durationMs))
            }
            .setNeutralButton(R.string.reset) { _, _ -> onApply(0, durationMs) }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }
}
