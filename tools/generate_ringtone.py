"""Reproducible, original SPARTAN 'Phoenix Rise' ringtone (no sampled audio).

Usage: python tools/generate_ringtone.py --output path/to/spartan_phoenix_call.wav
Python standard library only. 48 kHz mono PCM, one 4.8-second ringing cycle.
"""
import argparse
import math
import struct
import wave
from pathlib import Path

RATE = 48000
DURATION = 4.8


def render():
    samples = [0.0] * round(RATE * DURATION)

    def bell(start, frequency, gain, decay, length):
        # Gentle inharmonic upper partials suggest bronze without a harsh clang.
        partials = [(1.0, 1.0, 1.0), (2.005, 0.16, 0.52),
                    (2.99, 0.045, 0.34), (4.08, 0.012, 0.22)]
        for i in range(round(length * RATE)):
            t = i / RATE
            envelope = (1 - math.exp(-t / 0.012))
            envelope *= min(1.0, max(0.0, (length - t) / 0.12))
            value = sum(weight * math.sin(2 * math.pi * frequency * ratio * t)
                        * math.exp(-t / (decay * tail))
                        for ratio, weight, tail in partials)
            index = round(start * RATE) + i
            if index < len(samples):
                samples[index] += gain * envelope * value

    # A quiet low foundation; three rising pentatonic notes carry on phone speakers.
    bell(0.08, 146.8324, 0.12, 0.33, 1.1)
    for start, note, gain, decay, length in [
        (0.12, 440.0, 0.40, 0.38, 1.05),
        (0.47, 587.3295, 0.44, 0.41, 1.10),
        (0.88, 659.2551, 0.40, 0.60, 1.85),
    ]:
        bell(start, note, gain, decay, length)
        bell(start + 0.19, note, gain * 0.12, decay, length)
        bell(start + 0.38, note, gain * 0.04, decay, length)

    peak = max(abs(x) for x in samples)
    scale = 0.63 / peak
    samples = [x * scale for x in samples]
    assert samples[0] == 0 and samples[-1] == 0
    assert max(abs(x) for x in samples) < 1.0
    pcm = b''.join(struct.pack('<h', round(x * 32767)) for x in samples)
    rms = math.sqrt(sum(x*x for x in samples) / len(samples))
    return pcm, rms


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    pcm, rms = render()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.output), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)
    with wave.open(str(args.output), 'rb') as check:
        assert check.getnframes() == round(RATE * DURATION)
        assert check.getnchannels() == 1 and check.getsampwidth() == 2
    print(f'Created {args.output}: {DURATION}s, peak -4.01 dBFS, '
          f'RMS {20 * math.log10(rms):.2f} dBFS, no clipped samples.')


if __name__ == '__main__':
    main()
