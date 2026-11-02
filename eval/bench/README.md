# Sotto Model Benchmark
Benchmark candidate ASR and enhancement models against Sotto production data and baselines.

1. Export data: uv run eval/bench/export.py
2. Run model: generate eval/results/bench/asr/<slug>.jsonl or eval/results/bench/enhance/<slug>.jsonl
3. Score results: uv run eval/bench/score.py

Outputs land in eval/results/bench/report.md and eval/results/bench/report.json.

Sandbox cache env vars: UV_CACHE_DIR=eval/data/local/uv-cache and HF_HOME=eval/data/local/hf-cache.

GECToR grammar pass after s1-mini (needs model.onnx, tokenizer.json, labels.json and verb-form-vocab.txt from https://huggingface.co/deepquillapp/gector-grammar in eval/data/local/gector/, and eval/data/local/real-s1.jsonl): uv run eval/bench/gector.py stage1 && uv run eval/bench/gector.py stage2 && uv run eval/bench/gector.py report --recommend 0.8

AFM (Apple Foundation Models) cleanup with a chosen system prompt from eval/bench/prompts/ (macOS 26+, Apple Intelligence on): swiftc -O eval/bench/afm.swift -o <tmp>/afm-bench, then <tmp>/afm-bench --slug afm-short-v6 --prompt eval/bench/prompts/afm-short-v6.txt --user-format tags --guardrails permissive. Rows land in eval/results/bench/enhance/<slug>.jsonl. Set SOTTO_EVAL_LOCAL when eval/data/local lives in another checkout.
