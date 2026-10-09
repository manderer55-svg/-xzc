#!/usr/bin/env python3
"""Render the original Ashen Veil chamber score with a supplied sample bank.

Requires NumPy, SciPy, libfluidsynth and ffmpeg. The SoundFont is a development
dependency, not shipped in the game. See audio/MUSIC_LICENSE.md.
"""
import argparse
import ctypes as C
import json
import re
import subprocess
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 44100
BEAT = 60 / 58
BAR = 4 * BEAT
BARS = 24
LOOP = BARS * BAR


class Sampler:
    def __init__(self, bank):
        self.lib = C.CDLL("libfluidsynth.so.3")
        signatures = {
            "new_fluid_settings": (C.c_void_p, []),
            "fluid_settings_setnum": (C.c_int, [C.c_void_p, C.c_char_p, C.c_double]),
            "fluid_settings_setint": (C.c_int, [C.c_void_p, C.c_char_p, C.c_int]),
            "new_fluid_synth": (C.c_void_p, [C.c_void_p]),
            "fluid_synth_sfload": (C.c_int, [C.c_void_p, C.c_char_p, C.c_int]),
            "fluid_synth_program_change": (C.c_int, [C.c_void_p, C.c_int, C.c_int]),
            "fluid_synth_cc": (C.c_int, [C.c_void_p, C.c_int, C.c_int, C.c_int]),
            "fluid_synth_noteon": (C.c_int, [C.c_void_p, C.c_int, C.c_int, C.c_int]),
            "fluid_synth_noteoff": (C.c_int, [C.c_void_p, C.c_int, C.c_int]),
            "fluid_synth_write_float": (C.c_int, [C.c_void_p, C.c_int, C.c_void_p, C.c_int, C.c_int, C.c_void_p, C.c_int, C.c_int]),
            "delete_fluid_synth": (None, [C.c_void_p]),
            "delete_fluid_settings": (None, [C.c_void_p]),
        }
        for name, (result, arguments) in signatures.items():
            fn = getattr(self.lib, name)
            fn.restype, fn.argtypes = result, arguments
        self.settings = self.lib.new_fluid_settings()
        for name, value in {"synth.sample-rate": RATE, "synth.gain": 0.35,
                            "synth.reverb.room-size": 0.72, "synth.reverb.damp": 0.7,
                            "synth.reverb.width": 18, "synth.reverb.level": 0.22}.items():
            self.lib.fluid_settings_setnum(self.settings, name.encode(), value)
        self.lib.fluid_settings_setint(self.settings, b"synth.chorus.active", 0)
        self.synth = self.lib.new_fluid_synth(self.settings)
        if self.lib.fluid_synth_sfload(self.synth, str(bank).encode(), 1) < 0:
            raise RuntimeError("SoundFont could not be loaded")

    def samples(self, count):
        block = np.zeros((count, 2), dtype=np.float32)
        self.lib.fluid_synth_write_float(self.synth, count, block.ctypes.data, 0, 2,
                                        block.ctypes.data, 1, 2)
        return block

    def close(self):
        self.lib.delete_fluid_synth(self.synth)
        self.lib.delete_fluid_settings(self.settings)


def score():
    """Three related eight-bar phrases, with space between melodic gestures."""
    events = []
    rng = np.random.default_rng(20261009)

    def note(channel, pitch, beat, length, velocity):
        # Tiny timing/velocity deviations, never change the loop length.
        at = max(0.0, beat * BEAT + float(rng.uniform(-0.018, 0.018)))
        events.append((at, "on", channel, pitch, int(np.clip(velocity + rng.integers(-3, 4), 1, 100))))
        events.append((min(LOOP - 0.015, at + length * BEAT), "off", channel, pitch, 0))

    # GM harp, cello, slow strings, breathy low flute; no electronic pad/beeper.
    programs = {0: 46, 1: 42, 2: 49, 3: 73}
    volumes = {0: 68, 1: 58, 2: 36, 3: 44}
    pans = {0: 43, 1: 75, 2: 64, 3: 57}
    # Dm(add9), Bbmaj7, Fmaj9, Cadd9, Gm9, Dm/A, Bbmaj7, Asus4 -> Dm.
    harmony = [([50, 57, 60, 65, 69, 76], 38),
               ([46, 53, 57, 62, 65, 69], 34),
               ([48, 53, 57, 60, 64, 67], 41),
               ([48, 55, 60, 62, 67, 72], 36),
               ([43, 50, 53, 57, 62, 65], 43),
               ([45, 50, 57, 60, 65, 69], 33),
               ([46, 53, 57, 62, 65, 69], 34),
               ([45, 52, 57, 62, 64, 69], 33)]
    patterns = ([0, 2, 3, 1, 4, 2], [0, 3, 2, 4, 1, 3], [1, 3, 4, 2, 3, 1])
    for bar in range(BARS):
        chord, bass = harmony[bar % 8]
        pattern = patterns[(bar // 8) % 3]
        # Deliberately incomplete arpeggios leave the effects room to speak.
        for i, tone in enumerate(pattern):
            note(0, chord[tone], bar * 4 + i * 0.6, 1.05, 44 if i else 51)
        note(1, bass, bar * 4 + 0.08, 3.7, 41)
        if bar % 2 == 0:
            for pitch in chord[1:4]:
                note(2, pitch, bar * 4 + 0.14, 7.55, 32)
    # Original answer-and-response motif. Flute stays in its warm lower register.
    motifs = [
        [(0.3, 69, 1.35), (2.2, 65, 1.5), (4.2, 62, 2.8), (8.3, 65, 1.3), (10.2, 67, 1.45), (12.2, 69, 2.9),
         (16.3, 67, 1.3), (18.2, 65, 1.3), (20.2, 62, 2.8), (24.3, 60, 1.4), (26.2, 62, 3.8)],
        [(1.0, 65, 2.0), (4.2, 69, 1.3), (6.0, 72, 1.6), (8.2, 69, 2.8), (12.3, 67, 3.1),
         (17.0, 65, 1.5), (19.2, 62, 2.7), (24.2, 64, 1.4), (26.2, 62, 3.0)],
        [(0.3, 69, 1.4), (2.3, 65, 1.4), (4.2, 62, 2.7), (9.0, 65, 1.4), (11.0, 67, 2.5),
         (16.3, 65, 1.6), (19.0, 62, 2.2), (24.0, 60, 1.5), (26.0, 62, 3.3)],
    ]
    for phrase, motif in enumerate(motifs):
        for beat, pitch, duration in motif:
            note(3, pitch, phrase * 32 + beat, duration, 40)
    return sorted(events), programs, volumes, pans


def render(bank, output):
    synth = Sampler(bank)
    events, programs, volumes, pans = score()
    for ch, program in programs.items():
        synth.lib.fluid_synth_program_change(synth.synth, ch, program)
        synth.lib.fluid_synth_cc(synth.synth, ch, 7, volumes[ch])
        synth.lib.fluid_synth_cc(synth.synth, ch, 10, pans[ch])
        synth.lib.fluid_synth_cc(synth.synth, ch, 91, 36)
    chunks, cursor = [], 0
    # Render twice so the second cycle includes natural reverb/release from the
    # preceding loop; fold its final tail onto the head for sample-continuity.
    for cycle in range(2):
        for at, kind, channel, pitch, velocity in events:
            target = round((cycle * LOOP + at) * RATE)
            if target > cursor:
                chunks.append(synth.samples(target - cursor))
                cursor = target
            fn = synth.lib.fluid_synth_noteon if kind == "on" else synth.lib.fluid_synth_noteoff
            if kind == "on":
                fn(synth.synth, channel, pitch, velocity)
            else:
                fn(synth.synth, channel, pitch)
    end = round((2 * LOOP + 6) * RATE)
    chunks.append(synth.samples(end - cursor))
    synth.close()
    audio = np.concatenate(chunks)
    start, length = round(LOOP * RATE), round(LOOP * RATE)
    audio = audio[start:start + length].astype(np.float64)
    # Very gentle tonal shaping, no buzzy oscillator beds or hard clipping.
    audio = sosfilt(butter(2, 65, btype="highpass", fs=RATE, output="sos"), audio, axis=0)
    audio = sosfilt(butter(2, 6800, fs=RATE, output="sos"), audio, axis=0)
    # An 80ms boundary crossfade prevents a DC/sample-step click.
    seam = round(0.08 * RATE)
    weight = np.linspace(0, 1, seam)[:, None]
    blend = audio[-seam:] * (1 - weight) + audio[:seam] * weight
    audio = np.concatenate([audio[seam:-seam], blend])
    peak = np.max(np.abs(audio))
    audio *= 0.42 / max(peak, 1e-9)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".render.wav")
    wavfile.write(temporary, RATE, np.round(audio * 32767).astype(np.int16))
    measured = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(temporary),
                               "-af", "loudnorm=I=-22:TP=-6:LRA=7:print_format=json",
                               "-f", "null", "-"], capture_output=True, text=True, check=True)
    metrics = json.loads(re.findall(r"\{[^{}]+\}", measured.stderr)[-1])
    gain = min(-22 - float(metrics["input_i"]), -6.5 - float(metrics["input_tp"]))
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y", "-i", str(temporary),
                    "-af", f"volume={gain:.4f}dB", "-ar", str(RATE),
                    "-c:a", "libvorbis", "-q:a", "5", str(output)], check=True)
    print(f"Master gain {gain:.2f}dB; measured input {metrics['input_i']}LUFS")
    temporary.unlink()
    print(f"Rendered original 24-bar, {len(audio) / RATE:.2f}s stereo score: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--soundfont", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("audio/ambient.ogg"))
    args = parser.parse_args()
    render(args.soundfont, args.output)
