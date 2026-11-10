#!/usr/bin/env python3
"""Rebuild the original woodland audio palette using only Python's stdlib.

No recordings, downloads, or third-party samples. Cues use soft sine partials
and filtered noise; the beds use crossfaded periodic noise. All files are mono
16-bit PCM. Godot's game_audio.gd supplies loop points and conservative gains.
"""

import argparse
from array import array
import io
import math
from pathlib import Path
import random
import sys
import wave

CUE_RATE = 22050
BED_RATE = 16000
TAU = math.tau


def smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def envelope(t: float, duration: float, attack: float, release: float) -> float:
    return smoothstep(t / attack) * smoothstep((duration - t) / release)


def blank(duration: float, rate: int = CUE_RATE) -> list[float]:
    return [0.0] * round(duration * rate)


def tone(
    samples: list[float], start: float, duration: float, hz: float,
    gain: float = 1.0, *, rate: int = CUE_RATE, bend: float = 0.0,
    brightness: float = 0.12, attack: float = 0.006,
    release: float = 0.07, decay: float = 3.5,
) -> None:
    """Add a softly struck sine voice with two quiet harmonic partials."""
    offset = round(start * rate)
    length = min(round(duration * rate), len(samples) - offset)
    for i in range(length):
        t = i / rate
        phase = TAU * (hz * t + 0.5 * bend * t * t / duration)
        voice = (math.sin(phase) + brightness * math.sin(2.0 * phase)
                 + 0.3 * brightness * math.sin(3.0 * phase))
        shape = envelope(t, duration, attack, release)
        samples[offset + i] += gain * voice * shape * math.exp(-decay * t / duration)


def filtered_noise(frames: int, rate: int, cutoff: float, seed: int) -> list[float]:
    """Seeded two-pole low-pass noise, warmed up before the returned samples."""
    rng = random.Random(seed)
    alpha = 1.0 - math.exp(-TAU * cutoff / rate)
    first = second = 0.0
    result = []
    warmup = rate // 4
    for i in range(frames + warmup):
        first += alpha * (rng.uniform(-1.0, 1.0) - first)
        second += alpha * (first - second)
        if i >= warmup:
            result.append(second)
    return result


def noise_hit(
    samples: list[float], cutoff: float, seed: int, gain: float,
    *, attack: float = 0.008, release: float = 0.1, decay: float = 4.0,
) -> None:
    duration = len(samples) / CUE_RATE
    noise = filtered_noise(len(samples), CUE_RATE, cutoff, seed)
    for i, value in enumerate(noise):
        t = i / CUE_RATE
        samples[i] += gain * value * envelope(t, duration, attack, release) * math.exp(-decay * t / duration)


def loop_noise(duration: float, rate: int, cutoff: float, seed: int) -> list[float]:
    """Crossfade an extra second over the start, preserving seam continuity.

    The final frame is followed by its natural next noise sample at frame zero;
    the overlap then smoothly rejoins the original head. Both crossfade slopes
    reach zero. No independent random samples are joined at the loop boundary.
    """
    frames = round(duration * rate)
    overlap = rate
    noise = filtered_noise(frames + overlap, rate, cutoff, seed)
    result = noise[:frames]
    for i in range(overlap):
        blend = smoothstep(i / (overlap - 1))
        result[i] = noise[frames + i] * (1.0 - blend) + noise[i] * blend
    return result


def make_cues() -> dict[str, list[float]]:
    cues = {}

    # Tiny rounded UI chime, not a sharp electronic click.
    samples = blank(0.10)
    tone(samples, 0.0, 0.10, 659.255, brightness=0.06, release=0.035, decay=4.0)
    cues["select"] = samples

    # A low soil thump with a brief, softened grain layer.
    samples = blank(0.24)
    tone(samples, 0.0, 0.22, 155.0, 0.7, bend=-55.0, brightness=0.16, decay=4.5)
    noise_hit(samples, 850.0, 1701, 0.9, release=0.09, decay=5.5)
    cues["dig"] = samples

    # A hollow wooden knock rather than a metallic or aggressive chop.
    samples = blank(0.23)
    tone(samples, 0.0, 0.23, 196.0, 0.75, bend=-32.0, brightness=0.27, decay=5.5)
    tone(samples, 0.006, 0.11, 367.0, 0.18, brightness=0.05, release=0.04)
    noise_hit(samples, 1300.0, 1702, 0.35, release=0.08, decay=8.0)
    cues["axe"] = samples

    # Three rounded falling droplets over a restrained splash.
    samples = blank(0.48)
    noise_hit(samples, 1600.0, 1703, 0.45, attack=0.018, release=0.20, decay=2.4)
    for start, hz, length, gain in ((0.025, 910.0, 0.17, 0.34),
                                   (0.135, 710.0, 0.19, 0.29),
                                   (0.270, 1080.0, 0.20, 0.22)):
        tone(samples, start, length, hz, gain, bend=-hz * 0.35,
             brightness=0.02, attack=0.009, release=0.055, decay=4.0)
    cues["water"] = samples

    samples = blank(0.34)
    tone(samples, 0.0, 0.25, 293.665, 0.8, brightness=0.07)
    tone(samples, 0.095, 0.245, 440.0, 0.65, brightness=0.07)
    cues["turn"] = samples

    # A small breath of wind with no piercing whistle or broadband hiss.
    samples = blank(0.72)
    noise_hit(samples, 650.0, 1704, 1.0, attack=0.18, release=0.28, decay=0.4)
    tone(samples, 0.08, 0.64, 293.665, 0.035, brightness=0.0,
         attack=0.19, release=0.24, decay=0.4)
    cues["wind"] = samples

    # Original D-major rising phrase, exactly 1.1 seconds including its tail.
    samples = blank(1.10)
    for start, hz, length, gain in ((0.0, 293.665, 0.52, 0.65),
                                   (0.18, 369.994, 0.50, 0.62),
                                   (0.36, 440.0, 0.51, 0.60),
                                   (0.56, 587.330, 0.54, 0.67)):
        tone(samples, start, length, hz, gain, brightness=0.09,
             attack=0.012, release=0.16, decay=2.8)
    tone(samples, 0.0, 1.10, 146.832, 0.11, brightness=0.0,
         attack=0.025, release=0.25, decay=2.6)
    cues["win"] = samples

    # Reflective descending notes, not an alarm or a dissonant buzzer.
    samples = blank(0.76)
    for start, hz in ((0.0, 329.628), (0.20, 293.665), (0.40, 220.0)):
        tone(samples, start, 0.36, hz, 0.62, brightness=0.035,
             attack=0.018, release=0.14, decay=2.3)
    cues["lose"] = samples

    samples = blank(0.30)
    tone(samples, 0.0, 0.19, 440.0, 0.65, brightness=0.04, attack=0.012)
    tone(samples, 0.11, 0.19, 293.665, 0.70, brightness=0.04, attack=0.012)
    cues["undo"] = samples
    return cues


def make_forest() -> list[float]:
    duration = 16.0
    samples = loop_noise(duration, BED_RATE, 470.0, 2101)
    # Exact integer cycles per loop keep the slow swells and sine bed seamless.
    root = round(146.832 * duration) / duration
    fifth = round(220.0 * duration) / duration
    for i, noise in enumerate(samples):
        t = i / BED_RATE
        cycle = TAU * t / duration
        breath = 0.68 + 0.19 * math.sin(cycle) + 0.08 * math.sin(3.0 * cycle)
        pad = math.sin(TAU * root * t) + 0.55 * math.sin(TAU * fifth * t)
        swell = 0.12 + 0.88 * math.sin(cycle / 2.0) ** 2
        samples[i] = 0.13 * noise * breath + 0.007 * pad * swell
    # Sparse, warm two-note answers with several seconds of space between them.
    for start, hz, gain in ((1.7, 293.665, 0.042), (3.3, 440.0, 0.033),
                            (9.1, 329.628, 0.036), (10.9, 440.0, 0.030)):
        tone(samples, start, 2.0, hz, gain, rate=BED_RATE, brightness=0.035,
             attack=0.09, release=0.65, decay=3.8)
    return samples


def make_fire() -> list[float]:
    duration = 12.0
    samples = loop_noise(duration, BED_RATE, 620.0, 2102)
    # Soft smoulder only: no pops, crackle triggers, or sharp transients.
    for i in range(len(samples)):
        phase = TAU * i / len(samples)
        samples[i] *= 0.64 + 0.18 * math.sin(phase) + 0.10 * math.sin(4.0 * phase + 0.4)
    return samples


def write_if_changed(path: Path, data: bytes) -> None:
    # Do not invalidate a live Godot import for a byte-identical rebuild. Atomic
    # replacement also prevents the importer from observing a partial WAV.
    if path.exists() and path.read_bytes() == data:
        return
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def ensure_pcm_import(path: Path) -> None:
    # Godot 4.6 defaults to lossy QOA import. Pin PCM without replacing existing
    # [remap]/[deps] paths or resource UIDs generated by the actual project.
    sidecar = path.with_suffix(".wav.import")
    text = sidecar.read_text(encoding="utf-8") if sidecar.exists() else (
        '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n\n'
    )
    settings = {
        "force/8_bit": "false", "force/mono": "false", "force/max_rate": "false",
        "force/max_rate_hz": "44100", "edit/trim": "false", "edit/normalize": "false",
        "edit/loop_mode": "0", "edit/loop_begin": "0", "edit/loop_end": "-1",
        "compress/mode": "0",
    }
    if "[params]" not in text:
        text += "\n[params]\n"
    prefix, parameters = text.split("[params]", 1)
    lines = parameters.splitlines()
    for i, line in enumerate(lines):
        key = line.split("=", 1)[0]
        if key in settings:
            lines[i] = f"{key}={settings.pop(key)}"
    lines.extend(f"{key}={value}" for key, value in settings.items())
    write_if_changed(sidecar, (prefix + "[params]" + "\n".join(lines) + "\n").encode("utf-8"))


def write_wav(path: Path, samples: list[float], rate: int, peak: float, loop: bool = False) -> None:
    dc = sum(samples) / len(samples)
    samples = [sample - dc for sample in samples]
    if not loop:
        duration = len(samples) / rate
        for i in range(len(samples)):
            samples[i] *= envelope(i / rate, duration, 0.004, 0.018)
        samples[0] = samples[-1] = 0.0
    maximum = max(abs(sample) for sample in samples)
    if not math.isfinite(maximum) or maximum == 0.0:
        raise ValueError(f"Invalid waveform: {path.name}")
    pcm = array("h", (round(sample * peak * 32767.0 / maximum) for sample in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(pcm.tobytes())
    write_if_changed(path, buffer.getvalue())
    ensure_pcm_import(path)
    print(f"{path.name:16s} {len(samples) / rate:6.3f}s  {rate:5d} Hz  {path.stat().st_size:7d} bytes")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path,
                        default=Path(__file__).resolve().parents[1] / "assets" / "audio")
    output_dir = parser.parse_args().output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, samples in make_cues().items():
        peak = {"select": 0.46, "wind": 0.42, "lose": 0.44}.get(name, 0.50)
        write_wav(output_dir / f"{name}.wav", samples, CUE_RATE, peak)
    write_wav(output_dir / "forest_loop.wav", make_forest(), BED_RATE, 0.28, loop=True)
    write_wav(output_dir / "fire_loop.wav", make_fire(), BED_RATE, 0.28, loop=True)


if __name__ == "__main__":
    main()
