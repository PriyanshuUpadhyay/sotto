from __future__ import annotations

import math
import re
import statistics
import string
from collections import Counter


def compute_percentiles(vals: list[float]) -> tuple[float | None, float | None]:
    if not vals:
        return None, None
    s = sorted(vals)
    med = float(statistics.median(s))
    rank = max(1, math.ceil(0.90 * len(s)))
    p90 = float(s[rank - 1])
    return round(med, 4), round(p90, 4)


def normalize_asr(text: str) -> str:
    """Normalize text for ASR scoring: lowercase, strip punctuation, collapse whitespace."""
    if not text:
        return ""
    t = text.lower()
    t = t.replace("-", " ")
    t = t.translate(str.maketrans("", "", string.punctuation))
    return " ".join(t.split())


def normalize_enhancement(s: str) -> str:
    """Whitespace + quote normalization matching SottoTests/EnhancementEvalTests.swift."""
    t = s
    for a, b in [("\u2019", "'"), ("\u2018", "'"), ("\u201c", '"'), ("\u201d", '"')]:
        t = t.replace(a, b)
    lines: list[str] = []
    for raw_line in t.splitlines():
        tokens = [tk for tk in raw_line.replace("\t", " ").split(" ") if tk]
        squeezed = " ".join(tokens)
        if not squeezed and lines and lines[-1] == "":
            continue
        lines.append(squeezed)
    while lines and lines[0] == "":
        lines.pop(0)
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def words_enhancement(s: str) -> list[str]:
    return normalize_enhancement(s).split()


def word_distance(output: str, gold: str) -> float:
    """Word-level Levenshtein divided by gold word count matching EnhancementEvalTests.swift."""
    a = words_enhancement(output)
    b = words_enhancement(gold)
    if not b:
        return 0.0 if not a else 1.0
    if not a:
        return 1.0
    prev = list(range(len(b) + 1))
    cur = [0] * (len(b) + 1)
    for i in range(1, len(a) + 1):
        cur[0] = i
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        prev, cur = cur, [0] * (len(b) + 1)
    return prev[len(b)] / len(b)


def check_content_loss(raw: str, output: str) -> bool:
    """True if >20% of raw's content words (len >= 4, lowercase) are missing from output."""
    raw_words = [w for w in re.findall(r"[a-z0-9]+", raw.lower()) if len(w) >= 4]
    if not raw_words:
        return False
    raw_counter = Counter(raw_words)
    out_counter = Counter(re.findall(r"[a-z0-9]+", output.lower()))
    missing_cnt = sum(max(0, count - out_counter[w]) for w, count in raw_counter.items())
    return (missing_cnt / len(raw_words)) > 0.20
