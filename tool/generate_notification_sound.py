"""Generates the app's notification chime as a WAV in res/raw.

Run with plain Python 3 — no dependencies:

    python tool/generate_notification_sound.py

Writes every preset to build/notification_sounds/ so they can be compared, and
copies [SELECTED] to res/raw/proteinix_chime.wav, which is the one the app ships.
Switching the app's sound means changing [SELECTED] and re-running.

Kept as a generator rather than checked-in binaries nobody can edit — the
constants below *are* the sounds, and retuning one is a one-line change.
"""

import math
import struct
import wave
from dataclasses import dataclass
from pathlib import Path

SAMPLE_RATE = 44_100
BIT_DEPTH_MAX = 32_767

# ── Timbres ────────────────────────────────────────────────────────────────
# (frequency ratio, amplitude) pairs stacked on the fundamental. The ratios are
# what make an instrument recognisable, far more than the note itself.

# Struck metal. The slightly sharp ratios are deliberate — real bells are
# inharmonic, and exact multiples are what make a synth sound like a synth.
BELL = ((1.00, 1.00), (2.02, 0.32), (3.01, 0.14), (4.03, 0.06))

# The same metal, hit gently. Fewer and quieter partials read as softer without
# changing pitch, which is a better way to sound calm than simply turning down.
SOFT_BELL = ((1.00, 1.00), (2.01, 0.16), (3.02, 0.05))

# Marimba/woodblock. Strong third partial and nothing above it, so it reads as
# soft and hollow rather than bright.
WOOD = ((1.00, 1.00), (3.00, 0.22), (6.00, 0.05))

# Glass/celesta. Exact harmonics and a strong octave give a pure shimmer.
GLASS = ((1.00, 1.00), (2.00, 0.50), (4.00, 0.18), (6.00, 0.05))


@dataclass(frozen=True)
class Strike:
    """One note: what pitch, when it lands, and how hard."""

    hz: float
    at_s: float
    gain: float = 1.0


@dataclass(frozen=True)
class Preset:
    strikes: tuple[Strike, ...]
    partials: tuple[tuple[float, float], ...]
    decay_s: float  # time to near-silence for a single strike
    total_s: float
    peak: float = 0.62  # headroom so overlapping notes never clip
    attack_s: float = 0.004  # longer = gentler onset
    description: str = ""


# ── Calm, with a surprise ──────────────────────────────────────────────────
# The surprise has to come from shape rather than brightness: anything bright
# enough to startle stops being calm. All three keep the pitch low, the attack
# soft and the partials few, and put the interest somewhere unexpected instead.

PRESETS = {
    # Rising major sixth. The sixth is the surprise — almost every notification
    # tone moves by a third, fourth, fifth or octave, so a sixth sounds fresh
    # while staying consonant. Wood keeps it hollow and unhurried.
    "hush": Preset(
        strikes=(Strike(293.66, 0.00), Strike(493.88, 0.16, 0.92)),  # D4, B4
        partials=WOOD,
        decay_s=0.46,
        total_s=0.80,
        peak=0.52,
        attack_s=0.008,
        description="Rising major sixth on wood. Low, unhurried, warm.",
    ),
    # A low strike, then silence long enough that you think it has finished —
    # and a quiet answer two octaves up. The surprise is the timing, not the
    # note. This is the one that sounds like *something*, not like an alert.
    "lantern": Preset(
        strikes=(Strike(329.63, 0.00), Strike(1318.51, 0.25, 0.42)),  # E4, E6
        partials=SOFT_BELL,
        decay_s=0.58,
        total_s=0.95,
        peak=0.50,
        attack_s=0.010,
        description="Low bell, a pause, then a soft answer two octaves up.",
    ),
    # Root, fifth, ninth. The ninth is the surprise: it is the interval that
    # makes a chord sound open and modern rather than resolved, and it lifts
    # without the brightness a major third would add.
    "drift": Preset(
        strikes=(
            Strike(392.00, 0.00),  # G4
            Strike(587.33, 0.095, 0.88),  # D5
            Strike(880.00, 0.190, 0.70),  # A5 — the ninth
        ),
        partials=SOFT_BELL,
        # Spacing sets the pace, but the decay has to come down with it or the
        # notes stay ringing over each other and the arpeggio smears into one
        # chord — which reads as slower even when the strikes are faster.
        # Below about 80ms apart they stop articulating as separate notes.
        decay_s=0.55,
        total_s=0.82,
        peak=0.52,
        attack_s=0.008,
        description="Root, fifth and ninth. Open and gently lifting.",
    ),
    # ── Earlier, brighter candidates, kept for comparison ──────────────────
    "bloom": Preset(
        strikes=(Strike(880.00, 0.00), Strike(1108.73, 0.11), Strike(1318.51, 0.22)),
        partials=BELL,
        decay_s=0.55,
        total_s=0.85,
        description="Rising A-major triad on a bell. Warm, optimistic.",
    ),
    "pebble": Preset(
        strikes=(Strike(659.26, 0.00), Strike(493.88, 0.13)),
        partials=WOOD,
        decay_s=0.28,
        total_s=0.50,
        description="Two-note fall on soft wood. Calm, short, understated.",
    ),
    "beacon": Preset(
        strikes=(Strike(1046.50, 0.00), Strike(1046.50, 0.085)),
        partials=GLASS,
        decay_s=0.38,
        total_s=0.60,
        description="Single glassy note struck twice. Crisp, minimal.",
    ),
}

SELECTED = "drift"

ROOT = Path(__file__).resolve().parents[1]
SHIPPED = ROOT / "android/app/src/main/res/raw/proteinix_chime.wav"
PREVIEWS = ROOT / "build/notification_sounds"


def render(p: Preset) -> list[float]:
    total = int(p.total_s * SAMPLE_RATE)
    buffer = [0.0] * total

    for strike in p.strikes:
        start = int(strike.at_s * SAMPLE_RATE)
        for n in range(start, total):
            t = (n - start) / SAMPLE_RATE
            # Exponential decay is what makes a note read as *struck* rather
            # than held; a linear fade sounds like a pad.
            envelope = math.exp(-t / (p.decay_s / 4)) * strike.gain
            if envelope < 1e-4:
                break
            buffer[n] += envelope * sum(
                amp * math.sin(2 * math.pi * strike.hz * ratio * t)
                for ratio, amp in p.partials
            )

    # Fading the onset in removes the click an instant start produces; a longer
    # fade is most of what makes a sound feel gentle rather than sudden.
    attack = int(p.attack_s * SAMPLE_RATE)
    for n in range(min(attack, total)):
        buffer[n] *= n / attack

    # And fade the end out. A decaying tail cut off at total_s is still audible
    # — a fraction of a percent of full scale is enough to click — so the last
    # 25ms are ramped to silence rather than truncated.
    release = min(int(0.025 * SAMPLE_RATE), total)
    for n in range(release):
        buffer[total - 1 - n] *= n / release

    loudest = max((abs(s) for s in buffer), default=0.0) or 1.0
    return [s / loudest * p.peak for s in buffer]


def write(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * BIT_DEPTH_MAX))
                for s in samples
            )
        )


def main() -> None:
    if SELECTED not in PRESETS:
        raise SystemExit(f"SELECTED must be one of {sorted(PRESETS)}")

    for name, preset in PRESETS.items():
        samples = render(preset)
        write(PREVIEWS / f"{name}.wav", samples)
        mark = "  <- shipped" if name == SELECTED else ""
        print(f"{name:8} {preset.total_s:.2f}s  {preset.description}{mark}")
        if name == SELECTED:
            write(SHIPPED, samples)

    print(f"\npreviews: {PREVIEWS}")
    print(f"shipped : {SHIPPED}")


if __name__ == "__main__":
    main()
