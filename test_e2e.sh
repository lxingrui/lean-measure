#!/usr/bin/env bash
# 本地端到端模拟：用桩命令替换 Lean 工具链，跑完整 run.sh 流程，
# 验证【上传】与【飞书通知】两条链路。
#
# 真实执行的部分：run.sh 的全部编排逻辑、sizeguard、post.mjs、
#                 build_report.mjs、notify.mjs、git 推送
# 被桩替换的部分：lake / lean（用预置的 refs.tsv 冒充抽取结果）
#
# 用法: bash test_e2e.sh <mode>
#   mode=ok    全流程成功
#   mode=fail  让 oai 的 lean 失败，验证失败现场能否推上来
set -o pipefail

MODE="${1:-ok}"
# APP = 被测代码目录（预置好，不能删）  ROOT = 本次测试的运行目录
APP="${LCM_TEST_APP:-/tmp/lcm-app}"
ROOT=/tmp/lcm-test
STUB="$ROOT/stub"
MOCK="$ROOT/mock"
WORK="$ROOT/work"
REPO="$ROOT/repo"

echo "════════ E2E 测试 (mode=$MODE) ════════"
echo "被测代码: $APP"
[ -f "$APP/run.sh" ] || { echo "!! 找不到 $APP/run.sh（先执行 LCM_TEST_APP 指向代码目录）"; exit 1; }
rm -rf "$ROOT"; mkdir -p "$STUB" "$MOCK" "$WORK"
# 清掉上一轮可能残留的实例锁（测试里允许这样做；生产环境锁是保护机制）
rm -rf /tmp/lean-measure.lock
# run.sh 在其所在目录找 post.mjs / sizeguard.mjs 等，所以直接用 APP
RUNSH="$APP/run.sh"

# ── 1. 桩命令 lake ──────────────────────────────────────────────
cat > "$STUB/lake" <<'STUBEOF'
#!/usr/bin/env bash
# 只实现 run.sh 会用到的几种调用
case "$1" in
  exe)   # lake exe cache get → 什么都不做
         echo "[stub lake] $*"
         exit 0 ;;
  update) echo "[stub lake update] 假装拉了 42 个依赖"
          mkdir -p .lake/packages/mathlib
          exit 0 ;;
  build) echo "[stub lake build] $*"
          mkdir -p .lake/build
          echo "Build completed successfully (9038 jobs)."
          exit 0 ;;
  env)   shift
         # lake env lean --version
         if [ "$1" = "lean" ] && [ "$2" = "--version" ]; then
           echo "Lean (version 4.34.1, stub)"
           exit 0
         fi
         # lake env lean <file> —— 冒充抽取
         FILE="$2"
         echo "[stub lean] 正在抽取 $FILE"
         echo "[stub lean] 遍历环境中…"
         # 失败模式：oai 的 refs 刻意报错
         if [ -n "$LCM_TEST_FAIL_LEAN" ]; then
           case "$FILE" in
             *oai*) echo "error: stub 故意失败，用于验证失败上传路径" >&2
                    exit 1 ;;
           esac
         fi
         # 从 MeasureRefs.lean 里解析出输出路径与根模块
         OUT=$(grep -o '"[^"]*refs\.tsv"' "$FILE" | head -1 | tr -d '"')
         MOD=$(grep -o '`[A-Za-z0-9_.]*' "$FILE" | tail -1 | tr -d '`')
         [ -n "$OUT" ] || { echo "error: 桩没找到输出路径" >&2; exit 2; }
         mkdir -p "$(dirname "$OUT")"
         # 生成有层次的合成图：primitive + 两层引用
         {
           for i in $(seq 1 60); do echo "${MOD}.prim$i	§	1"; done
           for i in $(seq 1 400); do echo "${MOD}.d$i	${MOD}.prim$((i % 60 + 1))	$((i % 7 + 1))"; done
           for i in $(seq 1 200); do echo "${MOD}.e$i	${MOD}.d$((i % 400 + 1))	$((i % 4 + 1))"; done
         } > "$OUT"
         echo "[stub lean] 写出 $(wc -l < "$OUT") 行到 $OUT"
         exit 0 ;;
  *) echo "[stub lake] 未处理: $*"; exit 0 ;;
esac
STUBEOF
chmod +x "$STUB/lake"
export PATH="$STUB:$PATH"
echo "桩 lake: $(command -v lake)"

# 桩 lean：让 do_toolchain 走"已存在"分支，从而跳过 apt/elan 安装
# （本机非 root 装不了包，但这步在 pod 里本来是好的）
cat > "$STUB/lean" <<'LEANEOF'
#!/usr/bin/env bash
[ "$1" = "--version" ] && echo "Lean (version 4.34.1, stub)" && exit 0
echo "[stub lean] $*"
exit 0
LEANEOF
chmod +x "$STUB/lean"
echo "桩 lean: $(command -v lean)"

# ── 2. 预置 mock 仓库，让 deps 阶段跳过克隆 ─────────────────────
for name in mathlib4 oai; do
  d="$MOCK/$name"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && echo "$name" > README.md && git add -A && git commit -q -m init )
done
mkdir -p "$MOCK/oai/lean" "$MOCK/oai/lean/.lake/packages"
( cd "$MOCK/oai/lean" && git add -A 2>/dev/null; git commit -q -m lean 2>/dev/null || true )
# 预置 build 目录，让 du 有东西可量
mkdir -p "$MOCK/mathlib4/.lake/build/lib/lean" "$MOCK/oai/lean/.lake/build/lib/lean"
dd if=/dev/zero of="$MOCK/mathlib4/.lake/build/fake.olean" bs=1M count=5 2>/dev/null

# ── 3. 预置测试仓库的 main 分支，避免任何 clone ─────────────────
rm -rf "$REPO"; mkdir -p "$REPO"
( cd "$REPO" && git init -q -b main \
  && git config user.email t@t && git config user.name t \
  && echo "test repo" > README.md && git add -A && git commit -q -m "初始提交" )
echo "测试仓库: $REPO"

# ── 4. 跑 run.sh ────────────────────────────────────────────────
export LCM_WORK="$WORK"
export LCM_GH_REPO="${LCM_GH_REPO:-lxingrui/lean-measure-test}"
export LCM_REPO_URL="$REPO"
export LCM_KEEPALIVE=1              # 不要尝试关机
export LCM_DEADLINE_HOURS=0         # 不要看门狗
export LCM_TARGETS="${LCM_TARGETS:-mathlib,oai}"
export JOBS="${JOBS:-2}"
[ "$MODE" = "fail" ] && export LCM_TEST_FAIL_LEAN=1

echo "GH_TOKEN 是否已注入: $([ -n "$GH_TOKEN" ] && echo 是 || echo 否)"
echo "FEISHU_WEBHOOK 是否已注入: $([ -n "$FEISHU_WEBHOOK" ] && echo 是 || echo 否)"
echo

bash "$RUNSH" all 2>&1 | tee "$ROOT/run-output.log"
echo
echo "════════ run.sh 退出码: ${PIPESTATUS[0]} ════════"

# ── 5. 结果盘点 ────────────────────────────────────────────────
echo
echo "===== 本地产物 ====="
find "$WORK/results" -type f 2>/dev/null | sort | while read -r f; do
  printf '  %-60s %8s B\n' "${f#$WORK/}" "$(stat -c%s "$f")"
done
echo
echo "===== 日志 ====="
find "$WORK/logs" -type f 2>/dev/null | sort | while read -r f; do
  printf '  %-60s %8s B\n' "${f#$WORK/}" "$(stat -c%s "$f")"
done
echo
echo "===== 诊断（失败模式才有）====="
find "$WORK/diag" -type f 2>/dev/null | sort | while read -r f; do
  printf '  %-60s %8s B\n' "${f#$WORK/}" "$(stat -c%s "$f")"
done
[ -f "$WORK/diag/LAST_ERROR.txt" ] && { echo "--- LAST_ERROR.txt ---"; head -25 "$WORK/diag/LAST_ERROR.txt"; }
echo
echo "===== progress.json ====="
cat "$WORK/results/progress.json" 2>/dev/null; echo
