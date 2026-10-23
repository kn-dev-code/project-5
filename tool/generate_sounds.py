"""Generates the app's sound effects into assets/sounds/.

Every sound is synthesized here from tones and noise, so there are no
third-party recordings or licenses involved. Tweak a function and rerun:

    python tool/generate_sounds.py
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"

C5, E5, G5, C6, E6, G6 = 523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0
G4, B4, D5, D6 = 392.0, 493.88, 587.33, 1174.7


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(*tracks):
    """Adds tracks together. Each is (start_seconds, samples)."""
    length = max(int(start * RATE) + len(s) for start, s in tracks)
    out = [0.0] * length
    for start, samples in tracks:
        offset = int(start * RATE)
        for i, v in enumerate(samples):
            out[offset + i] += v
    return out


def tone(freq, seconds, partials=((1, 1.0),), attack=0.004, decay=None,
         vibrato=0.0, slide_to=None):
    """A note made of harmonic or bell-like partials.

    partials: (frequency multiple, amplitude) pairs.
    decay: time constant of the exponential fade, or None to hold then fade.
    slide_to: glide the pitch to this frequency over the note.
    """
    n = int(seconds * RATE)
    out = []
    phase = [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        f = freq if slide_to is None else freq * (slide_to / freq) ** (t / seconds)
        if vibrato:
            f *= 1 + vibrato * math.sin(2 * math.pi * 5.5 * t)
        v = 0.0
        for k, (mult, amp) in enumerate(partials):
            phase[k] += 2 * math.pi * f * mult / RATE
            v += amp * math.sin(phase[k])
        env = min(1.0, t / attack) if attack else 1.0
        if decay:
            env *= math.exp(-t / decay)
        else:
            env *= min(1.0, (seconds - t) / 0.03)
        out.append(v * env)
    return out


def noise(seconds, decay, smooth=0.0, rise=False, seed=1):
    """Filtered noise. smooth (0..1) darkens it; rise fades it in instead."""
    rng = random.Random(seed)
    n = int(seconds * RATE)
    out, last = [], 0.0
    for i in range(n):
        t = i / RATE
        last = smooth * last + (1 - smooth) * rng.uniform(-1, 1)
        env = (t / seconds) ** 2 if rise else math.exp(-t / decay)
        out.append(last * env)
    return out


BELL = ((1, 1.0), (2.76, 0.35), (5.4, 0.12))
BRASS = tuple((k, 1 / k) for k in range(1, 8))
SQUAREISH = ((1, 1.0), (3, 0.33), (5, 0.2))
PLUCK = ((1, 1.0), (2, 0.4), (3, 0.15))


def tap():
    return mix((0, noise(0.012, 0.002, smooth=0.3)),
               (0, tone(1900, 0.05, ((1, 0.6), (2, 0.15)), attack=0.001, decay=0.009)))


def select():
    return mix((0, tone(1200, 0.05, PLUCK, decay=0.02)),
               (0.035, tone(1600, 0.07, PLUCK, decay=0.025)))


def bet():
    chips = [(i * 0.045, noise(0.03, 0.006, smooth=0.5, seed=i + 3)) for i in range(3)]
    return mix(*chips,
               (0.12, tone(G5, 0.18, BELL, decay=0.06)),
               (0.2, tone(D6, 0.35, BELL, decay=0.1)))


def coins():
    pings = [(i * 0.06, tone(f, 0.4, BELL, decay=0.09))
             for i, f in enumerate([G6, 2093.0, 2637.0, 3136.0])]
    return mix(*pings, (0, noise(0.45, 0.12, smooth=0.1, seed=9)))


def error():
    return mix((0, tone(330, 0.13, SQUAREISH, attack=0.005)),
               (0.14, tone(247, 0.2, SQUAREISH, attack=0.005)))


def notify():
    return mix((0, tone(C6, 0.7, BELL, decay=0.2)),
               (0.12, tone(G6, 0.6, BELL, decay=0.18)))


def fanfare():
    notes = [(0.0, C5, 0.12), (0.12, E5, 0.12), (0.24, G5, 0.12), (0.36, C6, 0.55)]
    return mix(*[(start, tone(f, length, BRASS, attack=0.015,
                              vibrato=0.006 if length > 0.3 else 0))
                 for start, f, length in notes])


def lose():
    return mix((0, tone(700, 0.6, ((1, 1.0), (3, 0.11)), attack=0.01,
                        vibrato=0.02, slide_to=240)))


def purchase():
    sparkle = [(i * 0.04, tone(f, 0.25, BELL, decay=0.06))
               for i, f in enumerate([C6, E6, G6, 2093.0, 2637.0])]
    return mix(*sparkle)


def startup():
    whoosh = noise(0.45, 0.2, smooth=0.85, rise=True, seed=7)
    chord = [(0.4 + i * 0.09, tone(f, 1.1 - i * 0.09, PLUCK + ((4, 0.05),), decay=0.35))
             for i, f in enumerate([G4, B4, D5, G5])]
    return mix((0, whoosh), *chord, (0.76, tone(D6, 0.8, BELL, decay=0.25)))


def write(name, samples, peak=0.7):
    # Short fades at both ends so playback never clicks.
    fade = int(0.003 * RATE)
    for i in range(min(fade, len(samples))):
        samples[i] *= i / fade
        samples[-1 - i] *= i / fade
    top = max(abs(v) for v in samples) or 1.0
    data = b"".join(struct.pack("<h", int(v / top * peak * 32767)) for v in samples)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    # Quieter peaks for sounds heard constantly, louder for big moments.
    sounds = {
        "tap": (tap, 0.35), "select": (select, 0.4), "bet": (bet, 0.6),
        "coins": (coins, 0.6), "error": (error, 0.5), "notify": (notify, 0.6),
        "fanfare": (fanfare, 0.7), "lose": (lose, 0.55),
        "purchase": (purchase, 0.6), "startup": (startup, 0.7),
    }
    for name, (make, peak) in sounds.items():
        write(name, make() + silence(0.02), peak)
        print(f"assets/sounds/{name}.wav")
