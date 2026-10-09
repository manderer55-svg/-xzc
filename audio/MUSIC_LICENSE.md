# Background score

`ambient.ogg` is an original 24-bar chamber composition for Ashen Veil, D minor,
58 BPM, approximately 99.23 seconds, stereo 44.1 kHz Vorbis. It uses harp, cello,
quiet bowed strings and low flute recorded-instrument samples. It is not an
output from a neural music-generation service and uses no pre-existing melody
or demo MIDI from the sample-bank repository.

Rendered using FluidSynth and **GeneralUser GS 2.0.3**, by S. Christian Collins.
The bank licence permits unrestricted private/commercial music creation; the
complete upstream licence is preserved in [licenses/GeneralUser-GS.txt](licenses/GeneralUser-GS.txt).
The SoundFont itself is not distributed with the game.

Pinned development source: https://github.com/mrbumpy409/GeneralUser-GS/tree/684543d5e5efaef08d02be50dcda8d552478fa60

SoundFont SHA-256: `9575028c7a1f589f5770fccc8cff2734566af40cd26ed836944e9a5152688cfe`.

To reproduce with NumPy, SciPy, libfluidsynth and ffmpeg installed:

```sh
python3 tools/compose_music.py --soundfont /path/to/GeneralUser-GS.sf2
```

Rendering uses natural sample releases/reverb from a preceding cycle, a short
loop crossfade, gentle 65 Hz/6.8 kHz filtering and constant-gain mastering at
approximately -22 LUFS with true peak below -6 dB. This avoids a compressor
pumping the background during quiet phrases. The runtime streams the OGG;
it does not load the 31 MB development instrument bank.
