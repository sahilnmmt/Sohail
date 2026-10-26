# Video Merger (Android)

A small Android app to join several videos into one and do simple edits:

- **Merge:** pick any number of videos from the gallery; they are joined in the order shown. Move clips up or down to reorder.
- **Trim:** keep only part of each clip (range slider, to a tenth of a second).
- **Rotate:** turn a clip by 90° at a time.
- **Output size:** 1080p (Full HD) or 1440p (2K). Smaller clips are scaled up, so output is never below 1080p. The first clip sets landscape or portrait; clips of another shape get black bars.
- **Sound from another file:** take the picture from your clips and the sound from a different video or an audio file (MP3, M4A, WAV…). Trim the sound, repeat it if it is shorter than the video, and either replace the clips' own sound or mix both. The sound stops when the video ends.
- **Remove the clips' own sound:** export without it. Clips without sound can be mixed with clips that have it.
- **Save, play and share:** the result goes to *Movies/Video Merger* in the gallery.

Exports run on the phone's hardware video encoder with
[Media3 Transformer](https://developer.android.com/media/media3/transformer)
(H.264 video, AAC audio, MP4). Nothing is uploaded anywhere.

## Install the APK
On your Android phone, open
**https://github.com/sahilnmmt/Sohail/releases/download/video-merger-latest/video-merger.apk**
and open the downloaded file. Android asks you to allow installing apps from
your browser the first time. CI updates the `video-merger-latest` pre-release
after every push; each Actions run also keeps the APK as the `video-merger-apk`
artifact.

The APK is signed with a debug key made fresh on each CI run, so to install a
newer build over an older one you may need to uninstall the old one first. For
Google Play, or for smooth updates, sign it with your own key.

Needs Android 10 or newer.

## Build it yourself
With the Android SDK installed (or Android Studio):

```sh
cd video_editor
./gradlew assembleRelease   # app/build/outputs/apk/release/app-release.apk
./gradlew testReleaseUnitTest
```

## Code
| File | What it does |
|---|---|
| `MainActivity.kt` | Screen: clip list, trim dialog, export settings and buttons |
| `EditorViewModel.kt` | Clip list and edits, runs the export, saves to the gallery |
| `CompositionFactory.kt` | Turns the clips into one Media3 sequence with trim, rotate and resize, plus a sound-only sequence for an added sound |
| `Exporter.kt` | Runs Media3 Transformer and reports progress |
| `ClipLoader.kt` | Reads a video's length, size and thumbnail, or a sound file's length |
