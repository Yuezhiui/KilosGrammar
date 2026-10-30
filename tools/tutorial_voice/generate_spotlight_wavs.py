#!/usr/bin/env python3
"""Generate the 19 guided KILOS GRAMMAR narration WAVs with local OmniVoice.

Uses the user's existing, local OmniVoice voice sample. The source sample and
the owner's /omni-voice/input.txt stay untouched; only named output WAVs and
a non-sensitive QA report are written into the KILOS GRAMMAR project.

Example (Windows PowerShell):
  & 'C:\\Espressif\\tools\\python\\python.exe' tools/tutorial_voice/generate_spotlight_wavs.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "tools" / "tutorial_voice" / "voice_lines.json"
DEFAULT_OUT = ROOT / "assets" / "audio" / "tutorial_spotlight"
DEFAULT_REF = Path(r"C:\Users\Yue\Documents\OMNI VOICE\input\Clone.wav")
REPORT_PATH = ROOT / "tools" / "tutorial_voice" / "generation_report.json"
GAMES = ("catch_word", "balloon_popping", "human_plane")
STEPS = ("prompt", "movement", "seconds", "lives", "score", "pause")
EXPECTED_KEYS = tuple(f"{game}_{step}" for game in GAMES for step in STEPS) + ("human_plane_ring",)


def load_lines(manifest: Path) -> dict[str, dict]:
    """Accept a key/string mapping, keyed object, or {lines:[{key,text}]} JSON."""
    raw = json.loads(manifest.read_text(encoding="utf-8-sig"))
    if isinstance(raw, dict):
        for name in ("lines", "scripts", "clips", "narrations", "voice_lines"):
            if name in raw and isinstance(raw[name], (list, dict)):
                raw = raw[name]
                break

    result: dict[str, dict] = {}
    if isinstance(raw, list):
        entries = []
        for entry in raw:
            if not isinstance(entry, dict):
                raise ValueError("Every manifest list item needs key and text")
            key = entry.get("key") or entry.get("id") or entry.get("filename")
            entries.append((key, entry))
    elif isinstance(raw, dict):
        entries = list(raw.items())
    else:
        raise ValueError("Manifest must be a JSON list or object")

    for key, record in entries:
        if not isinstance(key, str):
            raise ValueError("Manifest entry lacks a string key/id")
        key = Path(key).stem
        if isinstance(record, str):
            record = {"text": record}
        if not isinstance(record, dict):
            raise ValueError(f"Invalid narration object for {key}")
        text = record.get("text") or record.get("spoken_text") or record.get("narration")
        if not isinstance(text, str) or not text.strip():
            raise ValueError(f"Missing narration text for {key}")
        if key in result:
            raise ValueError(f"Duplicate narration key: {key}")
        result[key] = {"text": text.strip(), "language": record.get("language")}

    missing = set(EXPECTED_KEYS) - set(result)
    extras = set(result) - set(EXPECTED_KEYS)
    if missing or extras:
        raise ValueError(f"Expected exactly {len(EXPECTED_KEYS)} keys. Missing: {sorted(missing)}, extra: {sorted(extras)}")
    return result


def normalize_mono_pcm16(audio: np.ndarray, sr: int) -> tuple[np.ndarray, float, float]:
    """Keep speech intact, smooth edges, avoid clipping, constrain gain to +6 dB."""
    signal = np.asarray(audio, dtype=np.float32)
    if signal.ndim == 2:
        signal = signal.mean(axis=1 if signal.shape[1] <= 2 else 0)
    signal = signal.reshape(-1)
    if signal.size < sr // 5 or not np.all(np.isfinite(signal)):
        raise ValueError("Synthesizer returned empty, short, or invalid waveform")
    original_peak = float(np.max(np.abs(signal)))
    if original_peak < 0.001:
        raise ValueError(f"Generated audio is essentially silent: peak={original_peak:.5f}")
    gain = min(0.88 / original_peak, 2.0)
    signal *= gain
    fade_samples = min(int(sr * 0.035), len(signal) // 8)
    if fade_samples > 1:
        signal[:fade_samples] *= np.linspace(0, 1, fade_samples, dtype=np.float32)
        signal[-fade_samples:] *= np.linspace(1, 0, fade_samples, dtype=np.float32)
    return signal, original_peak, float(np.max(np.abs(signal)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--ref", type=Path, default=DEFAULT_REF)
    parser.add_argument("--model", default="k2-fsa/OmniVoice")
    parser.add_argument("--steps", type=int, default=24, help="Diffusion steps (16 faster, 32 higher quality)")
    parser.add_argument("--speed", type=float, default=1.03, help="Narration rate, 1.0 natural")
    parser.add_argument("--language", default="auto", help="Forced synthesis language (en for English-only), or auto")
    parser.add_argument("--only", nargs="*", help="Optional clip key(s) for a spot check")
    parser.add_argument("--dry-run", action="store_true", help="Verify manifest and paths without model load")
    parser.add_argument("--overwrite", action="store_true", help="Regenerate existing WAVs")
    args = parser.parse_args()

    lines = load_lines(args.manifest)
    keys = list(EXPECTED_KEYS)
    if args.only:
        unknown = set(args.only) - set(keys)
        if unknown:
            parser.error(f"Unknown clip keys: {sorted(unknown)}")
        keys = [key for key in keys if key in args.only]
    if not args.ref.is_file():
        raise FileNotFoundError(f"Cloned voice sample missing: {args.ref}")
    ref_info = sf.info(str(args.ref))
    print(f"Manifest: {args.manifest} ({len(lines)} keys)", flush=True)
    print(f"Voice source: {args.ref.name}, {ref_info.duration:.2f}s (kept private)", flush=True)
    print(f"Target: {args.out}; selected clips: {len(keys)}", flush=True)
    if args.dry_run:
        for key in keys:
            print(f"  {key}: {lines[key]['text']}")
        return 0

    # Reuse cached Hugging Face weights; avoid network requests for a local task.
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
    os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
    import torch
    from omnivoice import OmniVoice

    device = "cuda:0" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if device.startswith("cuda") else torch.float32
    print(f"Loading OmniVoice once on {device}, precision={dtype}...", flush=True)
    started = time.perf_counter()
    model = OmniVoice.from_pretrained(args.model, device_map=device, dtype=dtype, asr_device="cpu")
    print(f"Model loaded: {time.perf_counter() - started:.1f}s, {model.sampling_rate}Hz", flush=True)

    print("Encoding cloned voice once (reference ASR on CPU if no transcript)...", flush=True)
    prompt = model.create_voice_clone_prompt(ref_audio=str(args.ref))
    print(f"Voice prompt ready, transcript length={len(prompt.ref_text)} chars", flush=True)

    args.out.mkdir(parents=True, exist_ok=True)
    report = {"model": args.model, "steps": args.steps, "speed": args.speed,
              "voice_mode": "existing_local_clone", "sample_rate": model.sampling_rate,
              "outputs": {}}
    for index, key in enumerate(keys, start=1):
        output = args.out / f"{key}.wav"
        if output.exists() and not args.overwrite:
            info = sf.info(str(output))
            if info.channels == 1 and info.subtype == "PCM_16" and info.duration > 0.2:
                print(f"[{index}/{len(keys)}] already present: {output.name}", flush=True)
                report["outputs"][key] = {"status": "existing", "duration_s": round(info.duration, 2)}
                continue
            raise ValueError(f"Existing WAV failed PCM16/mono validation: {output}")

        record = lines[key]
        # An explicit CLI language always overrides any stale per-line metadata.
        language = None if args.language.lower() == "auto" else args.language
        if language is None:
            language = record["language"]
        print(f"[{index}/{len(keys)}] Synthesizing {key}, language={language or 'auto'}, text={record['text']}", flush=True)
        elapsed = time.perf_counter()
        with torch.inference_mode():
            rendered = model.generate(text=record["text"], language=language,
                                      voice_clone_prompt=prompt, num_step=args.steps, speed=args.speed)
        wave, input_peak, peak = normalize_mono_pcm16(rendered[0], model.sampling_rate)
        sf.write(str(output), wave, model.sampling_rate, format="WAV", subtype="PCM_16")
        info = sf.info(str(output))
        if info.channels != 1 or info.subtype != "PCM_16" or info.samplerate != 24000 or not (5 <= info.duration <= 15):
            raise ValueError(f"Generated WAV did not meet PCM16/mono/duration criteria: {output}")
        digest = hashlib.sha256(output.read_bytes()).hexdigest()
        report["outputs"][key] = {"duration_s": round(info.duration, 2),
                                  "peak_before": round(input_peak, 4),
                                  "peak_after": round(peak, 4),
                                  "sha256": digest,
                                  "generation_s": round(time.perf_counter() - elapsed, 1)}
        print(f"  WAV {info.duration:.2f}s | peak={peak:.3f} | generated in {report['outputs'][key]['generation_s']}s", flush=True)
        REPORT_PATH.write_text(
            json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

    print(f"Done: {len(report['outputs'])} selected WAVs; report: {REPORT_PATH}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[ERROR] {type(exc).__name__}: {exc}", file=sys.stderr, flush=True)
        raise
