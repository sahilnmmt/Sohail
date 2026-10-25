package com.sohail.videomerger

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView

class ClipAdapter(private val actions: Actions) : ListAdapter<Clip, ClipAdapter.Holder>(Diff) {

    interface Actions {
        fun moveUp(position: Int)
        fun moveDown(position: Int)
        fun trim(clip: Clip)
        fun rotate(clip: Clip)
        fun remove(clip: Clip)
    }

    /** Editing is switched off while an export runs. */
    var enabled = true
        set(value) {
            if (field != value) {
                field = value
                notifyItemRangeChanged(0, itemCount)
            }
        }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        Holder(LayoutInflater.from(parent.context).inflate(R.layout.item_clip, parent, false))

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(getItem(position), position)

    inner class Holder(view: View) : RecyclerView.ViewHolder(view) {
        private val thumbnail: ImageView = view.findViewById(R.id.thumbnail)
        private val title: TextView = view.findViewById(R.id.title)
        private val details: TextView = view.findViewById(R.id.details)
        private val up: ImageButton = view.findViewById(R.id.move_up)
        private val down: ImageButton = view.findViewById(R.id.move_down)
        private val trim: ImageButton = view.findViewById(R.id.trim)
        private val rotate: ImageButton = view.findViewById(R.id.rotate)
        private val remove: ImageButton = view.findViewById(R.id.remove)

        fun bind(clip: Clip, position: Int) {
            thumbnail.setImageBitmap(clip.thumbnail)
            thumbnail.rotation = clip.rotation.toFloat()
            title.text = itemView.context.getString(R.string.clip_title, position + 1, clip.name)
            details.text = buildString {
                append(formatDuration(clip.keptMs))
                if (clip.isTrimmed) {
                    append(" · trimmed ")
                    append(formatDuration(clip.trimStartMs, tenths = true))
                    append("–")
                    append(formatDuration(clip.trimEndMs, tenths = true))
                }
                if (clip.rotation != 0) append(" · rotated ${clip.rotation}°")
                append(" · ${clip.outputWidth}×${clip.outputHeight}")
            }

            up.isEnabled = enabled && position > 0
            down.isEnabled = enabled && position < itemCount - 1
            listOf(up, down).forEach { it.alpha = if (it.isEnabled) 1f else 0.3f }
            listOf(trim, rotate, remove).forEach { it.isEnabled = enabled }

            up.setOnClickListener { bindingAdapterPosition.takeIf { it != RecyclerView.NO_POSITION }?.let(actions::moveUp) }
            down.setOnClickListener { bindingAdapterPosition.takeIf { it != RecyclerView.NO_POSITION }?.let(actions::moveDown) }
            trim.setOnClickListener { actions.trim(clip) }
            rotate.setOnClickListener { actions.rotate(clip) }
            remove.setOnClickListener { actions.remove(clip) }
        }
    }

    private object Diff : DiffUtil.ItemCallback<Clip>() {
        override fun areItemsTheSame(oldItem: Clip, newItem: Clip) = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: Clip, newItem: Clip) = oldItem == newItem
    }
}
