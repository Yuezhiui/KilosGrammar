#!/usr/bin/env python3
"""Verify authored tutorial WAVs are distinct, non-silent PCM16 mono voice clips."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf


ROOT = Path(__file__).resolve().parents[2]
WAV_DIR = ROOT / "assets" / "audio" / "tutorial_spotlight"
MANIFEST = Path(__file__).with_name("voice_lines.json")
QA_REPORT = Path(__file__).with_name("audio_validation.json")


def main() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    keys = [item["id"] for item in manifest]
    expected = {f"{key}.wav" for key in keys}
    actual = {item.name for item in WAV_DIR.glob("*.wav")}
    if actual != expected:
        raise AssertionError(f"Missing WAVs: {sorted(expected-actual)}; extras: {sorted(actual-expected)}")
    seen = {}
    total_bytes = 0
    metrics = {}
    for key in keys:
        path = WAV_DIR / f"{key}.wav"
        info = sf.info(str(path))
        audio, rate = sf.read(str(path), dtype="float32", always_2d=False)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        duration = len(audio) / rate
        rms = float(np.sqrt(np.mean(audio ** 2)))
        peak = float(np.max(np.abs(audio)))
        active_ratio = float(np.mean(np.abs(audio) > 0.012))
        clipped_ratio = float(np.mean(np.abs(audio) >= 0.99))
        total_bytes += path.stat().st_size
        conditions = (
            info.channels == 1 and info.subtype == "PCM_16" and rate == 24000
            and 5 <= duration <= 15.0 and 0.008 < rms < 0.85
            and 0.04 < peak < 0.95 and active_ratio > 0.12 and clipped_ratio == 0
            and digest not in seen
        )
        if not conditions:
            raise AssertionError(
                f"Bad speech clip {key}: channels={info.channels}, subtype={info.subtype}, "
                f"rate={rate}, duration={duration:.2f}, rms={rms:.4f}, "
                f"peak={peak:.4f}, active_ratio={active_ratio:.4f}, "
                f"clipped_ratio={clipped_ratio:.4f}, duplicate_of={seen.get(digest)}"
            )
        seen[digest] = key
        metrics[key] = {
            "duration_s": round(duration, 2),
            "sha256": digest,
            "rms": round(rms, 4),
            "peak": round(peak, 4),
            "active_ratio": round(active_ratio, 4),
            "byte_size": path.stat().st_size,
        }
        print(f"PASS {key}.wav: {duration:.2f}s, RMS {rms:.3f}, peak {peak:.3f}")
    aggregate = hashlib.sha256(''.join(f'{key}:{metrics[key]["sha256"]}\n' for key in keys).encode('ascii')).hexdigest()
    QA_REPORT.write_text(json.dumps({"clips": len(keys), "format": "PCM16 mono / 24kHz",
                                     "total_bytes": total_bytes, "sha256_manifest": aggregate,
                                     "metrics": metrics}, indent=2), encoding="utf-8")
    print(f"PASS {len(keys)}/{len(keys)}: all non-silent, unique, decoded PCM16 mono WAVs")
    print(f"SHA256 manifest: {aggregate} | size: {total_bytes} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
