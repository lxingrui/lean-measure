#!/usr/bin/env bash
# 本机端到端模拟：在 Windows 的 Git Bash 里跑完整 run.sh 流程，验证上传与飞书通知。
#
# 为什么不用 WSL：本机 WSL 是 NAT 网络，实测直连 github 100% 超时
# （curl 返回 000、git 报 GnuTLS recv error）。Git Bash 走 Windows 网络栈，正常。
#
# 真实执行：run.sh 全部编排、sizeguard、post.mjs、build_report.mjs、notify.mjs、git 推送
# 桩替换：  lake / lean（用合成 refs.tsv 冒充抽取结果）
#
# 用法（在 Git Bash 里）:
#   bash test/run_local.sh ok            # 成功路径
#   bash test/run_local.sh fail          # 让目标失败，验证失败现场能否上传
#   LCM_TEST_TARGETS=mathlib,oai bash test/run_local.sh ok
#
# 需要的环境变量（由调用方传入）:
#   LCM_GH_TOKEN      推送到测试仓库
#   LCM_GH_REPO       默认 lxingrui/lean-measure-test
#   FEISHU_WEBHOOK / FEISHU_SECRET   可选
set -o pipefail

MODE="${1:-ok}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"          # 仓库根
ROOT=/tmp/lcm-win
APP="$ROOT/app"
BIN="$ROOT/bin"
WORK="$ROOT/work"

echo "════════════ 本机 E2E (mode=$MODE) ════════════"
echo "仓库根: $SRC"
echo "运行根: $ROOT"

command -v node >/dev/null || { echo "!! 需要 node"; exit 1; }
command -v git  >/dev/null || { echo "!! 需要 git"; exit 1; }
[ -n "${LCM_GH_TOKEN:-}" ] || { echo "!! 需要 LCM_GH_TOKEN"; exit 1; }
export LCM_GH_REPO="${LCM_GH_REPO:-lxingrui/lean-measure-test}"

rm -rf "$ROOT"; mkdir -p "$APP" "$BIN" "$WORK"

# ── 1. 复制被测代码 ────────────────────────────────────────────
for f in run.sh bootstrap.sh post.mjs build_report.mjs notify.mjs sizeguard.mjs subst_template.mjs diagnose_selfterm.sh measure.lean; do
  cp "$SRC/$f" "$APP/$f" || { echo "!! 缺文件 $f"; exit 1; }
done
echo "被测代码: $(ls "$APP" | tr '\n' ' ')"

# ── 2. 桩命令 ──────────────────────────────────────────────────
cat > "$BIN/lake" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  exe)    echo "[stub lake] $*"; exit 0 ;;
  update) echo "[stub lake update] 假装拉了 42 个依赖"; mkdir -p .lake/packages/mathlib; exit 0 ;;
  build)  echo "[stub lake build] $*"; mkdir -p .lake/build
          echo "Build completed successfully (9038 jobs)."; exit 0 ;;
  env)    shift
          if [ "$1" = "lean" ] && [ "$2" = "--version" ]; then
            echo "Lean (version 4.34.1, stub)"; exit 0
          fi
          FILE="$2"
          echo "[stub lean] 抽取 $FILE"
          if [ -n "$LCM_TEST_FAIL_LEAN" ]; then
            case "$FILE" in
              *oai*) echo "error: stub 故意失败，用于验证失败上传路径" >&2; exit 1 ;;
            esac
          fi
          OUT=$(grep -o '"[^"]*refs\.tsv"' "$FILE" | head -1 | tr -d '"')
          MOD=$(grep -o '`[A-Za-z0-9_.]*' "$FILE" | tail -1 | tr -d '`')
          [ -n "$OUT" ] || { echo "error: 桩找不到输出路径" >&2; exit 2; }
          mkdir -p "$(dirname "$OUT")"
          {
            i=1; while [ $i -le 60 ];  do printf '%s.prim%s\t§\t1\n' "$MOD" "$i"; i=$((i+1)); done
            i=1; while [ $i -le 400 ]; do printf '%s.d%s\t%s.prim%s\t%s\n' "$MOD" "$i" "$MOD" "$((i % 60 + 1))" "$((i % 7 + 1))"; i=$((i+1)); done
            i=1; while [ $i -le 200 ]; do printf '%s.e%s\t%s.d%s\t%s\n' "$MOD" "$i" "$MOD" "$((i % 400 + 1))" "$((i % 4 + 1))"; i=$((i+1)); done
          } > "$OUT"
          echo "[stub lean] 写出 $(wc -l < "$OUT") 行到 $OUT"
          exit 0 ;;
  *)      echo "[stub lake] 未处理: $*"; exit 0 ;;
esac
STUB

cat > "$BIN/lean" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "--version" ] && { echo "Lean (version 4.34.1, stub)"; exit 0; }
echo "[stub lean] $*"; exit 0
STUB

cat > "$BIN/apt-get" <<'STUB'
#!/usr/bin/env bash
echo "[stub apt-get] $* （跳过）"; exit 0
STUB

cat > "$BIN/free" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "-g" ] && printf '              total        used        free\nMem:            124          10         100\n'
STUB
chmod +x "$BIN"/*

export PATH="$BIN:$PATH"
echo "桩命令: $(command -v lake) | $(command -v lean) | node=$(node --version)"

# ── 3. 预置 mock 项目，跳过真实克隆/编译 ───────────────────────
for n in mathlib4 oai; do
  d="$WORK/$n"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && echo "$n" > README.md && git add -A && git commit -q -m init )
done
mkdir -p "$WORK/oai/lean/.lake/packages"
( cd "$WORK/oai/lean" && git init -q && git config user.email t@t && git config user.name t \
  && echo x > .keep && git add -A && git commit -q -m lean )
mkdir -p "$WORK/mathlib4/.lake/build/lib/lean"
echo "mock 项目就绪"

# ── 4. 运行 ────────────────────────────────────────────────────
export LCM_WORK="$WORK"
export LCM_KEEPALIVE=1              # 不要尝试关机
export LCM_DEADLINE_HOURS=0         # 不要看门狗
export LCM_TARGETS="${LCM_TEST_TARGETS:-mathlib}"
export LCM_OAI_SUBTREE="${LCM_TEST_SUBTREE:-OAI/Analysis/Crouzeix}"
export JOBS=2
[ "$MODE" = "fail" ] && export LCM_TEST_FAIL_LEAN=1

rm -rf /tmp/lean-measure.lock       # 清掉上一轮可能残留的实例锁
echo
echo "──── 开始 run.sh（目标: $LCM_TARGETS，模式: $MODE）────"
bash "$APP/run.sh" all 2>&1 | tee "$ROOT/run-output.log"
RC=${PIPESTATUS[0]}
echo
echo "──── run.sh 退出码: $RC ────"

# ── 5. 盘点 ────────────────────────────────────────────────────
echo
echo "===== 本地产物 ====="
find "$WORK/results" -type f 2>/dev/null | sort | while read -r f; do
  printf '  %-52s %10s B\n' "${f#$WORK/}" "$(wc -c < "$f")"
done
echo
echo "===== 日志 ====="
find "$WORK/logs" -type f 2>/dev/null | sort | while read -r f; do
  printf '  %-52s %10s B\n' "${f#$WORK/}" "$(wc -c < "$f")"
done
echo
echo "===== 诊断 ====="
find "$WORK/diag" -type f 2>/dev/null | sort | while read -r f; do
  printf '  %-52s %10s B\n' "${f#$WORK/}" "$(wc -c < "$f")"
done
[ -f "$WORK/diag/LAST_ERROR.txt" ] && { echo "--- LAST_ERROR.txt ---"; head -20 "$WORK/diag/LAST_ERROR.txt"; }
echo
echo "===== progress.json ====="
cat "$WORK/results/progress.json" 2>/dev/null; echo
exit $RC
