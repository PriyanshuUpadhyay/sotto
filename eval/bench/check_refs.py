# /// script
# requires-python = ">=3.12,<3.14"
# ///
"""Check reference transcripts against their audio, one clip at a time.

For each unchecked row in eval/data/local/reference.jsonl, this plays the clip
(macOS `afplay`), shows the reference text and any note, and asks:

  Enter      the text matches the audio -> mark it checked
  r          play the clip again
  s          skip this clip for now
  q          stop (answers so far are saved)
  any text   the text you heard -> save it and mark it checked

Type exactly what the speaker said, as you hear it, and do not copy any model's
output. score.py scores only checked rows once any exist. The file is rewritten
after each answer, so stopping at any point loses nothing.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile

DEFAULT_DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "local")


def load_jsonl(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def save_jsonl(path: str, rows: list[dict]) -> None:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", default=os.environ.get("SOTTO_EVAL_LOCAL", DEFAULT_DATA_DIR))
    args = parser.parse_args()

    ref_path = os.path.join(args.data_dir, "reference.jsonl")
    rows = load_jsonl(ref_path)
    audio = {r["id"]: r.get("audio") for r in load_jsonl(os.path.join(args.data_dir, "recordings.jsonl"))}
    notes_path = os.path.join(args.data_dir, "reference-notes.jsonl")
    notes = {r["id"]: r.get("note", "") for r in load_jsonl(notes_path)} if os.path.exists(notes_path) else {}

    todo = [i for i, r in enumerate(rows) if r.get("checked") is not True]
    print(f"{len(rows) - len(todo)} of {len(rows)} checked; {len(todo)} to go.")
    for n, i in enumerate(todo, 1):
        row = rows[i]
        path = audio.get(row["id"])
        if not path or not os.path.exists(path):
            print(f"[{n}/{len(todo)}] {row['id']}: audio not found, skipped")
            continue
        print(f"\n[{n}/{len(todo)}] {row['id']}\n  text: {row['text']}")
        if notes.get(row["id"]):
            print(f"  note: {notes[row['id']]}")
        while True:
            subprocess.run(["afplay", path], check=False)
            answer = input("  Enter=matches, r=replay, s=skip, q=quit, or type what you heard: ").strip()
            if answer != "r":
                break
        if answer == "q":
            break
        if answer == "s":
            continue
        if answer:
            row["text"] = answer
        row["checked"] = True
        save_jsonl(ref_path, rows)

    done = sum(1 for r in rows if r.get("checked") is True)
    print(f"\n{done} of {len(rows)} checked.")


if __name__ == "__main__":
    main()
