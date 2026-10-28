#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = [
#   "huggingface-hub>=1,<2",
#   "jiwer>=3,<4",
#   "llama-cpp-python>=0.3.16,<0.4",
#   "numpy>=2,<3",
#   "onnxruntime>=1.20,<2",
#   "tokenizers>=0.21,<1",
# ]
# ///

"""Bench the GECToR grammar tagger as a second pass after s1-mini.

stage1 runs s1-mini on the synthetic and real inputs. stage2 runs GECToR on those outputs
at each threshold. report prints the tables. Model files: eval/data/local/gector/.
"""

import argparse
import difflib
import json
import re
import statistics
import sys
import time
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import enhance  # noqa: E402
import score  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GECTOR_DIR = ROOT / "eval/data/local/gector"
REAL_PATH = ROOT / "eval/data/local/real-s1.jsonl"
OUT_DIR = ROOT / "eval/results/gector"
LABELS_PATH = OUT_DIR / "labels.json"
S1_GGUF = (
    Path.home() / "Library/Application Support/com.sotto.Sotto/GGUFModels/s1-mini-q4_k_m.gguf"
)
THRESHOLDS = (0.6, 0.7, 0.8)
MAX_ROUNDS = 3
# enhance.py turns this into "[Styling: semi-formal] [Structure: lists] [Context: general]",
# the control line Sotto/Services/AIEnhancement/GGUFProvider.swift:340 sends.
REAL_INSTRUCTION = "lists"

# A word, or words joined by - . / @ ('hyphenated words and file names stay whole'), or one symbol.
TOKEN_RE = re.compile(r"[\w'’]+(?:[-./@][\w'’]+)*|[^\w\s]")
BULLET_RE = re.compile(r"^\s*(?:[-*•]|\d+[.)])\s+")
NO_SPACE_BEFORE = set(".,;:!?)%]}")
CLOSERS = set('"\'”’)]}')


def is_locked(word: str) -> bool:
    """Code-like tokens GECToR may not change or delete."""
    return (
        any(c in word for c in "._/@")
        or any(c.isdigit() for c in word)
        or any(c.isupper() for c in word[1:])
    )


class Tagger:
    def __init__(self) -> None:
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer

        meta = json.loads((GECTOR_DIR / "labels.json").read_text())
        self.labels = meta["labels"][:-1]  # the trailing <PAD> is not in the label head
        self.max_len = meta["max_length"]
        self.tok = Tokenizer.from_file(str(GECTOR_DIR / "tokenizer.json"))
        self.np = np
        self.sess = ort.InferenceSession(
            str(GECTOR_DIR / "model.onnx"), providers=["CPUExecutionProvider"]
        )
        self.verbs = {}
        for line in (GECTOR_DIR / "verb-form-vocab.txt").read_text().splitlines():
            pair, _, forms = line.partition(":")
            words = pair.split("_")
            if forms and len(words) == 2:
                self.verbs[(words[0], forms)] = words[1]

    def encode(self, words: list[str]):
        return self.tok.encode(["$START", *words], is_pretokenized=True)

    def fits(self, words: list[str]) -> bool:
        return len(self.encode(words).ids) <= self.max_len

    def predict(self, words: list[str]):
        """Per-position (START plus each word, first sub-token) label probs and error probs."""
        enc = self.encode(words)
        first = {}
        for pos, word_id in enumerate(enc.word_ids):
            if word_id is not None and word_id not in first:
                first[word_id] = pos
        ids = self.np.array([enc.ids], dtype=self.np.int64)
        probs, err = self.sess.run(
            ["label_probs", "error_probs"],
            {"input_ids": ids, "attention_mask": self.np.ones_like(ids)},
        )
        rows = [first[i] for i in range(len(words) + 1)]
        return probs[0][rows], err[0][rows]

    def transform(self, word: str, tag: str) -> str | None:
        if tag.startswith("$TRANSFORM_VERB_"):
            forms = tag.removeprefix("$TRANSFORM_VERB_")
            hit = self.verbs.get((word, forms)) or self.verbs.get((word.lower(), forms))
            if hit and word[:1].isupper():
                hit = hit.capitalize()
            return hit
        if tag == "$TRANSFORM_AGREEMENT_SINGULAR":
            return word[:-1] if word.endswith("s") else None
        if tag == "$TRANSFORM_AGREEMENT_PLURAL":
            return word + "s"
        return None  # $TRANSFORM_CASE_* is dropped

    def correct(self, toks: list[list], threshold: float):
        """One round on one chunk of [text, space_before] tokens. Returns (tokens, applied tags)."""
        probs, err = self.predict([t[0] for t in toks])
        if err.max() < threshold:
            return toks, []
        best = probs.argmax(axis=1)
        tags = {
            i: self.labels[b]
            for i, b in enumerate(best)
            if probs[i, b] >= threshold and self.labels[b] not in ("$KEEP", "<OOV>")
        }
        out, applied, start_insert = [], [], False
        for i in range(len(toks) + 1):
            tag = tags.get(i)
            if i > 0:
                text, sp = toks[i - 1]
                keep = True
                if tag and not is_locked(text):
                    if tag == "$DELETE":
                        keep = False
                        applied.append(tag)
                    elif tag.startswith("$REPLACE_"):
                        text = tag.removeprefix("$REPLACE_")
                        applied.append(tag)
                    elif tag.startswith("$TRANSFORM_"):
                        new = self.transform(text, tag)
                        if new:
                            text = new
                            applied.append(tag)
                if keep:
                    out.append([text, sp or (start_insert and text not in NO_SPACE_BEFORE)])
                    start_insert = False
            if tag and tag.startswith("$APPEND_"):
                text = tag.removeprefix("$APPEND_")
                out.append([text, text not in NO_SPACE_BEFORE and not text.startswith("'")])
                applied.append(tag)
                start_insert = i == 0
        return out, applied


def detok(toks: list[list]) -> str:
    return "".join((" " if sp and i else "") + text for i, (text, sp) in enumerate(toks))


def line_tokens(body: str) -> list[list]:
    return [
        [m.group(), m.start() > 0 and body[m.start() - 1].isspace()]
        for m in TOKEN_RE.finditer(body)
    ]


def chunks(tagger: Tagger, toks: list[list]):
    """Split tokens into sentences, then halve any piece that exceeds the model length."""
    pending, cur = [], []
    for tok in toks:
        if cur and cur[-1][0] in (".", "!", "?") and not (tok[0] in CLOSERS and not tok[1]):
            pending.append(cur)
            cur = []
        cur.append(tok)
    if cur:
        pending.append(cur)
    while pending:
        piece = pending.pop(0)
        if len(piece) > 1 and not tagger.fits([t[0] for t in piece]):
            mid = len(piece) // 2
            pending[:0] = [piece[:mid], piece[mid:]]
        else:
            yield piece


def gector(tagger: Tagger, text: str, threshold: float):
    """Run up to MAX_ROUNDS on each sentence. Returns (text, applied tags). Unchanged text is returned as is."""
    lines, applied = [], []
    for line in text.split("\n"):
        bullet = BULLET_RE.match(line)
        prefix = bullet.group() if bullet else ""
        toks = line_tokens(line[len(prefix) :])
        fixed = []
        for piece in chunks(tagger, toks):
            if not any(re.search(r"\w", t[0]) for t in piece):
                fixed += piece  # punctuation only, nothing to tag
                continue
            for _ in range(MAX_ROUNDS):
                piece, tags = tagger.correct(piece, threshold)
                applied += tags
                if not tags or not tagger.fits([t[0] for t in piece]):
                    break
            fixed += piece
        lines.append(prefix + detok(fixed) if toks else line)
    return ("\n".join(lines) if applied else text), applied


def word_edits(before: str, after: str, context: int = 2) -> list[dict]:
    a, b = before.split(), after.split()
    edits = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op == "equal":
            continue
        lo, hi = max(i1 - context, 0), i2 + context
        edits.append(
            {
                "before": " ".join(a[lo:hi]),
                "after": " ".join(a[lo:i1] + b[j1:j2] + a[i2:hi]),
            }
        )
    return edits


def content_words(text: str) -> Counter:
    return Counter(w for w in re.findall(r"[a-z0-9]+", text.lower()) if len(w) >= 4)


def recall(stage1: str, stage2: str) -> float:
    ref = content_words(stage1)
    total = sum(ref.values())
    if not total:
        return 1.0
    return sum((ref & content_words(stage2)).values()) / total


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def inputs() -> dict[str, list[dict]]:
    synthetic = []
    for name in ("dev", "eval", "heldout"):
        for row in read_jsonl(ROOT / f"eval/data/enhancement-{name}.jsonl"):
            synthetic.append({"id": row["id"], "raw": row["raw"], "gold": row["gold"]})
    return {"synthetic": synthetic, "real": read_jsonl(REAL_PATH)}


def stage1(args) -> None:
    config = {**enhance.MODELS["s1-mini-q4"], "path": str(S1_GGUF)}
    run = enhance.load_llama(config)
    for name, rows in inputs().items():
        path = OUT_DIR / f"stage1-{name}.jsonl"
        done = {r["id"] for r in read_jsonl(path)} if path.exists() else set()
        instruction = REAL_INSTRUCTION if name == "real" else None
        pending = [r for r in rows if r["id"] not in done]
        for row in pending[: args.limit]:
            text, seconds, _ = run(row["raw"], instruction=instruction)
            out = {
                "id": row["id"],
                "raw": row["raw"],
                "text": enhance.strip_chat_wrapping(text),
                "seconds": seconds,
            }
            enhance.append_row(path, out)
            print(name, row["id"], f"{seconds:.2f}s", flush=True)


def stage2(_args) -> None:
    tagger = Tagger()
    gector(tagger, "Warm up the session, are there anything left?", 0.6)
    for threshold in THRESHOLDS:
        rows = []
        for name in ("synthetic", "real"):
            for row in read_jsonl(OUT_DIR / f"stage1-{name}.jsonl"):
                started = time.perf_counter()
                text, applied = gector(tagger, row["text"], threshold)
                ms = (time.perf_counter() - started) * 1000
                rows.append(
                    {
                        "set": name,
                        "id": row["id"],
                        "stage1": row["text"],
                        "stage2": text,
                        "ms": ms,
                        "tags": applied,
                        "edits": word_edits(row["text"], text) if applied else [],
                    }
                )
        (OUT_DIR / f"stage2-{threshold}.json").write_text(json.dumps(rows, ensure_ascii=False))
        print(f"threshold {threshold}: {sum(1 for r in rows if r['tags'])} of {len(rows)} changed")


def pct(values: list[float], q: float) -> float:
    ordered = sorted(values)
    return ordered[max(1, round(q * len(ordered))) - 1]


def report(args) -> None:
    gold = {r["id"]: r["gold"] for r in inputs()["synthetic"]}
    labels = json.loads(LABELS_PATH.read_text()) if LABELS_PATH.exists() else {}
    exact = lambda a, b: score.normalize_enhancement(a) == score.normalize_enhancement(b)  # noqa: E731
    table = [
        "| Threshold | Synth exact before → after | Synth edit dist before → after | Synth better / worse | Real changed | good / bad / neutral | Real recall (mean, min) | p50 / p95 ms synth | p50 / p95 ms real |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    listing = {}
    for threshold in THRESHOLDS:
        rows = json.loads((OUT_DIR / f"stage2-{threshold}.json").read_text())
        synth = [r for r in rows if r["set"] == "synthetic"]
        real = [r for r in rows if r["set"] == "real"]
        before = [score.word_distance(r["stage1"], gold[r["id"]]) for r in synth]
        after = [score.word_distance(r["stage2"], gold[r["id"]]) for r in synth]
        better = sum(a < b for a, b in zip(after, before))
        worse = sum(a > b for a, b in zip(after, before))
        em_before = sum(exact(r["stage1"], gold[r["id"]]) for r in synth)
        em_after = sum(exact(r["stage2"], gold[r["id"]]) for r in synth)
        changed = [r for r in real if r["tags"]]
        counts = Counter(
            labels.get(f"{e['before']} -> {e['after']}", ["unlabeled"])[0]
            for r in changed
            for e in r["edits"]
        )
        recalls = [recall(r["stage1"], r["stage2"]) for r in real]
        ms = lambda part: f"{statistics.median(x['ms'] for x in part):.0f} / {pct([x['ms'] for x in part], 0.95):.0f}"  # noqa: E731
        table.append(
            f"| {threshold} | {em_before}/{len(synth)} → {em_after}/{len(synth)} "
            f"| {sum(before)/len(before):.4f} → {sum(after)/len(after):.4f} | {better} / {worse} "
            f"| {len(changed)}/{len(real)} | {counts['good']} / {counts['bad']} / {counts['neutral']}"
            f"{' (+' + str(counts['unlabeled']) + ' unlabeled)' if counts['unlabeled'] else ''} "
            f"| {sum(recalls)/len(recalls):.4f}, {min(recalls):.4f} | {ms(synth)} | {ms(real)} |"
        )
        listing[threshold] = (synth, real, changed)
    print("\n".join(table))
    synth, real, changed = listing[args.recommend]
    print(f"\n## Real edits at threshold {args.recommend}\n")
    print("| # | id | before -> after | label | reason |\n|---|---|---|---|---|")
    n = 0
    for r in changed:
        for e in r["edits"]:
            n += 1
            label, reason = labels.get(f"{e['before']} -> {e['after']}", ["unlabeled", ""])
            print(f"| {n} | {r['id']} | {e['before']} -> {e['after']} | {label} | {reason} |")
    print(f"\n## Synthetic cases that got worse at threshold {args.recommend}\n")
    for r in synth:
        if score.word_distance(r["stage2"], gold[r["id"]]) > score.word_distance(r["stage1"], gold[r["id"]]):
            print(f"- {r['id']}: " + "; ".join(f"{e['before']} -> {e['after']}" for e in r["edits"]))


def selftest(_args) -> None:
    assert is_locked("voice.md") and is_locked("parse_audio") and is_locked("camelCase")
    assert is_locked("a@b.com") and is_locked("v2") and is_locked("src/app")
    assert not is_locked("re-ranking") and not is_locked("Hello") and not is_locked("don't")
    text = "Rename it to voice.md, then re-ranking works (maybe)."
    assert detok(line_tokens(text)) == text
    assert [t[0] for t in line_tokens("a re-ranking voice.md.")] == ["a", "re-ranking", "voice.md", "."]
    tagger = Tagger()
    probs, err = tagger.predict(["Are", "there", "anything", "left", "?"])
    assert probs.shape == (6, len(tagger.labels)) and err.shape == (6,)
    fixed, applied = gector(tagger, "Rename voice.md and run the tests.", 0.6)
    assert "voice.md" in fixed, fixed
    print("selftest passed:", gector(tagger, "Are there anything left to do?", 0.6))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    s1 = sub.add_parser("stage1")
    s1.add_argument("--limit", type=int)
    s1.set_defaults(fn=stage1)
    sub.add_parser("stage2").set_defaults(fn=stage2)
    rp = sub.add_parser("report")
    rp.add_argument("--recommend", type=float, default=0.7, choices=THRESHOLDS)
    rp.set_defaults(fn=report)
    sub.add_parser("selftest").set_defaults(fn=selftest)
    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
