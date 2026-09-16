# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = []
# ///
"""Export Sotto recordings, edit records, and AFM timing baseline to JSONL/JSON."""

from __future__ import annotations

import argparse
import csv
import datetime
import json
import math
import os
import shutil
import sqlite3
import statistics
import tempfile
import urllib.parse
import uuid
from pathlib import Path

CORE_DATA_EPOCH = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
DEFAULT_APP_SUPPORT = os.path.expanduser("~/Library/Application Support/com.sotto.Sotto")
DEFAULT_OUT_DIR = os.path.join(
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..")), "data", "local"
)


def parse_uuid(val: bytes | str | None) -> str | None:
    if val is None:
        return None
    if isinstance(val, bytes):
        try:
            return str(uuid.UUID(bytes=val))
        except ValueError:
            return val.hex()
    s = str(val).strip()
    try:
        return str(uuid.UUID(s))
    except ValueError:
        return s


def parse_core_data_timestamp(val: float | int | None) -> str | None:
    if val is None:
        return None
    try:
        dt = CORE_DATA_EPOCH + datetime.timedelta(seconds=float(val))
        return dt.isoformat()
    except (ValueError, OverflowError):
        return None


def parse_file_url(url_str: str | None) -> str | None:
    if not url_str:
        return None
    parsed = urllib.parse.urlparse(url_str)
    if parsed.scheme == "file":
        return urllib.parse.unquote(parsed.path)
    return urllib.parse.unquote(url_str)


def copy_store_to_dir(src_dir: str, store_name: str, dst_dir: str) -> str:
    base = os.path.join(src_dir, store_name)
    dst_base = os.path.join(dst_dir, store_name)
    found = False
    for ext in ["", "-wal", "-shm"]:
        p = base + ext
        if os.path.exists(p):
            shutil.copy2(p, dst_base + ext)
            found = True
    if not found:
        raise FileNotFoundError(f"Store file not found: {base}")
    return dst_base


def compute_metrics(vals: list[float]) -> dict[str, float | None]:
    if not vals:
        return {"median": None, "p90": None}
    s = sorted(vals)
    med = float(statistics.median(s))
    rank = max(1, math.ceil(0.90 * len(s)))
    p90 = float(s[rank - 1])
    return {"median": round(med, 4), "p90": round(p90, 4)}


def export_recordings(
    default_store_path: str,
    out_path: str,
    limit: int | None = None,
) -> tuple[int, int]:
    """Exports ZTRANSCRIPTION to recordings.jsonl. Returns (exported_count, skipped_count)."""
    conn = sqlite3.connect(f"file:{default_store_path}?mode=ro", uri=True)
    c = conn.cursor()
    c.execute("""
        SELECT ZID, ZAUDIOFILEURL, ZDURATION, ZTEXT, ZENHANCEDTEXT,
               ZENHANCEMENTDURATION, ZTRANSCRIPTIONMODELNAME, ZTRANSCRIPTIONDURATION,
               ZPROMPTNAME, ZTIMESTAMP
        FROM ZTRANSCRIPTION
        ORDER BY ZTIMESTAMP ASC
    """)
    rows = c.fetchall()
    conn.close()

    exported = 0
    skipped = 0
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        for r in rows:
            zid, audio_url, dur, text, enh, enh_dur, asr_model, asr_dur, prompt, ts = r
            wav_path = parse_file_url(audio_url)
            if not wav_path or not os.path.exists(wav_path):
                skipped += 1
                continue

            row_id = parse_uuid(zid)
            rec = {
                "id": row_id,
                "audio": wav_path,
                "duration_s": float(dur) if dur is not None else 0.0,
                "raw": str(text) if text is not None else "",
                "afm": str(enh) if enh is not None else None,
                "afm_s": float(enh_dur) if enh_dur is not None else None,
                "asr_model": str(asr_model) if asr_model is not None else None,
                "prompt": str(prompt) if prompt is not None else None,
                "timestamp": parse_core_data_timestamp(ts),
                "asr_s": float(asr_dur) if asr_dur is not None else None,
            }
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            exported += 1
            if limit and exported >= limit:
                break

    return exported, skipped


def export_edits(
    dictionary_store_path: str,
    out_path: str,
    limit: int | None = None,
) -> int:
    """Exports ZENHANCEMENTEDITRECORD to edits.jsonl. Returns exported count."""
    conn = sqlite3.connect(f"file:{dictionary_store_path}?mode=ro", uri=True)
    c = conn.cursor()
    c.execute("""
        SELECT ZID, ZTRANSCRIPTIONID, ZRAWTEXT, ZENHANCEDTEXT,
               ZFINALTEXT, ZEDITKINDRAW, ZSIGNALSOURCERAW, ZTIMESTAMP
        FROM ZENHANCEMENTEDITRECORD
        ORDER BY ZTIMESTAMP ASC
    """)
    rows = c.fetchall()
    conn.close()

    exported = 0
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        for r in rows:
            zid, txid, raw, enh, final, kind, src, ts = r
            rec = {
                "id": parse_uuid(zid),
                "transcription_id": parse_uuid(txid),
                "raw": str(raw) if raw is not None else "",
                "enhanced": str(enh) if enh is not None else "",
                "final": str(final) if final is not None else "",
                "kind": str(kind) if kind is not None else "",
                "source": str(src) if src is not None else "",
                "timestamp": parse_core_data_timestamp(ts),
            }
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            exported += 1
            if limit and exported >= limit:
                break

    return exported


def export_afm_baseline(csv_path: str, out_path: str) -> dict:
    """Computes median and p90 of totalSeconds and ttftSeconds for outcome=success rows."""
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"AFM timings CSV not found: {csv_path}")

    groups: dict[str, dict[str, list[float]]] = {}
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("outcome") != "success":
                continue
            reused = row.get("sessionReused", "").strip().lower()
            if reused not in groups:
                groups[reused] = {"totalSeconds": [], "ttftSeconds": []}
            try:
                tot = float(row["totalSeconds"])
                groups[reused]["totalSeconds"].append(tot)
            except (ValueError, KeyError):
                pass
            try:
                ttft = float(row["ttftSeconds"])
                groups[reused]["ttftSeconds"].append(ttft)
            except (ValueError, KeyError):
                pass

    result: dict[str, dict] = {}
    all_tot: list[float] = []
    all_ttft: list[float] = []

    for reused_key, metrics in groups.items():
        all_tot.extend(metrics["totalSeconds"])
        all_ttft.extend(metrics["ttftSeconds"])
        tot_m = compute_metrics(metrics["totalSeconds"])
        ttft_m = compute_metrics(metrics["ttftSeconds"])
        result[reused_key] = {
            "count": len(metrics["totalSeconds"]),
            "totalSeconds": tot_m,
            "ttftSeconds": ttft_m,
        }

    overall_tot = compute_metrics(all_tot)
    overall_ttft = compute_metrics(all_ttft)
    result["overall"] = {
        "count": len(all_tot),
        "totalSeconds": overall_tot,
        "ttftSeconds": overall_ttft,
    }

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    return result


def run_selftest() -> None:
    """Self-test verifying export functions using temporary SQLite and CSV."""
    with tempfile.TemporaryDirectory() as td:
        dummy_wav = os.path.join(td, "test.wav")
        Path(dummy_wav).touch()

        db_path = os.path.join(td, "default.store")
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("""
            CREATE TABLE ZTRANSCRIPTION (
                Z_PK INTEGER PRIMARY KEY,
                ZID BLOB,
                ZAUDIOFILEURL VARCHAR,
                ZDURATION FLOAT,
                ZTEXT VARCHAR,
                ZENHANCEDTEXT VARCHAR,
                ZENHANCEMENTDURATION FLOAT,
                ZTRANSCRIPTIONMODELNAME VARCHAR,
                ZTRANSCRIPTIONDURATION FLOAT,
                ZPROMPTNAME VARCHAR,
                ZTIMESTAMP TIMESTAMP
            )
        """)
        u1 = uuid.uuid4()
        c.execute("""
            INSERT INTO ZTRANSCRIPTION VALUES (
                1, ?, ?, 5.0, 'test raw', 'test enhanced', 0.5,
                'Parakeet V2', 0.1, 'Default', 809944828.0
            )
        """, (u1.bytes, f"file://{dummy_wav}"))
        c.execute("""
            INSERT INTO ZTRANSCRIPTION VALUES (
                2, ?, 'file:///nonexistent.wav', 3.0, 'missing', NULL, NULL,
                'Parakeet V2', 0.1, 'Default', 809944830.0
            )
        """, (uuid.uuid4().bytes,))
        conn.commit()
        conn.close()

        dict_path = os.path.join(td, "dictionary.store")
        conn = sqlite3.connect(dict_path)
        c = conn.cursor()
        c.execute("""
            CREATE TABLE ZENHANCEMENTEDITRECORD (
                Z_PK INTEGER PRIMARY KEY,
                ZID BLOB,
                ZTRANSCRIPTIONID BLOB,
                ZRAWTEXT VARCHAR,
                ZENHANCEDTEXT VARCHAR,
                ZFINALTEXT VARCHAR,
                ZEDITKINDRAW VARCHAR,
                ZSIGNALSOURCERAW VARCHAR,
                ZTIMESTAMP TIMESTAMP
            )
        """)
        c.execute("""
            INSERT INTO ZENHANCEMENTEDITRECORD VALUES (
                1, ?, ?, 'raw', 'enh', 'final', 'style', 'edit', 809944835.0
            )
        """, (uuid.uuid4().bytes, u1.bytes))
        conn.commit()
        conn.close()

        csv_path = os.path.join(td, "timings.csv")
        with open(csv_path, "w", encoding="utf-8") as f:
            f.write("outcome,sessionReused,totalSeconds,ttftSeconds\n")
            f.write("success,true,1.0,0.5\n")
            f.write("success,false,2.0,1.0\n")

        rec_out = os.path.join(td, "recordings.jsonl")
        edits_out = os.path.join(td, "edits.jsonl")
        base_out = os.path.join(td, "afm-baseline.json")

        exp_rec, skp_rec = export_recordings(db_path, rec_out)
        assert exp_rec == 1, f"Expected 1 exported recording, got {exp_rec}"
        assert skp_rec == 1, f"Expected 1 skipped recording, got {skp_rec}"

        exp_edits = export_edits(dict_path, edits_out)
        assert exp_edits == 1, f"Expected 1 exported edit, got {exp_edits}"

        base_res = export_afm_baseline(csv_path, base_out)
        assert "true" in base_res and "false" in base_res

        with open(rec_out) as f:
            line = json.loads(f.readline())
            assert line["id"] == str(u1)
            assert line["duration_s"] == 5.0
            assert line["raw"] == "test raw"
            assert line["asr_s"] == 0.1

        print("Selftest passed successfully!")


def main() -> None:
    parser = argparse.ArgumentParser(description="Export Sotto data to JSONL/JSON.")
    parser.add_argument(
        "--out-dir",
        default=DEFAULT_OUT_DIR,
        help=f"Directory to write JSONL outputs to (default: {DEFAULT_OUT_DIR})",
    )
    parser.add_argument(
        "--app-support",
        default=DEFAULT_APP_SUPPORT,
        help=f"Path to Sotto Application Support directory (default: {DEFAULT_APP_SUPPORT})",
    )
    parser.add_argument("--limit", type=int, default=None, help="Limit number of rows exported")
    parser.add_argument("--selftest", action="store_true", help="Run self-test and exit")
    args = parser.parse_args()

    if args.selftest:
        run_selftest()
        return

    out_dir = os.path.abspath(args.out_dir)
    app_support = os.path.abspath(os.path.expanduser(args.app_support))

    print(f"Exporting Sotto data from: {app_support}")
    print(f"Destination: {out_dir}")

    with tempfile.TemporaryDirectory() as td:
        print("Copying stores to temporary directory...")
        default_copy = copy_store_to_dir(app_support, "default.store", td)
        dict_copy = copy_store_to_dir(app_support, "dictionary.store", td)

        rec_out = os.path.join(out_dir, "recordings.jsonl")
        rec_exp, rec_skip = export_recordings(default_copy, rec_out, limit=args.limit)
        print(f"recordings.jsonl: exported {rec_exp} rows (skipped {rec_skip} missing WAVs)")

        edits_out = os.path.join(out_dir, "edits.jsonl")
        edits_exp = export_edits(dict_copy, edits_out, limit=args.limit)
        print(f"edits.jsonl: exported {edits_exp} rows")

    csv_path = os.path.join(app_support, "enhancement-timings.csv")
    if os.path.exists(csv_path):
        base_out = os.path.join(out_dir, "afm-baseline.json")
        res = export_afm_baseline(csv_path, base_out)
        print(f"afm-baseline.json: written ({res['overall']['count']} success rows)")
    else:
        print(f"Warning: {csv_path} not found, skipping baseline generation.")

    print("Export complete.")


if __name__ == "__main__":
    main()
