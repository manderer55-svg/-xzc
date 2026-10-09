# Fantasy sound effects

The six previous mathematical effects have been replaced by eleven effects
designed from Kenney's **Impact Sounds** samples. These are sample-based audio
assets with edited timing, pitch, layers, equalization, and room reflections.
They are not outputs from a neural audio generator. The original source pack's
recording method is not independently verified here.

Kenney dedicates the pack under **CC0 1.0 Universal**, permitting commercial use,
editing, and redistribution. Full license: [Kenney-Impact.txt](licenses/Kenney-Impact.txt).

- Original pack: <https://kenney.nl/assets/impact-sounds>
- Downloaded mirror: <https://github.com/Boyquotes/kenney-impact-sounds-for-godot>
- Exact mirror revision: `999dd1684873f8b020a3aa5b26e713da21688924`
- Unmodified source samples, per-file SHA256 hashes, and license:
  [tools/audio_sources/kenney_impact](../tools/audio_sources/kenney_impact/).
  The source folder has `.gdignore` and is excluded from Godot imports/exports.

| Game effect | Source material | Design |
| --- | --- | --- |
| `tap.wav` | `impact_wood_light_003` | Short warm wooden tick; no oscillator beep. |
| `match.wav`, `match_2.wav`, `match_3.wav` | `impact_glass_medium_000/001/002`, `impact_glass_light_000/002/004`, `impact_wood_light_003` | Rounded glass strikes, quiet fragments, three distinct variations. |
| `cascade.wav`, `cascade_2.wav` | `impact_glass_medium_000/001/002` | Three restrained overlapping strikes with falling gain. |
| `lightning.wav`, `lightning_2.wav` | `impact_metal_heavy_000/003`, `impact_glass_heavy_000/002`, `impact_plank_medium_000`, `impact_soft_heavy_000/002/003` | Dark short crack and rolling low impact body; a warm middle range for phone speakers. This is designed thunder-like audio, not a field recording of thunder. |
| `explosion.wav`, `explosion_2.wav` | `impact_soft_heavy_000/002/003`, `impact_wood_heavy_000/002`, `impact_plank_medium_000`, `impact_glass_heavy_000/002`, `impact_glass_medium_000/001` | Rounded low impact, wooden body, restrained glass debris, finite tail. |
| `victory.wav` | `impact_bell_heavy_002` | Quiet bell flourish whose strongest partials follow D–A–C–F, matching the D-minor background. |

Every game file is 48 kHz, stereo, signed 16-bit PCM. Peaks are between −12 and
−8 dBFS; their starts and tails fade to zero. The recipe never generates white
noise, uses no oscillator tones, and adds no endless ringing feedback.

Rebuild without network access, using Python with numpy/scipy and ffmpeg:

```bash
python3 tools/sound_effects.py --audition audio/preview-effects.ogg
```

[sfx_metrics.json](sfx_metrics.json) records checksums, peaks, RMS, high frequency
energy, and EBU integrated loudness. Because a single short tick is shorter than
an EBU measurement block, loudness is measured on twelve exact repetitions
without gaps. These figures characterize the source files; the game mixer
applies additional gain and limits simultaneous sounds.

The roughly 20-second [preview-effects.ogg](preview-effects.ogg) reel contains
the effects at their source-file levels, with quiet gaps. Its timestamp list is
[preview-effects.json](preview-effects.json). It is for reviewing the sound
design and is excluded from the game export.

| Start | Effect |
| --- | --- |
| 0.35 s | UI tap |
| 1.12 / 2.35 / 3.58 s | Three crystal match variants |
| 4.81 / 6.32 s | Two cascade variants |
| 7.83 / 10.03 s | Two lightning variants |
| 12.23 / 14.48 s | Two bomb variants |
| 16.73 s | Victory bells |

Measurements do not substitute for listening. No subjective claim that the
effects sound good on a physical Android speaker is made by this build script.
