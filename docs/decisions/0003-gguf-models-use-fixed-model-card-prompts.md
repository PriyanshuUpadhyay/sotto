---
status: accepted
date: 2026-09-16
deciders: [PriyanshuUpadhyay]
related: [0001, 0002]
---
# 0003. GGUF models use their fixed model-card prompts, not Sotto's custom prompt

In the context of the GGUF enhancement provider, facing model cards that require an exact
system prompt and input shape (s1-mini needs its control line and an empty think block, and a
missing trailing newline already made it return empty output), we chose to hard-code each model's
prompt in the provider and ignore Sotto's system prompt and context for these models, and
neglected passing the user's custom prompt through, to achieve the quality measured in the bench,
accepting that the Enhancement prompt settings and captured context apply only to AFM.
