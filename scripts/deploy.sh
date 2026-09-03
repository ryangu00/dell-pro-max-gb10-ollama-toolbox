#!/usr/bin/env bash
# deploy.sh — one-command deploy of Ollama utility slots (vision fallback + lightweight extraction), with double-safety thinking verification
set -euo pipefail
say() { printf '\033[1m[deploy]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[deploy] FAIL:\033[0m %s\n' "$*" >&2; exit 1; }

command -v ollama >/dev/null || die "ollama is required"
curl -s -m 3 http://127.0.0.1:11434/api/tags >/dev/null || die "Ollama not serving on 11434. Run ollama serve first"

# ── 1. Pull the two utility slots ──
say "Pulling qwen3-vl:32b (vision fallback, ~20GB) + qwen3:4b (lightweight extraction)"
ollama pull qwen3-vl:32b
ollama pull qwen3:4b

# ── 2. Vision slot: double-safety thinking-off verification (pitfall #1: leave it on = 289s timeout) ──
say "Verifying vision slot with thinking disabled (should return in seconds, not hundreds of seconds)..."
python3 - <<'PY'
import base64, json, time, urllib.request
# 1x1 red PNG
png = base64.b64encode(bytes.fromhex(
 "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c626001000000ffff03000006000557bfabd40000000049454e44ae426082")).decode()
req = {"model": "qwen3-vl:32b", "stream": False, "think": False,
       "messages": [{"role": "user", "content": "What color is this? One word", "images": [png]}]}
t0 = time.time()
r = urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:11434/api/chat",
    json.dumps(req).encode(), {"Content-Type": "application/json"}), timeout=180)
d = json.load(r); dt = time.time() - t0
content = d.get("message", {}).get("content", "")
assert content.strip(), "FATAL: content is empty (thinking leaked / swallowed the body, pitfall #2)"
assert "<think>" not in content, "FATAL: chain-of-thought leaked into content (pitfall #2)"
print(f"  vision slot passed: {dt:.1f}s, answer={content.strip()[:20]!r}")
assert dt < 60, f"WARN boundary: {dt:.0f}s is slow — confirm thinking is actually disabled (pitfall #1)"
PY

# ── 3. Extraction slot verification ──
say "Verifying extraction slot..."
OUT=$(ollama run qwen3:4b --think=false "Answer in one word: what color is the sky usually" 2>/dev/null | tail -1)
[ -n "$OUT" ] || die "no output from qwen3:4b"
say "✅ Utility slots deployed (qwen3-vl:32b + qwen3:4b @ 11434)"
say "Reminder: also disable thinking explicitly at the call layer (double safety, pitfall #1); give each utility slot its own health probe (README design principles)"
