from __future__ import annotations

import statistics
from typing import Any

import jiwer

from score_text import (
    check_content_loss,
    compute_percentiles,
    normalize_asr,
    normalize_enhancement,
    word_distance,
)


def evaluate_asr_model(
    model_name: str,
    rows: list[dict[str, Any]],
    recordings_map: dict[str, dict[str, Any]],
    reference_map: dict[str, str],
    pseudo_ref_map: dict[str, str],
) -> dict[str, Any]:
    n = len(rows)
    errors = sum(1 for r in rows if r.get("error"))

    warm_seconds = []
    rtf_values = []
    cold_seconds = None

    for r in rows:
        if r.get("error"):
            continue
        sec = r.get("seconds")
        if sec is None:
            continue
        is_warm = r.get("warm", True)
        if not is_warm and cold_seconds is None:
            cold_seconds = sec
        if is_warm:
            warm_seconds.append(sec)
            rec_meta = recordings_map.get(r["id"])
            if rec_meta and rec_meta.get("duration_s", 0) > 0:
                rtf_values.append(sec / rec_meta["duration_s"])

    warm_med, warm_p90 = compute_percentiles(warm_seconds)
    rtf_med = round(float(statistics.median(rtf_values)), 4) if rtf_values else None

    # WER / CER vs human/consensus reference
    wer_ref, cer_ref = None, None
    if reference_map:
        refs, hyps = [], []
        for r in rows:
            if not r.get("error") and r["id"] in reference_map:
                ref_text = normalize_asr(reference_map[r["id"]])
                hyp_text = normalize_asr(r.get("text", ""))
                refs.append(ref_text)
                hyps.append(hyp_text)
        if refs:
            wer_ref = round(float(jiwer.wer(refs, hyps)), 4)
            cer_ref = round(float(jiwer.cer(refs, hyps)), 4)

    # Agreement WER vs pseudo-reference
    agreement_wer = None
    if pseudo_ref_map:
        p_refs, hyps = [], []
        for r in rows:
            if not r.get("error") and r["id"] in pseudo_ref_map:
                p_text = normalize_asr(pseudo_ref_map[r["id"]])
                hyp_text = normalize_asr(r.get("text", ""))
                p_refs.append(p_text)
                hyps.append(hyp_text)
        if p_refs:
            agreement_wer = round(float(jiwer.wer(p_refs, hyps)), 4)

    return {
        "model": model_name,
        "n": n,
        "errors": errors,
        "warm_median_s": warm_med,
        "warm_p90_s": warm_p90,
        "rtf_median": rtf_med,
        "cold_s": round(cold_seconds, 4) if cold_seconds is not None else None,
        "wer_ref": wer_ref,
        "cer_ref": cer_ref,
        "agreement_wer": agreement_wer,
    }


def evaluate_enhancement_model(
    model_name: str,
    rows: list[dict[str, Any]],
    recordings_map: dict[str, dict[str, Any]],
    user_edits: dict[str, str],
    synthetic_gold: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    n = len(rows)
    errors = sum(1 for r in rows if r.get("error"))

    warm_seconds = []
    warm_ttft = []

    for r in rows:
        if r.get("error"):
            continue
        sec = r.get("seconds")
        if sec is not None and r.get("warm", True):
            warm_seconds.append(sec)
        ttft = r.get("ttft_s")
        if ttft is not None and r.get("warm", True):
            warm_ttft.append(ttft)

    warm_med, warm_p90 = compute_percentiles(warm_seconds)
    ttft_med = round(float(statistics.median(warm_ttft)), 4) if warm_ttft else None

    # Synthetic set metrics
    synth_exact = 0
    synth_dists = []
    for r in rows:
        if r.get("error"):
            continue
        g = synthetic_gold.get(r["id"])
        if g:
            out_text = r.get("text", "")
            gold_text = g["gold"]
            if normalize_enhancement(out_text) == normalize_enhancement(gold_text):
                synth_exact += 1
            synth_dists.append(word_distance(out_text, gold_text))

    synth_em_rate = round(synth_exact / len(synth_dists), 4) if synth_dists else None
    synth_mean_dist = round(sum(synth_dists) / len(synth_dists), 4) if synth_dists else None

    # Recordings metrics
    rec_afm_exact = 0
    rec_afm_dists = []
    rec_user_exact = 0
    rec_user_dists = []
    content_loss_count = 0
    length_ratios = []
    total_recs = 0

    for r in rows:
        if r.get("error"):
            continue
        # Check if row is from recordings
        is_rec = (r.get("set") == "recordings") or (r["id"] in recordings_map)
        if not is_rec:
            continue

        total_recs += 1
        rec_meta = recordings_map.get(r["id"], {})
        raw_text = r.get("raw") or rec_meta.get("raw", "")
        out_text = r.get("text", "")

        # (a) vs AFM output
        afm_text = rec_meta.get("afm")
        if afm_text is not None:
            if normalize_enhancement(out_text) == normalize_enhancement(afm_text):
                rec_afm_exact += 1
            rec_afm_dists.append(word_distance(out_text, afm_text))

        # (b) vs user final from edits.jsonl (only source=edit)
        user_final = user_edits.get(r["id"])
        if user_final is not None:
            if normalize_enhancement(out_text) == normalize_enhancement(user_final):
                rec_user_exact += 1
            rec_user_dists.append(word_distance(out_text, user_final))

        # (c) content-loss rate
        if check_content_loss(raw_text, out_text):
            content_loss_count += 1

        # (d) length ratio median
        if len(raw_text) > 0:
            length_ratios.append(len(out_text) / len(raw_text))

    afm_em_rate = round(rec_afm_exact / len(rec_afm_dists), 4) if rec_afm_dists else None
    afm_mean_dist = round(sum(rec_afm_dists) / len(rec_afm_dists), 4) if rec_afm_dists else None
    user_em_rate = round(rec_user_exact / len(rec_user_dists), 4) if rec_user_dists else None
    user_mean_dist = round(sum(rec_user_dists) / len(rec_user_dists), 4) if rec_user_dists else None
    content_loss_rate = round(content_loss_count / total_recs, 4) if total_recs > 0 else None
    len_ratio_med = round(float(statistics.median(length_ratios)), 4) if length_ratios else None

    return {
        "model": model_name,
        "n": n,
        "errors": errors,
        "warm_median_s": warm_med,
        "warm_p90_s": warm_p90,
        "ttft_s_median": ttft_med,
        "synthetic_exact_match": synth_em_rate,
        "synthetic_mean_word_distance": synth_mean_dist,
        "recordings_afm_exact_match": afm_em_rate,
        "recordings_afm_mean_word_distance": afm_mean_dist,
        "recordings_user_exact_match": user_em_rate,
        "recordings_user_mean_word_distance": user_mean_dist,
        "recordings_content_loss_rate": content_loss_rate,
        "recordings_length_ratio_median": len_ratio_med,
    }
