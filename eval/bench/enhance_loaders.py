"""Model adapters for enhance.py: one loader per model kind."""

import re
import time

from enhance_models import (
    FLOWSCRIBE_PROMPT,
    MUMBLE_PROMPT,
    REWRITE_FIXED_LINE,
    S1_MINI_PROMPT,
    SPEAKOFLOW_PROMPT,
)


def load_llama(config: dict):
    from huggingface_hub import hf_hub_download
    from llama_cpp import Llama

    model_path = config.get("path") or hf_hub_download(
        repo_id=config["repo"], filename=config["file"]
    )
    model = Llama(model_path=model_path, n_ctx=8192, n_gpu_layers=-1, verbose=False)
    prompt_style = config.get("prompt_style", "speakoflow")

    def enhance(
        raw: str, instruction: str | None = None
    ) -> tuple[str, float, float | None]:
        input_tokens = len(model.tokenize(raw.encode("utf-8"), add_bos=False))
        started = time.perf_counter()
        first_token_at = None
        pieces = []

        if prompt_style == "s1_mini":
            if instruction is not None:
                inst_lower = instruction.lower()
                styling = "semi-formal"
                if "formal" in inst_lower and "semi" not in inst_lower:
                    styling = "formal"
                elif "semi-casual" in inst_lower:
                    styling = "semi-casual"
                elif "casual" in inst_lower:
                    styling = "casual"
                structure = (
                    "lists"
                    if ("list" in inst_lower or "bullet" in inst_lower)
                    else "prose"
                )
                context = "email" if "email" in inst_lower else "general"
                control_line = (
                    f"[Styling: {styling}] [Structure: {structure}] [Context: {context}]"
                )
                max_tokens = 3 * input_tokens + 64
            else:
                control_line = (
                    "[Styling: semi-formal] [Structure: prose] [Context: general]"
                )
                max_tokens = 2 * input_tokens + 32

            prompt = (
                f"<|im_start|>system\n{S1_MINI_PROMPT}<|im_end|>\n"
                f"<|im_start|>user\n{control_line}\n{raw}<|im_end|>\n"
                f"<|im_start|>assistant\n<think>\n\n</think>\n\n"
            )
            stream = model.create_completion(
                prompt=prompt,
                temperature=0.0,
                max_tokens=max_tokens,
                stream=True,
                stop=["<|im_end|>", "<|endoftext|>"],
            )
            for chunk in stream:
                piece = chunk["choices"][0].get("text") or ""
                if piece and first_token_at is None:
                    first_token_at = time.perf_counter()
                pieces.append(piece)

        elif prompt_style == "handy_editor":
            max_tokens = (
                3 * input_tokens + 64
                if instruction is not None
                else 2 * input_tokens + 32
            )
            prompt = (
                f"<|im_start|>system\n<|im_end|>\n"
                f"<|im_start|>user\n{raw}<|im_end|>\n"
                f"<|im_start|>assistant\n"
            )
            stream = model.create_completion(
                prompt=prompt,
                temperature=0.0,
                max_tokens=max_tokens,
                stream=True,
                stop=["<|im_end|>", "<|endoftext|>"],
            )
            for chunk in stream:
                piece = chunk["choices"][0].get("text") or ""
                if piece and first_token_at is None:
                    first_token_at = time.perf_counter()
                pieces.append(piece)

        elif prompt_style == "flowscribe":
            if instruction is not None:
                style = instruction
                max_tokens = 3 * input_tokens + 64
            else:
                style = "Auto"
                max_tokens = 2 * input_tokens + 32
            prompt = (
                f"<|im_start|>system\n{FLOWSCRIBE_PROMPT}<|im_end|>\n"
                f"<|im_start|>user\nTranscribe and format this with style: {style}\nInput: {raw}<|im_end|>\n"
                f"<|im_start|>assistant\n"
            )
            stream = model.create_completion(
                prompt=prompt,
                temperature=0.0,
                max_tokens=max_tokens,
                stream=True,
                stop=["<|im_end|>", "<|endoftext|>"],
            )
            for chunk in stream:
                piece = chunk["choices"][0].get("text") or ""
                if piece and first_token_at is None:
                    first_token_at = time.perf_counter()
                pieces.append(piece)

        else:
            if instruction is not None:
                sys_prompt = f"{instruction}\n{REWRITE_FIXED_LINE}"
                max_tokens = 3 * input_tokens + 64
            else:
                sys_prompt = SPEAKOFLOW_PROMPT
                max_tokens = 2 * input_tokens + 32
            stream = model.create_chat_completion(
                messages=[
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": raw},
                ],
                temperature=0.0,
                max_tokens=max_tokens,
                stream=True,
            )
            for chunk in stream:
                piece = chunk["choices"][0]["delta"].get("content") or ""
                if piece and first_token_at is None:
                    first_token_at = time.perf_counter()
                pieces.append(piece)

        ended = time.perf_counter()
        ttft = None if first_token_at is None else first_token_at - started
        return "".join(pieces), ended - started, ttft

    return enhance


def load_mlx(config: dict, system_prompt: str):
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler

    model, tokenizer = load(config["repo"])
    sampler = make_sampler(temp=0.0)

    def enhance(
        raw: str, instruction: str | None = None
    ) -> tuple[str, float, float | None]:
        input_tokens = len(tokenizer.encode(raw, add_special_tokens=False))
        if instruction is not None:
            sys_prompt = f"{instruction}\n{REWRITE_FIXED_LINE}"
            max_tokens = 3 * input_tokens + 64
        else:
            sys_prompt = system_prompt
            max_tokens = 2 * input_tokens + 32
        user_content = f"Transcript to clean: {raw}\nCleaned transcript:"
        messages = [
            {"role": "system", "content": sys_prompt},
            {"role": "user", "content": user_content},
        ]
        template_args = {"tokenize": False, "add_generation_prompt": True}
        if config.get("thinking") is False:
            template_args["enable_thinking"] = False
        if getattr(tokenizer, "chat_template", None):
            prompt = tokenizer.apply_chat_template(messages, **template_args)
        else:
            prompt = f"{sys_prompt}\n\nTranscript:\n{raw}\n\nCleaned transcript:"
        started = time.perf_counter()
        first_token_at = None
        pieces = []
        for response in stream_generate(
            model,
            tokenizer,
            prompt=prompt,
            max_tokens=max_tokens,
            sampler=sampler,
        ):
            piece = response.text
            if piece and first_token_at is None:
                first_token_at = time.perf_counter()
            pieces.append(piece)
        ended = time.perf_counter()
        ttft = None if first_token_at is None else first_token_at - started
        return "".join(pieces), ended - started, ttft

    return enhance


FILLER_RE = re.compile(
    r"(?i)(?<![\w'])\b(?:um+|uh+|er+|ah+|hmm+|you[ ,]+know)\b[,.]?\s*"
)


def remove_fillers(text: str) -> str:
    text = FILLER_RE.sub("", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\s+([,.;:!?])", r"\1", text)
    text = re.sub(r"[,;:]+\s*$", "", text)
    return text.strip()


def sentence_case(text: str) -> str:
    chars = list(text)
    uppercase_next = True
    for index, char in enumerate(chars):
        if uppercase_next and char.isalpha():
            chars[index] = char.upper()
            uppercase_next = False
        if char in ".!?\n":
            uppercase_next = True
    return "".join(chars)


def load_punctuation(config: dict):
    import torch
    from transformers import pipeline

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    pipe = pipeline(
        "token-classification",
        model=config["repo"],
        aggregation_strategy="none",
        device=device,
    )

    def restore_punctuation(text: str) -> str:
        words = re.sub(r"(?<!\d)[.,;:!?](?!\d)", "", text).split()
        if not words:
            return ""
        overlap = 5
        chunk_size = 230
        if len(words) <= chunk_size:
            overlap = 0
        batches = [
            words[i : i + chunk_size]
            for i in range(0, len(words), max(1, chunk_size - overlap))
        ]
        if len(batches) > 1 and len(batches[-1]) <= overlap:
            batches.pop()

        tagged_words = []
        for batch in batches:
            if batch == batches[-1]:
                overlap = 0
            text_chunk = " ".join(batch)
            result = pipe(text_chunk)
            char_index = 0
            result_index = 0
            for word in batch[: len(batch) - overlap]:
                char_index += len(word) + 1
                label = "0"
                while (
                    result_index < len(result)
                    and char_index > result[result_index]["end"]
                ):
                    label = result[result_index]["entity"]
                    result_index += 1
                tagged_words.append((word, label))

        result_str = ""
        for word, label in tagged_words:
            result_str += word
            if label == "0":
                result_str += " "
            elif label in ".,?-:":
                result_str += label + " "
        return result_str.strip()

    def enhance(
        raw: str, instruction: str | None = None
    ) -> tuple[str, float, None]:
        started = time.perf_counter()
        cleaned = remove_fillers(raw)
        text = "" if not cleaned else sentence_case(restore_punctuation(cleaned))
        return text, time.perf_counter() - started, None

    return enhance


def load_coedit(config: dict):
    import torch
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(config["repo"])
    model = AutoModelForSeq2SeqLM.from_pretrained(config["repo"]).to("mps")
    model.eval()

    def enhance(
        raw: str, instruction: str | None = None
    ) -> tuple[str, float, None]:
        if instruction is not None:
            prefixed = f"{instruction}: {raw}"
            max_tokens = 3 * len(tokenizer.encode(raw, add_special_tokens=False)) + 64
        else:
            prefixed = f"Fix grammatical errors in this sentence: {raw}"
            max_tokens = 2 * len(tokenizer.encode(raw, add_special_tokens=False)) + 32
        inputs = tokenizer(prefixed, return_tensors="pt").to("mps")
        started = time.perf_counter()
        with torch.inference_mode():
            output = model.generate(
                **inputs, do_sample=False, max_new_tokens=max_tokens
            )
        torch.mps.synchronize()
        elapsed = time.perf_counter() - started
        return tokenizer.decode(output[0], skip_special_tokens=True), elapsed, None

    return enhance


def load_causal_lm(config: dict):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    tokenizer = AutoTokenizer.from_pretrained(config["repo"])
    model = AutoModelForCausalLM.from_pretrained(
        config["repo"],
        torch_dtype=torch.bfloat16 if device == "mps" else torch.float32,
    ).to(device)
    model.eval()

    def enhance(
        raw: str, instruction: str | None = None
    ) -> tuple[str, float, float | None]:
        input_tokens = len(tokenizer.encode(raw, add_special_tokens=False))
        if instruction is not None:
            sys_prompt = f"{instruction}\n{REWRITE_FIXED_LINE}"
            max_tokens = 3 * input_tokens + 64
        else:
            sys_prompt = MUMBLE_PROMPT
            max_tokens = 2 * input_tokens + 32

        messages = [
            {"role": "system", "content": sys_prompt},
            {"role": "user", "content": raw},
        ]
        prompt = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
        inputs = tokenizer(prompt, return_tensors="pt").to(device)
        started = time.perf_counter()
        with torch.inference_mode():
            output = model.generate(
                **inputs, do_sample=False, max_new_tokens=max_tokens
            )
        if device == "mps":
            torch.mps.synchronize()
        elapsed = time.perf_counter() - started
        output_ids = output[0][inputs.input_ids.shape[1] :]
        text = tokenizer.decode(output_ids, skip_special_tokens=True)
        return text, elapsed, None

    return enhance


def load_adapter(config: dict, system_prompt: str):
    if config["kind"] == "llama":
        return load_llama(config)
    if config["kind"] == "mlx":
        return load_mlx(config, system_prompt)
    if config["kind"] == "punctuation":
        return load_punctuation(config)
    if config["kind"] == "coedit":
        return load_coedit(config)
    if config["kind"] == "causal_lm":
        return load_causal_lm(config)
    raise ValueError(f"unsupported adapter kind: {config['kind']}")
