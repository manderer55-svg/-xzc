# Ashen Veil sound

The earlier mathematical beeps/noise and 32-second synth pad have been replaced.
The game streams a 99-second original, sample-based chamber score (harp, cello,
soft strings and flute). Sound effects use licensed impact and glass samples,
with individual layering, pitch/tonal shaping, short fades and several variations.
This is sample-based sound design and composition, not neural audio generation.

- [Background excerpt](preview-music.ogg)
- [Effect audition](preview-effects.ogg)
- [Actual Godot mix](preview-gameplay.ogg)
- [Music rendering and licence](MUSIC_LICENSE.md)
- [Effect sources and licence](SFX_LICENSES.md)

The runtime keeps eight pooled effect players but permits at most three audible
voices, including at most two heavy effects. Identical specials in one burst are
coalesced; quieter ordinary tails yield to special effects and victory. Music is
ducked briefly during specials. Music/SFX buses leave headroom, and the Master
limiter has a -1.5 dB safety ceiling. Pausing/muting preserves the music position;
resuming fades it back in. No new players are created during cascades.

The music is stereo 44.1 kHz Vorbis at roughly -22 LUFS / -9.8 dB true peak.
Effects are stereo 48 kHz PCM WAV with peaks from -12 to -8 dBFS. Preview files
and development metrics/sources are excluded from Android export; licence texts
are included. The development SoundFont is not shipped.

The technical checks demonstrate bounded levels, finite tails and lifecycle
behavior. They do not establish a subjective quality score, and are not a
substitute for listening on the player's phone/headphones. Use the previews to
judge the timbre before making another APK.

[Independent technical review](../docs/AUDIO_REVIEW.md) records the final checks and controlled Godot mixer recording.
