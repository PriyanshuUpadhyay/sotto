# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = [
#     "jiwer>=3.0.0",
# ]
# ///
"""Score ASR and enhancement models against Sotto production data and baselines."""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import statistics
import string
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any

import jiwer

# The moved names stay importable from here: gector.py reads score.word_distance and others.
from score_eval import evaluate_asr_model, evaluate_enhancement_model  # noqa: F401
from score_text import (  # noqa: F401
    check_content_loss,
    compute_percentiles,
    normalize_asr,
    normalize_enhancement,
    word_distance,
    words_enhancement,
)

DEFAULT_RESULTS_DIR = os.path.join(
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..")), "results", "bench"
)
DEFAULT_DATA_DIR = os.path.join(
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..")), "data", "local"
)
DEFAULT_EVAL_DIR = os.path.join(
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..")), "data"
)


def load_jsonl(path: str) -> list[dict[str, Any]]:
    if not os.path.exists(path):
        return []
    records = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def load_synthetic_sets(eval_dir: str) -> dict[str, dict[str, Any]]:
    """Loads enhancement-{dev,eval,heldout}.jsonl into a mapping id -> {set, raw, gold}."""
    gold_map = {}
    for subset in ["dev", "eval", "heldout"]:
        p = os.path.join(eval_dir, f"enhancement-{subset}.jsonl")
        if os.path.exists(p):
            for row in load_jsonl(p):
                gold_map[row["id"]] = {
                    "set": subset,
                    "raw": row.get("raw", ""),
                    "gold": row.get("gold", ""),
                }
    return gold_map


def fmt_pct(val: float | None) -> str:
    return f"{val * 100:.1f}%" if val is not None else "-"


def fmt_num(val: float | None, prec: int = 3) -> str:
    return f"{val:.{prec}f}" if val is not None else "-"


def generate_markdown(
    asr_results: list[dict[str, Any]],
    enh_results: list[dict[str, Any]],
    pseudo_ref_slug: str,
    has_ref: bool,
) -> str:
    lines = []
    lines.append("# Sotto Model Benchmark Report\n")

    lines.append("## ASR Models\n")
    ref_hdr = "WER (Ref) | CER (Ref) | " if has_ref else ""
    lines.append(
        f"| Model | N | Errors | Warm Med (s) | Warm P90 (s) | RTF | Cold (s) | {ref_hdr}Agreement WER vs {pseudo_ref_slug} |"
    )
    sep = "| --- | ---: | ---: | ---: | ---: | ---: | ---: | "
    if has_ref:
        sep += "---: | ---: | "
    sep += "---: |"
    lines.append(sep)

    for r in asr_results:
        row_str = (
            f"| {r['model']} | {r['n']} | {r['errors']} | {fmt_num(r['warm_median_s'])} | "
            f"{fmt_num(r['warm_p90_s'])} | {fmt_num(r['rtf_median'])} | {fmt_num(r['cold_s'])} | "
        )
        if has_ref:
            row_str += f"{fmt_pct(r['wer_ref'])} | {fmt_pct(r['cer_ref'])} | "
        row_str += f"{fmt_pct(r['agreement_wer'])} |"
        lines.append(row_str)

    lines.append("\n## Enhancement Models\n")
    lines.append(
        "| Model | N | Errors | Warm Med (s) | Warm P90 (s) | TTFT Med (s) | "
        "Synth EM | Synth Dist | AFM EM | AFM Dist | User Edit EM | User Edit Dist | Content Loss | Len Ratio |"
    )
    lines.append(
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
    )

    for r in enh_results:
        lines.append(
            f"| {r['model']} | {r['n']} | {r['errors']} | {fmt_num(r['warm_median_s'])} | "
            f"{fmt_num(r['warm_p90_s'])} | {fmt_num(r['ttft_s_median'])} | "
            f"{fmt_pct(r['synthetic_exact_match'])} | {fmt_num(r['synthetic_mean_word_distance'])} | "
            f"{fmt_pct(r['recordings_afm_exact_match'])} | {fmt_num(r['recordings_afm_mean_word_distance'])} | "
            f"{fmt_pct(r['recordings_user_exact_match'])} | {fmt_num(r['recordings_user_mean_word_distance'])} | "
            f"{fmt_pct(r['recordings_content_loss_rate'])} | {fmt_num(r['recordings_length_ratio_median'])} |"
        )

    lines.append("")
    return "\n".join(lines)


def run_selftest() -> None:
    """Self-test verifying metric calculation and report formatting."""
    with tempfile.TemporaryDirectory() as td:
        dummy_gold = {
            "s1": {"set": "dev", "raw": "hello world", "gold": "Hello, world!"},
            "s2": {"set": "dev", "raw": "testing one two", "gold": "Testing 1, 2."},
        }
        dummy_recs = {
            "r1": {"raw": "hello world test", "afm": "Hello world test.", "duration_s": 2.0, "asr_s": 0.1},
        }
        dummy_edits = {"r1": "Hello world test!"}

        enh_rows = [
            {"id": "s1", "set": "dev", "raw": "hello world", "text": "Hello, world!", "seconds": 0.5, "ttft_s": 0.2, "warm": True, "error": None},
            {"id": "s2", "set": "dev", "raw": "testing one two", "text": "Testing 1 2.", "seconds": 0.6, "ttft_s": 0.25, "warm": True, "error": None},
            {"id": "r1", "set": "recordings", "raw": "hello world test", "text": "Hello world test.", "seconds": 0.7, "ttft_s": 0.3, "warm": True, "error": None},
        ]
        enh_res = evaluate_enhancement_model("test-model", enh_rows, dummy_recs, dummy_edits, dummy_gold)
        assert enh_res["n"] == 3
        assert enh_res["errors"] == 0
        assert enh_res["synthetic_exact_match"] == 0.5
        assert enh_res["recordings_afm_exact_match"] == 1.0

        asr_rows = [
            {"id": "r1", "text": "hello world test", "seconds": 0.2, "warm": True, "error": None}
        ]
        asr_res = evaluate_asr_model("test-asr", asr_rows, dummy_recs, {"r1": "hello world test"}, {"r1": "hello world test"})
        assert asr_res["wer_ref"] == 0.0
        assert asr_res["agreement_wer"] == 0.0

        md = generate_markdown([asr_res], [enh_res], "test-asr", True)
        assert "# Sotto Model Benchmark Report" in md
        print("Score selftest passed successfully!")


def main() -> None:
    parser = argparse.ArgumentParser(description="Score Sotto candidate models.")
    parser.add_argument("--results-dir", default=DEFAULT_RESULTS_DIR, help="Path to bench results dir")
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR, help="Path to eval/data/local")
    parser.add_argument("--eval-dir", default=DEFAULT_EVAL_DIR, help="Path to eval/data")
    parser.add_argument("--pseudo-reference", default=None, help="ASR model slug to use as pseudo-reference")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of rows scored per model")
    parser.add_argument("--selftest", action="store_true", help="Run self-test and exit")
    args = parser.parse_args()

    if args.selftest:
        run_selftest()
        return

    results_dir = os.path.abspath(args.results_dir)
    data_dir = os.path.abspath(args.data_dir)
    eval_dir = os.path.abspath(args.eval_dir)

    asr_dir = os.path.join(results_dir, "asr")
    enh_dir = os.path.join(results_dir, "enhance")
    os.makedirs(asr_dir, exist_ok=True)
    os.makedirs(enh_dir, exist_ok=True)

    # 1. Load ground truth / base assets
    recordings_file = os.path.join(data_dir, "recordings.jsonl")
    recordings_rows = load_jsonl(recordings_file)
    recordings_map = {r["id"]: r for r in recordings_rows}

    edits_file = os.path.join(data_dir, "edits.jsonl")
    edits_rows = load_jsonl(edits_file)
    # Map transcription_id -> final for source=edit rows
    user_edits = {
        r["transcription_id"]: r["final"]
        for r in edits_rows
        if r.get("source") == "edit" and r.get("transcription_id")
    }

    ref_file = os.path.join(data_dir, "reference.jsonl")
    ref_rows = load_jsonl(ref_file)
    reference_map = {r["id"]: r["text"] for r in ref_rows if "id" in r and "text" in r}

    synthetic_gold = load_synthetic_sets(eval_dir)

    # 2. Gather ASR models
    asr_files = glob.glob(os.path.join(asr_dir, "*.jsonl"))
    asr_models_data: dict[str, list[dict[str, Any]]] = {}

    for f in asr_files:
        slug = Path(f).stem
        rows = load_jsonl(f)
        if args.limit:
            rows = rows[:args.limit]
        asr_models_data[slug] = rows

    # Always include parakeet-v2 pseudo-model from recordings.jsonl
    if "parakeet-v2" not in asr_models_data and recordings_rows:
        parakeet_rows = []
        for r in recordings_rows:
            parakeet_rows.append({
                "id": r["id"],
                "text": r.get("raw", ""),
                "seconds": r.get("asr_s"),
                "warm": True,
                "error": None,
            })
        if args.limit:
            parakeet_rows = parakeet_rows[:args.limit]
        asr_models_data["parakeet-v2"] = parakeet_rows

    # Choose pseudo-reference model slug
    if args.pseudo_reference:
        pseudo_ref_slug = args.pseudo_reference
    elif "parakeet-v2" in asr_models_data:
        pseudo_ref_slug = "parakeet-v2"
    elif asr_models_data:
        pseudo_ref_slug = sorted(asr_models_data.keys())[0]
    else:
        pseudo_ref_slug = "parakeet-v2"

    pseudo_ref_map = {}
    if pseudo_ref_slug in asr_models_data:
        for r in asr_models_data[pseudo_ref_slug]:
            if not r.get("error"):
                pseudo_ref_map[r["id"]] = r.get("text", "")

    # Score ASR models
    asr_scored: list[dict[str, Any]] = []
    for slug in sorted(asr_models_data.keys()):
        m_res = evaluate_asr_model(
            slug,
            asr_models_data[slug],
            recordings_map,
            reference_map,
            pseudo_ref_map,
        )
        asr_scored.append(m_res)

    # 3. Gather Enhancement models
    enh_files = glob.glob(os.path.join(enh_dir, "*.jsonl"))
    enh_models_data: dict[str, list[dict[str, Any]]] = {}

    for f in enh_files:
        slug = Path(f).stem
        rows = load_jsonl(f)
        if args.limit:
            rows = rows[:args.limit]
        enh_models_data[slug] = rows

    # Always include afm pseudo-model from recordings.jsonl
    if "afm" not in enh_models_data and recordings_rows:
        afm_rows = []
        for r in recordings_rows:
            if r.get("afm") is not None:
                afm_rows.append({
                    "id": r["id"],
                    "set": "recordings",
                    "raw": r.get("raw", ""),
                    "text": r.get("afm", ""),
                    "seconds": r.get("afm_s"),
                    "ttft_s": None,
                    "warm": True,
                    "error": None,
                })
        if args.limit:
            afm_rows = afm_rows[:args.limit]
        enh_models_data["afm"] = afm_rows

    # Score Enhancement models
    enh_scored: list[dict[str, Any]] = []
    for slug in sorted(enh_models_data.keys()):
        m_res = evaluate_enhancement_model(
            slug,
            enh_models_data[slug],
            recordings_map,
            user_edits,
            synthetic_gold,
        )
        enh_scored.append(m_res)

    # 4. Generate Reports
    md_report = generate_markdown(
        asr_scored,
        enh_scored,
        pseudo_ref_slug,
        has_ref=bool(reference_map),
    )

    report_md_path = os.path.join(results_dir, "report.md")
    with open(report_md_path, "w", encoding="utf-8") as f:
        f.write(md_report)

    report_json_path = os.path.join(results_dir, "report.json")
    json_data = {
        "metadata": {
            "pseudo_reference": pseudo_ref_slug,
            "has_human_reference": bool(reference_map),
            "recordings_count": len(recordings_rows),
            "edits_count": len(edits_rows),
            "synthetic_count": len(synthetic_gold),
        },
        "asr": {r["model"]: r for r in asr_scored},
        "enhancement": {r["model"]: r for r in enh_scored},
    }
    with open(report_json_path, "w", encoding="utf-8") as f:
        json.dump(json_data, f, indent=2)

    # Print markdown to stdout
    print(md_report)


if __name__ == "__main__":
    main()
