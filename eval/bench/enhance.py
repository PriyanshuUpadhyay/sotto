#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = [
#   "huggingface-hub>=1,<2",
#   "mlx-lm>=0.31,<0.32",
#   "sentencepiece>=0.2,<0.3",
#   "transformers>=5,<6",
# ]
# ///

"""Run local transcript-cleanup models against Sotto benchmark inputs."""

import argparse
import importlib.util
import json
import os
import re
import sys
import time
from pathlib import Path

# The moved names stay importable from here: gector.py reads enhance.MODELS and others.
from enhance_loaders import (  # noqa: F401
    FILLER_RE,
    load_adapter,
    load_causal_lm,
    load_coedit,
    load_llama,
    load_mlx,
    load_punctuation,
    remove_fillers,
    sentence_case,
)
from enhance_models import (  # noqa: F401
    FLOWSCRIBE_PROMPT,
    MODELS,
    MUMBLE_PROMPT,
    OUTPUT_DIR,
    PROMPT_PATH,
    RECORDINGS_PATH,
    REWRITE_FIXED_LINE,
    REWRITE_PATH,
    ROOT,
    S1_MINI_PROMPT,
    SPEAKOFLOW_PROMPT,
    SYNTHETIC_PATHS,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=MODELS)
    parser.add_argument("--limit", type=int)
    parser.add_argument(
        "--sets",
        default="recordings,dev,eval,heldout",
        help="Comma-separated input sets: recordings, dev, eval, heldout, rewrite",
    )
    parser.add_argument(
        "--list", action="store_true", help="List supported model slugs"
    )
    parser.add_argument(
        "--selftest", action="store_true", help="Test local data and output cleanup"
    )
    args = parser.parse_args()
    if not args.list and not args.selftest and not args.model:
        parser.error("--model is required unless --list or --selftest is used")
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be at least 1")
    return args


def read_jsonl(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def load_inputs(names: list[str]) -> list[dict]:
    unknown = set(names) - {"recordings", "rewrite", *SYNTHETIC_PATHS}
    if unknown:
        raise ValueError(f"unknown set(s): {', '.join(sorted(unknown))}")

    rows = []
    for name in names:
        if name == "recordings":
            path = RECORDINGS_PATH
        elif name == "rewrite":
            path = REWRITE_PATH
        else:
            path = SYNTHETIC_PATHS[name]
        if not path.exists():
            raise FileNotFoundError(f"{name} input does not exist: {path}")
        for row in read_jsonl(path):
            item = {"id": str(row["id"]), "set": name, "raw": str(row["raw"])}
            if "instruction" in row:
                item["instruction"] = str(row["instruction"])
            rows.append(item)
    return rows


def strip_chat_wrapping(text: str) -> str:
    text = text.strip()
    text = re.sub(r"^<think>.*?</think>\s*", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(
        r"^<\|channel\>thought.*?<channel\|\>\s*",
        "",
        text,
        flags=re.DOTALL | re.IGNORECASE,
    )
    fence = re.fullmatch(
        r"```(?:text|markdown)?\s*\n?(.*?)\n?```", text, re.DOTALL | re.IGNORECASE
    )
    if fence:
        text = fence.group(1).strip()
    text = re.sub(
        r"^(?:(?:here (?:is|are)|to clean|below is|sure|of course|i have cleaned|the cleaned transcript|the transcript is (?:cleaned|ready)|transcript to clean|cleaned transcript|rewritten text|rewritten|rewrite).*?:\s*)+",
        "",
        text,
        flags=re.IGNORECASE | re.DOTALL,
    ).strip()
    text = re.sub(
        r"\n\n+(?:the cleaned transcript|this (?:output|cleaned version|maintains)|note:).*$",
        "",
        text,
        flags=re.DOTALL | re.IGNORECASE,
    ).strip()
    text = re.sub(r"<\|im_end\|>.*$", "", text, flags=re.DOTALL).strip()
    text = re.sub(r"<\|endoftext\|>.*$", "", text, flags=re.DOTALL).strip()
    quote_pairs = (('"', '"'), ("'", "'"), ("“", "”"), ("‘", "’"))
    for left, right in quote_pairs:
        if text.startswith(left) and text.endswith(right) and len(text) >= 2:
            text = text[len(left) : -len(right)].strip()
            break
    return text


def ensure_optional_runtime(config: dict) -> None:
    """Restart through uv with only the large backend needed by this adapter."""
    optional = {
        "llama": ("llama_cpp", "llama-cpp-python>=0.3.16,<0.4"),
        "punctuation": ("torch", "torch>=2.8,<3"),
        "coedit": ("torch", "torch>=2.8,<3"),
        "causal_lm": ("torch", "torch>=2.8,<3"),
    }
    requirement = optional.get(config["kind"])
    if requirement is None or importlib.util.find_spec(requirement[0]) is not None:
        return
    os.execvp(
        "uv",
        [
            "uv",
            "run",
            "--with",
            requirement[1],
            str(Path(__file__).resolve()),
            *sys.argv[1:],
        ],
    )


def existing_keys(path: Path) -> set[tuple[str, str]]:
    if not path.exists():
        return set()
    keys = set()
    for row in read_jsonl(path):
        keys.add((str(row.get("set", "")), str(row["id"])))
    return keys


def append_row(path: Path, row: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, ensure_ascii=False) + "\n")
        handle.flush()


def run(args: argparse.Namespace) -> int:
    set_names = [name.strip() for name in args.sets.split(",") if name.strip()]
    rows = load_inputs(set_names)
    output_path = OUTPUT_DIR / f"{args.model}.jsonl"
    done = existing_keys(output_path)
    pending = [row for row in rows if (row["set"], row["id"]) not in done]
    if args.limit is not None:
        pending = pending[: args.limit]
    if not pending:
        print(f"No pending rows for {args.model}.")
        return 0

    ensure_optional_runtime(MODELS[args.model])
    prompt = PROMPT_PATH.read_text(encoding="utf-8").strip()
    enhance = load_adapter(MODELS[args.model], prompt)
    for index, input_row in enumerate(pending):
        row_started = time.perf_counter()
        try:
            instruction = input_row.get("instruction")
            text, seconds, ttft_s = enhance(input_row["raw"], instruction=instruction)
            text = strip_chat_wrapping(text)
            error = None
        except Exception as exc:  # A failed item must not stop a long benchmark run.
            text = ""
            seconds = time.perf_counter() - row_started
            ttft_s = None
            error = f"{type(exc).__name__}: {exc}"
        row = {
            "id": input_row["id"],
            "set": input_row["set"],
            "raw": input_row["raw"],
            "text": text,
            "seconds": seconds,
            "ttft_s": ttft_s,
            "warm": index > 0,
            "error": error,
        }
        append_row(output_path, row)
        display_text = text if error is None else f"ERROR {error}"
        print(
            f"{input_row['id']}\t{seconds:.3f}s\t{input_row['raw']} -> {display_text}"
        )
    return 0


def selftest() -> int:
    assert strip_chat_wrapping("```text\n“Hello.”\n```") == "Hello."
    assert strip_chat_wrapping("Here is the cleaned transcript:\nHello.") == "Hello."
    assert (
        strip_chat_wrapping("<|channel>thought\nsome thinking\n<channel|>Hello.")
        == "Hello."
    )
    assert remove_fillers("Um, I, uh, know this, you know.") == "I, know this"
    assert sentence_case("hello. this works! yes") == "Hello. This works! Yes"
    rows = load_inputs(["dev"])
    assert rows and {"id", "set", "raw"} == set(rows[0])
    rw_rows = load_inputs(["rewrite"])
    assert rw_rows and rw_rows[0]["set"] == "rewrite" and "instruction" in rw_rows[0]
    print(
        f"selftest passed; loaded {len(rows)} dev rows and {len(rw_rows)} rewrite rows"
    )
    return 0


def main() -> int:
    args = parse_args()
    if args.list:
        print("\n".join(MODELS))
        return 0
    if args.selftest:
        return selftest()
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
