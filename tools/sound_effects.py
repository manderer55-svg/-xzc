#!/usr/bin/env python3
"""Rebuild restrained fantasy effects from the bundled CC0 Kenney samples.

No oscillator tones, random-noise generators, downloaded-at-runtime assets, or
neural generation are involved. The unmodified sources, hashes, and license are
in tools/audio_sources/kenney_impact/. Requires Python numpy/scipy and ffmpeg.
"""
from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re
import subprocess
import wave

import numpy as np
from scipy import ndimage, signal

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/audio_sources/kenney_impact"
RATE = 48000
OUTPUT = ROOT / "audio"


def decode(name: str) -> np.ndarray:
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(SOURCE / (name + ".ogg")),
        "-ac", "1", "-ar", str(RATE), "-f", "f32le", "pipe:1",
    ])
    x = np.frombuffer(data, dtype="<f4").astype(np.float64)
    # Original Vorbis files can decode over 0 dBFS; work in float, never clip.
    x /= max(float(np.max(np.abs(x))), 1e-9)
    # Remove leading codec padding, preserving 2 ms before the first impact.
    hits = np.flatnonzero(np.abs(x) > 0.008)
    if len(hits):
        x = x[max(0, int(hits[0]) - int(0.002 * RATE)):]
    return x


def sample(name: str, speed: float = 1.0, high: float = 4500.0,
           low: float = 45.0) -> np.ndarray:
    x = decode(name)
    ratio = Fraction(1.0 / speed).limit_denominator(1000)
    x = signal.resample_poly(x, ratio.numerator, ratio.denominator)
    x = signal.sosfilt(signal.butter(2, low, btype="highpass", fs=RATE,
                                  output="sos"), x)
    x = signal.sosfilt(signal.butter(3, high, btype="lowpass", fs=RATE,
                                  output="sos"), x)
    # A recorded click should not become a needle-shaped peak. This gentle,
    # feed-forward compressor tames the first few milliseconds of hard impacts.
    envelope = ndimage.maximum_filter1d(np.abs(x), size=721, mode="nearest")
    envelope = ndimage.gaussian_filter1d(envelope, sigma=180)
    gain = np.minimum(1.0, np.power(np.maximum(envelope / 0.20, 1.0), -0.55))
    x *= gain
    fade = min(int(0.002 * RATE), len(x) // 3)
    if fade:
        x[:fade] *= np.linspace(0, 1, fade)
    tail = min(int(0.035 * RATE), len(x) // 3)
    if tail:
        x[-tail:] *= np.linspace(1, 0, tail)
    peak = float(np.max(np.abs(x)))
    return x / max(peak, 1e-9)


def put(canvas: np.ndarray, x: np.ndarray, at: float, gain: float,
        pan: float = 0.0) -> None:
    start = int(at * RATE)
    count = min(len(x), len(canvas) - start)
    if count <= 0:
        return
    # Modest stereo spread also folds down cleanly on a phone speaker.
    left = np.sqrt((1.0 - pan) * 0.5)
    right = np.sqrt((1.0 + pan) * 0.5)
    canvas[start:start + count, 0] += x[:count] * gain * left
    canvas[start:start + count, 1] += x[:count] * gain * right


def room(canvas: np.ndarray, amount: float) -> np.ndarray:
    dry = canvas.copy()
    result = canvas.copy()
    # Quiet, filtered early reflections; finite taps cannot ring indefinitely.
    for delay, gain in [(0.041, 0.29), (0.073, 0.23), (0.113, 0.17),
                        (0.179, 0.12), (0.251, 0.07), (0.337, 0.04)]:
        n = int(delay * RATE)
        damped = signal.sosfilt(signal.butter(2, 2600, fs=RATE,
                                            output="sos"), dry, axis=0)
        result[n:] += damped[:-n, ::-1] * gain * amount
    return result


def write(name: str, canvas: np.ndarray, peak_db: float,
          room_amount: float = 0.0) -> dict:
    x = room(canvas, room_amount)
    x -= np.mean(x, axis=0)
    fade_in = int(0.003 * RATE)
    fade_out = min(int(0.120 * RATE), len(x) // 4)
    x[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
    x[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None]
    x *= 10 ** (peak_db / 20) / max(float(np.max(np.abs(x))), 1e-9)
    pcm = np.round(x * 32767).astype("<i2")
    path = OUTPUT / (name + ".wav")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    frequencies = np.fft.rfftfreq(len(x), 1 / RATE)
    power = np.sum(np.abs(np.fft.rfft(x, axis=0)) ** 2, axis=1)
    # A single 220-ms tap is shorter than an EBU measurement block. Measure
    # twelve exact repetitions, without gaps, consistently for every asset.
    measured = subprocess.run([
        "ffmpeg", "-hide_banner", "-v", "info", "-f", "s16le", "-ar", str(RATE),
        "-ac", "2", "-i", "pipe:0", "-af",
        "loudnorm=I=-20:TP=-2:LRA=7:print_format=json", "-f", "null", "-",
    ], input=pcm.tobytes() * 12, capture_output=True, check=True)
    matches = re.findall(r'\{\s*"input_i"[\s\S]*?\}', measured.stderr.decode())
    loudness = json.loads(matches[-1])
    return {
        "file": path.name, "seconds": len(x) / RATE,
        "peak_dbfs": round(20 * np.log10(np.max(np.abs(x))), 2),
        "rms_dbfs": round(20 * np.log10(np.sqrt(np.mean(x * x))), 2),
        "energy_above_4khz_percent": round(float(
            100 * np.sum(power[frequencies > 4000]) / np.sum(power)), 4),
        "lufs_i_twelve_repetitions": float(loudness["input_i"]),
        "true_peak_dbfs": float(loudness["input_tp"]),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def canvas(seconds: float) -> np.ndarray:
    return np.zeros((round(seconds * RATE), 2), dtype=np.float64)


def build() -> list[dict]:
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    for entry in manifest["files"]:
        actual = hashlib.sha256((SOURCE / entry["file"]).read_bytes()).hexdigest()
        if actual != entry["sha256"]:
            raise RuntimeError("Source checksum mismatch: " + entry["file"])
    OUTPUT.mkdir(exist_ok=True)
    result = []

    x = canvas(0.22)
    put(x, sample("impact_wood_light_003", high=2400), 0, 1)
    result.append(write("tap", x, -12))

    for i in range(3):
        x = canvas(0.68)
        put(x, sample(f"impact_glass_medium_{i:03}", speed=0.96,
                      high=3900), 0, 0.68, -0.10)
        light_index = [0, 2, 4][i]
        put(x, sample(f"impact_glass_light_{light_index:03}", speed=0.94,
                      high=4100), 0.027, 0.27, 0.13)
        put(x, sample("impact_wood_light_003", speed=0.86, high=1700),
            0.005, 0.10)
        name = "match" if i == 0 else f"match_{i + 1}"
        result.append(write(name, x, -9, 0.18))

    for i in range(2):
        x = canvas(0.96)
        for j, offset in enumerate([0.0, 0.090, 0.190]):
            put(x, sample(f"impact_glass_medium_{(i + j) % 3:03}",
                          speed=[0.9, 1.0, 1.08][j], high=3600),
                offset, [0.58, 0.34, 0.19][j], [-0.12, 0.0, 0.12][j])
        result.append(write("cascade" if i == 0 else "cascade_2", x, -9, 0.24))

    for i in range(2):
        x = canvas(1.65)
        # The bolt is a short dark crack above a weighted, recorded impact body.
        # Three staggered lower impacts give a rolling tail, without hiss/noise.
        put(x, sample(f"impact_metal_heavy_{[0, 3][i]:03}",
                      speed=0.80, high=2200, low=120), 0, 0.70, -0.08)
        put(x, sample(f"impact_glass_heavy_{[0, 2][i]:03}",
                      speed=0.90, high=2300, low=180), 0.012, 0.43, 0.08)
        # A 190-Hz wooden body keeps the bolt audible on small phone speakers.
        put(x, sample("impact_plank_medium_000", speed=0.95,
                      high=1700, low=150), 0.026, 1.45)
        for j, (offset, speed, gain) in enumerate([
            (0.019, 0.85, 0.50), (0.162, 0.70, 0.24), (0.345, 0.58, 0.12),
        ]):
            index = [0, 2, 3][(i + j) % 3]
            put(x, sample(f"impact_soft_heavy_{index:03}", speed=speed,
                          high=1350, low=45), offset, gain, (j - 1) * 0.08)
        result.append(write("lightning" if i == 0 else "lightning_2", x, -8, 0.3))

    for i in range(2):
        x = canvas(1.70)
        put(x, sample(f"impact_soft_heavy_{[0, 2][i]:03}", speed=0.82,
                      high=1900, low=55), 0, 0.50)
        put(x, sample(f"impact_wood_heavy_{[0, 2][i]:03}", speed=0.78,
                      high=2500, low=85), 0.011, 0.25)
        put(x, sample("impact_plank_medium_000", speed=0.86,
                      high=2200, low=155), 0.015, 1.40)
        put(x, sample(f"impact_glass_heavy_{[0, 2][i]:03}", speed=0.83,
                      high=3200, low=180), 0.039, 0.60, -0.08)
        put(x, sample(f"impact_glass_medium_{i:03}", speed=0.78,
                      high=2600, low=180), 0.125, 0.20, 0.12)
        put(x, sample("impact_soft_heavy_003", speed=0.56,
                      high=1000, low=40), 0.23, 0.10)
        result.append(write("explosion" if i == 0 else "explosion_2", x, -8, 0.34))

    x = canvas(2.25)
    # Source bell's strongest partial is about 227 Hz. Tune its main partial
    # to D3, A3, C4, F3 so the flourish fits the background's D-minor harmony.
    for hz, at, gain, pan in [
        (146.832, 0.0, 0.58, -0.08), (220.0, 0.21, 0.43, 0.05),
        (261.626, 0.40, 0.34, 0.10), (174.614, 0.65, 0.47, -0.04),
    ]:
        put(x, sample("impact_bell_heavy_002", speed=hz / 227.0,
                      high=2500, low=90), at, gain, pan)
    result.append(write("victory", x, -11, 0.32))
    (OUTPUT / "sfx_metrics.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def audition(destination: Path) -> None:
    # A simple ordered reel with quiet gaps; it is not used by the game.
    names = ["tap", "match", "match_2", "match_3", "cascade", "cascade_2",
             "lightning", "lightning_2", "explosion", "explosion_2", "victory"]
    chunks = [np.zeros((int(0.35 * RATE), 2), dtype="<i2")]
    cue_sheet = []
    at = 0.35
    for name in names:
        with wave.open(str(OUTPUT / (name + ".wav")), "rb") as src:
            pcm = np.frombuffer(src.readframes(src.getnframes()), dtype="<i2")
            pcm = pcm.reshape(-1, 2)
        cue_sheet.append({"at_seconds": round(at, 2), "effect": name})
        chunks.extend([pcm, np.zeros((int(0.55 * RATE), 2), dtype="<i2")])
        at += len(pcm) / RATE + 0.55
    raw = np.concatenate(chunks).tobytes()
    subprocess.run([
        "ffmpeg", "-y", "-v", "error", "-f", "s16le", "-ar", str(RATE),
        "-ac", "2", "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "5",
        str(destination),
    ], input=raw, check=True)
    destination.with_suffix(".json").write_text(json.dumps(cue_sheet, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audition", type=Path, help="Write an optional OGG review reel")
    args = parser.parse_args()
    for entry in build():
        print(json.dumps(entry))
    if args.audition:
        audition(args.audition)
