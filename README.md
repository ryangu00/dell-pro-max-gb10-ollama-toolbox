# Ollama Toolbox Models on Dell Pro Max with GB10 — Vision Fallback and Lightweight Extraction

> Beyond your main workhorse LLM, you always need a few "utility slot" models: vision fallback, web-page extraction, embedding.
> This book is the complete configuration of our Ollama utility slots, plus two thinking-related pitfalls.

## Update (2026-10): status of the vision slot

As of 2026-09-24 our own deployment no longer uses the `qwen3-vl:32b` Ollama model as a vision fallback. The slot was re-pointed to the fast-tier endpoint of the primary inference engine. When checked, the Ollama model was not loaded, had no referring configuration, and therefore occupied no memory. A configuration audit on 2026-10-02 confirmed the running vision path is configured through a separate vision setting of our agent framework; a leftover routing block that still named old local endpoints had no reader and was deleted. What was hosted here sat on a Dell Pro Max with GB10 node.

Whether the `qwen3-vl:32b` weights were later deleted from the node is not recorded; the decision was handed to a separate clean-up list whose outcome is not in the records checked.

The deploy script, the thinking-disabled latency assertion, the 289-second figure and the content-leak pitfall were not re-measured in this update.

No new facts were found for the `qwen3:4b` extraction slot or the embedding row.

## One-command deploy

`scripts/deploy.sh` — pulls the two utility models → verifies the vision slot with thinking disabled (second-level latency assertion + non-empty content + no `<think>` leakage) → verifies the extraction slot.

## Utility slot roster

| Model | Purpose | Key configuration |
|---|---|---|
| `qwen3-vl:32b` | Vision fallback slot. Status as of 2026-09-24: nothing in our own deployment points at it any more (see Update 2026-10); the recipe and pitfall #1 still apply if you wire it in | **thinking must be disabled at both layers** (see pitfall #1) |
| `qwen3:4b` | Web-page body extraction / lightweight structuring (fast, cheap, good enough) | No special config; give it a generous timeout (long pages) |
| Self-trained embedding | Knowledge-base retrieval (see the embedding-training book in this series) | `num_batch 16384` |

## Pitfall #1: leave thinking on, and vision requests time out until you question your sanity

`qwen3-vl:32b` ships with thinking enabled by default. Point a 32B model at an image and let it think, and **a single request can drag out to 289 seconds measured** — everything upstream times out, and it looks like "vision fallback is completely dead" while the service itself is healthy and the logs show no errors.
**The fix is a double safety** (a single switch gets missed on some call paths):
1. Model level: disable thinking in the Modelfile / request parameters;
2. Call level: set `chat_template_kwargs: {"enable_thinking": false}` explicitly in the request body (or the equivalent key for that model family).
With both layers set, every call path stays covered. Verify: reasoning tokens in `usage` ≈ 0 and response time drops from hundreds of seconds to seconds.

> **Image-resolution timing tip (different model)**  
> This is a single observation from a different vision model (Qwen3.8-family via vLLM), not from `qwen3-vl:32b`. While generating text descriptions for an archive of 1,467 images on a Dell Pro Max with GB10 node: sending original-resolution images took 60.1 s per image; downscaling the long edge to 1,024 px before sending took 3.2 s per image (about 18x faster; 60.1 / 3.2 = 18.8). Reported as "no loss of quality" for transcribing text and recognising charts, but no quality metric was recorded. Observed once. Not recorded: original image resolution, how many images were timed in each arm, the prefill versus decode split, and whether the two arms ran under identical load.

## Pitfall #2: thinking leaks into content (older Ollama compatibility layer)

Some versions of Ollama's OpenAI compatibility layer have a "content fallback" behavior: when it can't parse a body out of the upstream response, it **promotes the raw chain-of-thought to content and returns it** — the "answer" your downstream receives is actually the model's rambling. We hit this in a real pipeline (the version at the time had it; later versions fixed it; trigger condition = thinking on + empty body).
**Defense (a version-independent habit)**: when consuming output from a thinking model, always check whether content starts with `<think>` / a block of reasoning; and disable thinking on all utility-slot models to kill this class of problem at the source.

## Utility slot design principles (our practice)

- **Disable thinking on every utility-slot model**: utility slots need fast, stable, format-predictable output; the quality gain from thinking isn't worth its latency on tasks like "extract the body" or "describe the image".
- Deploy utility slots and the primary model on **separate ports**, so primary upgrades/restarts never take the utility slots down.
- Give each utility slot its own **independent health probe** (fixed input, assert on output shape) — don't piggyback on the primary pipeline's health check.

---
*RyanAI Lab · All numbers measured on our resident environment. Updated 2026-10. Issues welcome.*
