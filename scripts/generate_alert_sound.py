#!/usr/bin/env python3
"""Generate InkPulse custom notification sound — heartbeat pulse."""
import struct
import math
import subprocess
import tempfile
import os

SAMPLE_RATE = 44100
DURATION = 1.0
FREQ = 80  # Low thump frequency

samples = []
n_samples = int(SAMPLE_RATE * DURATION)

for i in range(n_samples):
    t = i / SAMPLE_RATE
    # Two heartbeat pulses: thump at 0.1s and 0.35s
    pulse1 = math.exp(-((t - 0.10) ** 2) / 0.002)
    pulse2 = math.exp(-((t - 0.35) ** 2) / 0.002)
    envelope = (pulse1 + pulse2 * 0.7)
    # Low sine for thump body
    wave = math.sin(2 * math.pi * FREQ * t)
    # Higher harmonic for attack
    wave += 0.3 * math.sin(2 * math.pi * FREQ * 3 * t)
    sample = envelope * wave * 0.8
    sample = max(-1.0, min(1.0, sample))
    samples.append(int(sample * 32767))

# Write raw WAV first
wav_path = tempfile.mktemp(suffix=".wav")
with open(wav_path, "wb") as f:
    n = len(samples)
    data_size = n * 2
    f.write(b"RIFF")
    f.write(struct.pack("<I", 36 + data_size))
    f.write(b"WAVE")
    f.write(b"fmt ")
    f.write(struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16))
    f.write(b"data")
    f.write(struct.pack("<I", data_size))
    for s in samples:
        f.write(struct.pack("<h", s))

# Convert to AIFF via afconvert
script_dir = os.path.dirname(os.path.abspath(__file__))
aiff_path = os.path.join(script_dir, "..", "Resources", "inkpulse_alert.aiff")
subprocess.run(["afconvert", "-f", "AIFF", "-d", "BEI16", wav_path, aiff_path], check=True)
os.unlink(wav_path)
print(f"Generated: {aiff_path}")
