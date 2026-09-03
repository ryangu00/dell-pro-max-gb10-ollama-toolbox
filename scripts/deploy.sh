#!/usr/bin/env bash
# deploy.sh — Ollama 工具位一键部署(视觉兜底+轻量抽取),含 thinking 双保险验证
set -euo pipefail
say() { printf '\033[1m[deploy]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[deploy] FAIL:\033[0m %s\n' "$*" >&2; exit 1; }

command -v ollama >/dev/null || die "需要 ollama"
curl -s -m 3 http://127.0.0.1:11434/api/tags >/dev/null || die "Ollama 服务未在 11434。先 ollama serve"

# ── 1. 拉取两个工具位 ──
say "拉取 qwen3-vl:32b(视觉兜底,~20GB)+ qwen3:4b(轻量抽取)"
ollama pull qwen3-vl:32b
ollama pull qwen3:4b

# ── 2. 视觉位:thinking 双保险验证(坑 #1:不关=289 秒超时) ──
say "视觉位关思考验证(应秒级返回而非百秒级)..."
python3 - <<'PY'
import base64, json, time, urllib.request
# 1x1 红色 PNG
png = base64.b64encode(bytes.fromhex(
 "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c626001000000ffff03000006000557bfabd40000000049454e44ae426082")).decode()
req = {"model": "qwen3-vl:32b", "stream": False, "think": False,
       "messages": [{"role": "user", "content": "这是什么颜色?一个词", "images": [png]}]}
t0 = time.time()
r = urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:11434/api/chat",
    json.dumps(req).encode(), {"Content-Type": "application/json"}), timeout=180)
d = json.load(r); dt = time.time() - t0
content = d.get("message", {}).get("content", "")
assert content.strip(), "FATAL: content 为空(thinking 泄漏/吃空正文,坑 #2)"
assert "<think>" not in content, "FATAL: 思维链泄漏进 content(坑 #2)"
print(f"  视觉位通过: {dt:.1f}s, 答={content.strip()[:20]!r}")
assert dt < 60, f"WARN 边界: {dt:.0f}s 偏慢——确认 think 关闭是否生效(坑 #1)"
PY

# ── 3. 抽取位验证 ──
say "抽取位验证..."
OUT=$(ollama run qwen3:4b --think=false "用一个词回答:天空通常是什么颜色" 2>/dev/null | tail -1)
[ -n "$OUT" ] || die "qwen3:4b 无输出"
say "✅ 工具位部署完成(qwen3-vl:32b + qwen3:4b @ 11434)"
say "提醒:调用层也显式关思考(双保险,坑 #1);工具位配独立健康探针(README 设计原则)"
