# Sotto Model Benchmark
Benchmark candidate ASR and enhancement models against Sotto production data and baselines.

1. Export data: uv run eval/bench/export.py
2. Run model: generate eval/results/bench/asr/<slug>.jsonl or eval/results/bench/enhance/<slug>.jsonl
3. Score results: uv run eval/bench/score.py

Outputs land in eval/results/bench/report.md and eval/results/bench/report.json.

Reference text: score.py measures WER against eval/data/local/reference.jsonl. Build each reference by listening to the clip, never from a model's output, because a model-made reference favours that model. Mark a row checked with uv run eval/bench/check_refs.py, which plays each unchecked clip and saves your answer. Once any row is checked, only checked rows score; the report names which kind of reference it used.

Test audio: a Debug build started with SOTTO_AUDIO_FIXTURE=<audio file> plays that file in place of the microphone on every recording (10 ms chunks at real-time pace, looping), so the live path from capture to paste runs with no person speaking. Example: SOTTO_AUDIO_FIXTURE=$PWD/clip.wav /Applications/Sotto.app/Contents/MacOS/Sotto

Sandbox cache env vars: UV_CACHE_DIR=eval/data/local/uv-cache and HF_HOME=eval/data/local/hf-cache.

GECToR grammar pass after s1-mini (needs model.onnx, tokenizer.json, labels.json and verb-form-vocab.txt from https://huggingface.co/deepquillapp/gector-grammar in eval/data/local/gector/, and eval/data/local/real-s1.jsonl): uv run eval/bench/gector.py stage1 && uv run eval/bench/gector.py stage2 && uv run eval/bench/gector.py report --recommend 0.8

AFM (Apple Foundation Models) cleanup with a chosen system prompt from eval/bench/prompts/ (macOS 26+, Apple Intelligence on): swiftc -O eval/bench/afm.swift -o <tmp>/afm-bench, then <tmp>/afm-bench --slug afm-short-v6 --prompt eval/bench/prompts/afm-short-v6.txt --user-format tags --guardrails permissive. Rows land in eval/results/bench/enhance/<slug>.jsonl. Set SOTTO_EVAL_LOCAL when eval/data/local lives in another checkout.
