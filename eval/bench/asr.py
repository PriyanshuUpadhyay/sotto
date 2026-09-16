# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = [
#   "crisperwhisper[transformers]>=2.0.0",
#   "huggingface-hub>=0.34.0",
#   "mistral-common[audio]>=1.9.0",
#   "mlx-audio[stt]>=0.5.1",
#   "mlx-whisper>=0.4.3",
#   "numpy>=2.0.0",
#   "sherpa-onnx>=1.12.20",
#   "soundfile>=0.13.1",
#   "torch>=2.4.0",
#   "transformers>=5.16.0",
# ]
# ///
"""Replay Sotto recordings through local speech-recognition models."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "eval/data/local/recordings.jsonl"
OUTPUT_DIR = ROOT / "eval/results/bench/asr"

# granite-turboctc-470m
# Source: https://huggingface.co/ibm-granite/granite-speech-5.0-470m-turboctc
# License: Apache-2.0. Downloaded cache size: 904M.
#
# sensevoice-small
# Source: https://huggingface.co/FunAudioLLM/SenseVoiceSmall
# License: FunASR Model License Agreement 1.0 (model-license on the card).
# Downloaded cache size: 228M.
#
# moonshine-streaming-small and moonshine-streaming-tiny
# Source: https://huggingface.co/moonshine-ai/moonshine-streaming-small
# License: MIT. Downloaded cache size: small 536M, tiny 170M.
#
# zipformer-en-streaming
# Source: https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26
# License: Apache-2.0. Downloaded cache size: 70M.
#
# kyutai-stt-1b
# Source: https://huggingface.co/kyutai/stt-1b-en_fr
# License: CC-BY-4.0. Downloaded cache size: 2.2G.
# Status: fails (mlx-audio does not support model type 'stt'; moshi-mlx has no reusable in-process API).
#
# voxtral-mini-4b-realtime
# Source: https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602
# License: Apache-2.0. Downloaded cache size: 2.9G.
#
# crisperwhisper2-small-intended
# Source: https://huggingface.co/nyralabs/CrisperWhisper2.0_small
# License: Nyra Health Non-Commercial Research License.
# Downloaded cache size: 467M.
#
# whisper-large-v3-turbo
# Source: https://huggingface.co/mlx-community/whisper-large-v3-turbo
# License: MIT (inherited from openai/whisper). Downloaded cache size: 1.5G.
#
# canary-qwen-2.5b
# Source: https://huggingface.co/nvidia/canary-qwen-2.5b
# License: NVIDIA Open Model License. Downloaded cache size: not downloaded.
# Status: fails (no NeMo-free macOS runtime was found).

MLX_MODELS = {
    "granite-turboctc-470m": "ibm-granite/granite-speech-5.0-470m-turboctc",
    "voxtral-mini-4b-realtime": "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
}
MOONSHINE_MODELS = {
    "moonshine-streaming-small": "moonshine-ai/moonshine-streaming-small",
    "moonshine-streaming-tiny": "moonshine-ai/moonshine-streaming-tiny",
}
ALL_MODELS = (
    "granite-turboctc-470m",
    "sensevoice-small",
    "moonshine-streaming-small",
    "moonshine-streaming-tiny",
    "zipformer-en-streaming",
    "kyutai-stt-1b",
    "voxtral-mini-4b-realtime",
    "crisperwhisper2-small-intended",
    "whisper-large-v3-turbo",
    "canary-qwen-2.5b",
)


def load_rows(ids: set[str] | None, limit: int | None) -> list[dict]:
    if not INPUT.exists():
        raise FileNotFoundError(f"missing input file: {INPUT}")
    rows = []
    with INPUT.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            try:
                row = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{INPUT}:{line_number}: {error}") from error
            if ids is None or row["id"] in ids:
                rows.append(row)
                if limit is not None and len(rows) >= limit:
                    break
    return rows


def completed_ids(path: Path) -> set[str]:
    if not path.exists():
        return set()
    done = set()
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            try:
                done.add(json.loads(line)["id"])
            except (json.JSONDecodeError, KeyError) as error:
                raise ValueError(f"{path}:{line_number}: invalid result row") from error
    return done


def mlx_audio_loader(repo: str) -> Callable[[str], str]:
    from mlx_audio.stt import load

    model = load(repo)

    def transcribe(audio: str) -> str:
        result = model.generate(audio, verbose=False)
        if hasattr(result, "text"):
            return result.text.strip()
        parts = [chunk.text if hasattr(chunk, "text") else str(chunk) for chunk in result]
        return "".join(parts).strip()

    return transcribe


def download(repo: str, filename: str) -> str:
    from huggingface_hub import hf_hub_download

    return hf_hub_download(repo_id=repo, filename=filename)


def sherpa_offline_loader() -> Callable[[str], str]:
    import sherpa_onnx
    import soundfile as sf

    repo = "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
    model = download(repo, "model.int8.onnx")
    tokens = download(repo, "tokens.txt")
    recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
        model=model,
        tokens=tokens,
        num_threads=max(1, min(4, os.cpu_count() or 1)),
        use_itn=True,
    )

    def transcribe(audio: str) -> str:
        samples, sample_rate = sf.read(audio, dtype="float32", always_2d=False)
        if samples.ndim != 1:
            raise ValueError("SenseVoice requires mono audio")
        stream = recognizer.create_stream()
        stream.accept_waveform(sample_rate, samples)
        recognizer.decode_stream(stream)
        return strip_sensevoice_tags(stream.result.text)

    return transcribe


def strip_sensevoice_tags(text: str) -> str:
    return re.sub(r"<\|[^|>]+\|>", "", text).strip()


def moonshine_loader(repo: str) -> Callable[[str], str]:
    import soundfile as sf
    import torch
    from transformers import AutoModelForSpeechSeq2Seq, AutoProcessor

    processor = AutoProcessor.from_pretrained(repo)
    dtype = torch.float16 if torch.backends.mps.is_available() else torch.float32
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    model = AutoModelForSpeechSeq2Seq.from_pretrained(repo, torch_dtype=dtype).to(device)
    model.eval()
    sampling_rate = processor.feature_extractor.sampling_rate

    def transcribe(audio: str) -> str:
        samples, source_rate = sf.read(audio, dtype="float32", always_2d=False)
        if samples.ndim != 1 or source_rate != sampling_rate:
            raise ValueError(f"Moonshine requires mono {sampling_rate} Hz audio")
        inputs = processor(
            samples,
            sampling_rate=source_rate,
            return_tensors="pt",
        ).to(device, dtype)
        token_limit = max(8, int(len(samples) * 6.5 / sampling_rate))
        with torch.inference_mode():
            generated = model.generate(**inputs, max_length=token_limit)
        return processor.decode(generated[0], skip_special_tokens=True).strip()

    return transcribe


def zipformer_loader() -> Callable[[str], str]:
    import sherpa_onnx
    import soundfile as sf

    repo = "csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26"
    names = {
        "encoder": "encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
        "decoder": "decoder-epoch-99-avg-1-chunk-16-left-128.onnx",
        "joiner": "joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
        "tokens": "tokens.txt",
    }
    files = {key: download(repo, name) for key, name in names.items()}
    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=files["tokens"],
        encoder=files["encoder"],
        decoder=files["decoder"],
        joiner=files["joiner"],
        num_threads=max(1, min(4, os.cpu_count() or 1)),
        sample_rate=16000,
        feature_dim=80,
        decoding_method="greedy_search",
        enable_endpoint_detection=False,
    )

    def transcribe(audio: str) -> str:
        samples, sample_rate = sf.read(audio, dtype="float32", always_2d=False)
        if samples.ndim != 1:
            raise ValueError("Zipformer requires mono audio")
        stream = recognizer.create_stream()
        chunk_size = int(sample_rate * 0.1)
        for offset in range(0, len(samples), chunk_size):
            stream.accept_waveform(sample_rate, samples[offset : offset + chunk_size])
            while recognizer.is_ready(stream):
                recognizer.decode_stream(stream)
        stream.input_finished()
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)
        return recognizer.get_result(stream).strip()

    return transcribe


def crisperwhisper_loader() -> Callable[[str], str]:
    from crisperwhisper import CrisperWhisperModel

    model = CrisperWhisperModel(
        "small", backend="transformers", compute_type="float16", device="auto"
    )

    def transcribe(audio: str) -> str:
        return model.transcribe(
            audio, language="en", mode="intended", hallucination_mitigation=False
        ).text.strip()

    return transcribe


def whisper_loader() -> Callable[[str], str]:
    import mlx.core as mx
    import mlx_whisper
    from mlx_whisper.transcribe import ModelHolder

    repo = "mlx-community/whisper-large-v3-turbo"
    ModelHolder.get_model(repo, mx.float16)

    def transcribe(audio: str) -> str:
        result = mlx_whisper.transcribe(
            audio,
            path_or_hf_repo=repo,
            language="en",
            temperature=0.0,
            verbose=None,
        )
        return result["text"].strip()

    return transcribe


def load_adapter(slug: str) -> Callable[[str], str]:
    if slug in MLX_MODELS:
        return mlx_audio_loader(MLX_MODELS[slug])
    if slug == "sensevoice-small":
        return sherpa_offline_loader()
    if slug in MOONSHINE_MODELS:
        return moonshine_loader(MOONSHINE_MODELS[slug])
    if slug == "zipformer-en-streaming":
        return zipformer_loader()
    if slug == "crisperwhisper2-small-intended":
        return crisperwhisper_loader()
    if slug == "whisper-large-v3-turbo":
        return whisper_loader()
    if slug == "kyutai-stt-1b":
        raise RuntimeError(
            "moshi-mlx has a file CLI but no reusable file-transcription API; "
            "this bench must load each model only once"
        )
    if slug == "canary-qwen-2.5b":
        raise RuntimeError("no NeMo-free macOS runtime was found")
    raise ValueError(f"unknown model: {slug}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=ALL_MODELS)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--ids", help="comma-separated recording ids")
    parser.add_argument("--list", action="store_true", dest="list_models")
    args = parser.parse_args()
    if args.list_models:
        return args
    if not args.model:
        parser.error("--model is required unless --list is used")
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be at least 1")
    return args


def main() -> int:
    args = parse_args()
    if args.list_models:
        print("\n".join(ALL_MODELS))
        return 0

    selected_ids = set(args.ids.split(",")) if args.ids else None
    rows = load_rows(selected_ids, args.limit)
    output = OUTPUT_DIR / f"{args.model}.jsonl"
    done = completed_ids(output)
    pending = [row for row in rows if row["id"] not in done]
    if not pending:
        print(f"nothing to do; {len(rows)} selected id(s) already exist in {output}")
        return 0

    transcribe = load_adapter(args.model)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("a", encoding="utf-8") as handle:
        for index, row in enumerate(pending):
            started = time.perf_counter()
            try:
                text = transcribe(row["audio"])
                error = None
            except Exception as caught:
                text = ""
                error = f"{type(caught).__name__}: {caught}"
            seconds = time.perf_counter() - started
            result = {
                "id": row["id"],
                "text": text,
                "seconds": seconds,
                "warm": index != 0,
                "error": error,
            }
            handle.write(json.dumps(result, ensure_ascii=False) + "\n")
            handle.flush()
            print(json.dumps(result, ensure_ascii=False))
            if (index + 1) % 25 == 0:
                print(f"progress {index + 1}/{len(pending)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
