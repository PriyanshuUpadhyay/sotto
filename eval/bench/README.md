# Sotto Model Benchmark
Benchmark candidate ASR and enhancement models against Sotto production data and baselines.

1. Export data: uv run eval/bench/export.py
2. Run model: generate eval/results/bench/asr/<slug>.jsonl or eval/results/bench/enhance/<slug>.jsonl
3. Score results: uv run eval/bench/score.py

Outputs land in eval/results/bench/report.md and eval/results/bench/report.json.

Sandbox cache env vars: UV_CACHE_DIR=eval/data/local/uv-cache and HF_HOME=eval/data/local/hf-cache.

GECToR grammar pass after s1-mini (needs model.onnx, tokenizer.json, labels.json and verb-form-vocab.txt from https://huggingface.co/deepquillapp/gector-grammar in eval/data/local/gector/, and eval/data/local/real-s1.jsonl): uv run eval/bench/gector.py stage1 && uv run eval/bench/gector.py stage2 && uv run eval/bench/gector.py report --recommend 0.8
