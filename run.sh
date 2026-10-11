#!/usr/bin/env bash
# 在 RunPod CPU Pod 上测量 Lean 库的「压缩签名」（按 arXiv:2603.20396 §3 的口径）。
#
# 设计目标：
#   · 开机自动跑完 mathlib + OAI 子树，不需要任何环境变量（凭证除外）
#   · 跑完（或卡死到时限）自动关机，不空转计费
#   · 结果推回 GitHub，产物按运行实例分支隔离
#   · 失败要响亮：每个关键步骤都检查退出码
#
# 必须提供的环境变量（只有凭证）：
#   GITHUB_TOKEN      或 LCM_GH_TOKEN / GH_TOKEN   推结果用
#   FEISHU_WEBHOOK    可选，飞书机器人
#   FEISHU_SECRET     可选，飞书签名密钥
#
# 可覆盖的（都有合理默认值）：
#   LCM_TARGETS          默认 "mathlib,oai"
#   LCM_OAI_SUBTREE      默认 "OAI/Analysis/Crouzeix"
#   LCM_OAI_FULL=1       编译整个 OAI（需 ~110G，默认关）
#   LCM_WORK             默认 /work（容器盘，本地 NVMe）
#   JOBS                 默认按 vCPU 与内存自动定
#   LCM_DEADLINE_HOURS   默认 24（看门狗）
#   LCM_SELFTERM=0       关闭自动关机
#   LCM_RESULT_BRANCH    默认 results-<主机名>-<时间戳>
#   LCM_PUSH_REFS=1      连 refs.tsv 中间产物一起推（默认关）

set -o pipefail

PHASE="${1:-all}"
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] 失败: $*" >&2; exit 1; }

# ════════════════════════════════════════════════════════════════
# 配置
# ════════════════════════════════════════════════════════════════
GH_TOKEN="${LCM_GH_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
FEISHU_WEBHOOK="${LCM_FEISHU_WEBHOOK:-${FEISHU_WEBHOOK:-}}"
FEISHU_SECRET="${LCM_FEISHU_SECRET:-${FEISHU_SECRET:-}}"
GH_REPO="${LCM_GH_REPO:-lxingrui/lean-measure}"
OAI_SUBTREE="${LCM_OAI_SUBTREE:-OAI/Analysis/Crouzeix}"
OAI_FULL="${LCM_OAI_FULL:-0}"

_raw="${LCM_TARGETS:-${TARGETS:-mathlib,oai}}"
TARGETS="$(echo "$_raw" | tr ',' ' ' | tr -s ' ')"
TARGET="${TARGETS%% *}"                       # 兼容单数用法

# 工作目录固定在容器盘（本地 NVMe）。RunPod 的网络卷是网络存储，Lean 编译
# 极度 I/O 密集，放上面会明显变慢；结果都推 GitHub，不需要持久化。
WORK="${LCM_WORK:-/work}"
mkdir -p "$WORK" || die "无法创建工作目录 $WORK"
RES="$WORK/results"
LOGS="$WORK/logs"
mkdir -p "$RES" "$LOGS"

VCPU="$(nproc)"
MEM_GB="$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')"; [ -z "$MEM_GB" ] && MEM_GB=16
if [ -z "${JOBS:-}" ]; then
  JOBS_CPU=$(( VCPU > 8 ? 8 : (VCPU > 2 ? VCPU - 1 : 1) ))
  JOBS_MEM=$(( (MEM_GB - 8) / 12 ))       # 单个 Lean 进程峰值按 12G 留
  [ "$JOBS_MEM" -lt 1 ] && JOBS_MEM=1
  JOBS=$(( JOBS_CPU < JOBS_MEM ? JOBS_CPU : JOBS_MEM )); JOBS_AUTO=1
fi
JOBS="${JOBS:-2}"

# 需要多少工作空间
WORK_NEED_GB=60
[ "$OAI_FULL" = "1" ] && WORK_NEED_GB=110

# 看门狗
DEADLINE_H="${LCM_DEADLINE_HOURS:-24}"

export ELAN_HOME="${ELAN_HOME:-/root/.elan}"
export PATH="$ELAN_HOME/bin:$PATH"

START_EPOCH=$(date +%s)
elapsed() { echo $(( $(date +%s) - START_EPOCH )); }
fmt_dur() { local s=$1; printf '%dm%02ds' $((s/60)) $((s%60)); }

# 主机标识（结果/诊断分支名都用它）
HOST_TAG="$(hostname 2>/dev/null | tr -cd 'a-zA-Z0-9' | head -c 12)"; [ -z "$HOST_TAG" ] && HOST_TAG=pod

# ════════════════════════════════════════════════════════════════
# 通知
# ════════════════════════════════════════════════════════════════
notify() {
  [ -n "$FEISHU_WEBHOOK" ] || return 0
  command -v node >/dev/null 2>&1 || return 0
  node "$APP/notify.mjs" "$1" "$2" "${3:-}" "${4:-}" 2>&1 | tail -2 || true
}

# ════════════════════════════════════════════════════════════════
# 实例锁：同一台机器只允许一个 run.sh
# ════════════════════════════════════════════════════════════════
LOCK_DIR="/tmp/lean-measure.lock"
acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"; date -u +"%Y-%m-%dT%H:%M:%SZ" > "$LOCK_DIR/started"
    return 0
  fi
  local other; other="$(cat "$LOCK_DIR/pid" 2>/dev/null || echo '')"
  if [ -n "$other" ] && [ "$other" != "$$" ] && kill -0 "$other" 2>/dev/null; then
    die "已有实例在运行（pid=$other，启动于 $(cat "$LOCK_DIR/started" 2>/dev/null || echo '?')）。
    同一台机器跑两个会互相覆盖产物、并冲突推送。
    强行接管：kill $other && rm -rf $LOCK_DIR"
  fi
  say "接管陈旧实例锁（pid=$other 已不存在）"
  rm -rf "$LOCK_DIR"; mkdir "$LOCK_DIR" || die "无法获取实例锁"
  echo "$$" > "$LOCK_DIR/pid"; date -u +"%Y-%m-%dT%H:%M:%SZ" > "$LOCK_DIR/started"
}
release_lock() { [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK_DIR" || true; }

# ════════════════════════════════════════════════════════════════
# 自动关机
#
# ⚠️ 两次踩坑的结论：
#   1. kill 1 只是让容器主进程退出，RunPod 会把容器【再拉起来】——
#      造成无限循环重启（实测每 15 秒一轮），把 SSH 都挤掉，根本进不去。
#   2. RunPod 的预期模型是主进程【不要退出】（官方文档建议用 sleep infinity
#      保持容器存活）。所以 kill 1 属于未定义行为，不能依赖。
#
# 因此本版规则：
#   · 首选：调 RunPod API DELETE /v1/pods/<id> —— 唯一可靠的关机方式
#   · 没有 API key：【什么也不做】，保留容器，让 SSH 还能进去
#     并且明确告诉用户"需要手动删"
#   · 绝不 kill 1
#
#   RUNPOD_POD_ID   由 RunPod 运行时自动注入
#   RUNPOD_API_KEY  RunPod → Settings → API Keys
#   LCM_KEEPALIVE=1 明确要求保留 Pod（调试）
# ════════════════════════════════════════════════════════════════
selfterm() {
  if [ "${LCM_KEEPALIVE:-0}" = "1" ]; then
    say "LCM_KEEPALIVE=1：保留 Pod（SSH 可用，记得手动删）"; return 0
  fi
  local pid="${RUNPOD_POD_ID:-}" key="${RUNPOD_API_KEY:-}"

  if [ -z "$key" ]; then
    say "────────────────────────────────────────────────────────"
    say "⚠️ 未提供 RUNPOD_API_KEY，无法自动关机。"
    say "   本版【不会】用 kill 1 兜底 —— 那会导致无限循环重启，"
    say "   把 SSH 都挤掉，反而更糟。"
    say "   Pod 保持运行，请手动删除；或加环境变量 RUNPOD_API_KEY"
    say "   （RunPod → Settings → API Keys）下次即可自动关机。"
    say "────────────────────────────────────────────────────────"
    notify warn "lean-measure 需要手动删 Pod" \
      "原因: 未配置 RUNPOD_API_KEY，无法自动关机
Pod 仍在运行并计费。请到控制台删除，或补上 RUNPOD_API_KEY。"
    return 0
  fi

  if [ -z "$pid" ]; then
    say "⚠️ RUNPOD_POD_ID 为空（非 RunPod 环境？），跳过删除"
    return 0
  fi

  # 重试若干次：网络抖动很常见，删不掉就会一直计费
  local i code
  for i in 1 2 3 4 5; do
    say "自动关机：DELETE https://rest.runpod.io/v1/pods/$pid （第 $i 次）"
    code=$(curl -sS -o /tmp/rp_del.txt -w '%{http_code}' --max-time 30 \
      -X DELETE "https://rest.runpod.io/v1/pods/${pid}" \
      -H "Authorization: Bearer ${key}" 2>/dev/null || echo 000)
    say "  HTTP $code  $(head -c 300 /tmp/rp_del.txt 2>/dev/null)"
    case "$code" in
      200|204) say "✅ Pod 删除请求已接受，容器即将消失"; sleep 30; return 0 ;;
      401) say "❌ 401 Unauthorized —— RUNPOD_API_KEY 无效。保留 Pod，请手动删。"; return 0 ;;
      400|404) say "❌ $code —— RUNPOD_POD_ID 不被 RunPod 接受（'$pid'）。保留 Pod，请手动删。"; return 0 ;;
    esac
    sleep 10
  done
  say "⚠️ 5 次都失败。保留 Pod（不会 kill 1），请手动删。"
  notify fail "自动关机失败" "DELETE /v1/pods/$pid 连续 5 次失败，Pod 仍在计费，请手动删除。"
}

# ════════════════════════════════════════════════════════════════
# 阶段执行器：记录耗时、失败时发通知、成功后写进度
# ════════════════════════════════════════════════════════════════
mark_progress() {
  printf '{"stage":"%s","state":"%s","at":"%s","elapsed_seconds":%s}\n' \
    "$1" "$2" "$(ts)" "$(elapsed)" > "$RES/progress.json"
  do_upload >/dev/null 2>&1 || true
}

run_stage() {
  local name="$1"; shift
  local t0; t0=$(date +%s)
  local log="$LOGS/$name.log"
  say "==> $name"

  # ⚠️ 不要写成 `if ! "$@" 2>&1 | tee ...` —— 那样测的是 tee 的退出码，
  #    tee 永远成功，于是失败永远检不出来（真机踩过：measure 失败却报"完成"）。
  #    必须先捕获命令自身的退出码，再 tee。
  local rc=0
  ( "$@" ) > >(tee -a "$log") 2>&1 || rc=$?

  if [ "$rc" -ne 0 ]; then
    local d=$(( $(date +%s) - t0 ))
    say "──── $name 失败（退出码 $rc），日志尾部 ────"
    tail -50 "$log" 2>/dev/null | sed 's/^/  | /'
    say "────────────────────────────────────────────"
    write_error_report "$name" "$rc"
    mark_progress "$name" failed
    notify fail "lean-measure 失败: $name" \
      "退出码: $rc
耗时: $(fmt_dur $d)（累计 $(fmt_dur "$(elapsed)")）
目标: $TARGETS${OAI_SUBTREE:+  subtree=$OAI_SUBTREE}

日志尾部（完整日志见仓库 logs/$name.log）:
$(tail -40 "$log" 2>/dev/null || echo '(无)')"
    die "$name 阶段失败（退出码 $rc），详见 $log"
  fi

  local d=$(( $(date +%s) - t0 ))
  notify ok "阶段完成: $name" \
    "耗时: $(fmt_dur $d)（累计 $(fmt_dur "$(elapsed)")）
目标: $TARGETS"
  mark_progress "$name" done
}

# 把失败现场单独写一份，并立刻单独推一次日志 ——
# 即使后面的上传逻辑有问题，诊断信息也已经在仓库里了
write_error_report() {
  local name="$1" rc="$2"
  mkdir -p "$WORK/diag"
  {
    echo "阶段: $name"
    echo "退出码: $rc"
    echo "时间: $(ts)"
    echo "目标: $TARGETS"
    echo "主机: $(hostname)  vCPU=$(nproc)  MEM=${MEM_GB}G"
    echo "工作目录: $WORK"
    echo
    echo "===== $name 日志尾部 80 行 ====="
    tail -80 "$LOGS/$name.log" 2>/dev/null || echo '(无日志)'
  } > "$WORK/diag/LAST_ERROR.txt" 2>/dev/null || true
  push_diag "$name" || true
}

# 只推日志（不依赖结果目录/体积守卫），保证诊断信息能出来
push_diag() {
  local name="$1"
  [ -n "$GH_TOKEN" ] || { say "（无 GH_TOKEN，跳过诊断上传）"; return 1; }
  local D="/tmp/diagpush"
  rm -rf "$D"; mkdir -p "$D/logs" "$D/diag"
  cp -r "$LOGS"/. "$D/logs/" 2>/dev/null || true
  cp -r "$WORK/diag"/. "$D/diag/" 2>/dev/null || true
  cd "$D" || return 1
  git init -q
  git config user.email "bot@localhost"; git config user.name "lean-measure bot"
  git checkout -q -b "diag-${HOST_TAG}-$(date -u +%m%d-%H%M%S)"
  git add -f logs diag 2>/dev/null || true
  git commit -q -m "诊断: $name 失败 @ $(ts)" 2>/dev/null || return 1
  git push -q --force "https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git" HEAD 2>&1 | tail -3 || return 1
  say "诊断日志已推送（分支 diag-*）"
}

# ════════════════════════════════════════════════════════════════
# 阶段 0：工具链
# ════════════════════════════════════════════════════════════════
do_toolchain() {
  if command -v lean >/dev/null 2>&1; then
    say "Lean 已存在: $(lean --version)"
  else
    say "安装基础包"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || die "apt-get update 失败"
    apt-get install -y -qq --no-install-recommends curl git ca-certificates build-essential libgmp-dev || die "apt 安装失败"
    say "安装 elan + leanprover/lean4:v4.34.1（约 1.5–2 GB）"
    curl -fsSL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -o /tmp/elan.sh || die "elan 下载失败"
    sh /tmp/elan.sh -y --default-toolchain leanprover/lean4:v4.34.1 || die "elan 安装失败"
  fi
  command -v node >/dev/null 2>&1 || {
    say "安装 nodejs"; export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq --no-install-recommends nodejs || say "⚠️ nodejs 安装失败"
  }
  command -v node >/dev/null 2>&1 && say "node: $(node --version)" || say "⚠️ 没有 node，后处理会失败"
  df -BG "$WORK" | awk 'NR==2{print "工作盘可用: "$4}'
}

# ════════════════════════════════════════════════════════════════
# 阶段 1：依赖
# ════════════════════════════════════════════════════════════════
do_deps() {
  local t="$1"
  if [ "$t" = "mathlib" ]; then
    if [ ! -d "$WORK/mathlib4/.git" ]; then
      say "[$t] 克隆 mathlib4"
      git clone --filter=blob:none https://github.com/leanprover-community/mathlib4.git "$WORK/mathlib4" || die "[$t] 克隆失败"
    fi
    say "[$t] commit: $(git -C "$WORK/mathlib4" rev-parse HEAD)"
  else
    if [ ! -d "$WORK/oai/.git" ]; then
      say "[$t] 克隆 OpenAI 数学仓库（约 1.5 GB）"
      git clone --filter=blob:none https://github.com/openai/math.git "$WORK/oai" || die "[$t] 克隆失败"
    fi
    say "[$t] commit: $(git -C "$WORK/oai" rev-parse HEAD)"
    cd "$WORK/oai/lean" || die "[$t] 没有 $WORK/oai/lean"
    say "[$t] lake update（42 个依赖 + 自动打 24 个兼容补丁）"
    lake update || die "[$t] lake update 失败"
  fi
}

# ════════════════════════════════════════════════════════════════
# 阶段 2：编译
#   注意：lake build 【没有】 -j 选项（v4.34.1 实测 unknown short option）
#   并发靠环境变量 LEAN_NUM_THREADS
# ════════════════════════════════════════════════════════════════
do_build() {
  local t="$1"
  if [ "$t" = "mathlib" ]; then
    cd "$WORK/mathlib4" || die "[$t] 目录不存在"
    say "[$t] 拉预编译缓存（失败则自行编译，1–3 小时）"
    lake exe cache get || say "[$t] ⚠️ 缓存失败，将自行编译"
    say "[$t] 编译 Mathlib（LEAN_NUM_THREADS=$JOBS）"
    LEAN_NUM_THREADS="$JOBS" lake build Mathlib || die "[$t] 编译失败"
  else
    cd "$WORK/oai/lean" || die "[$t] 目录不存在"
    say "[$t] 确保 pinned mathlib 缓存"
    ( cd .lake/packages/mathlib && lake exe cache get ) || say "[$t] ⚠️ mathlib 缓存失败"
    local tgt
    if [ "$OAI_FULL" = "1" ]; then tgt="OAI"
    else tgt="$(echo "$OAI_SUBTREE" | tr '/' '.')"; fi
    say "[$t] 编译 $tgt（LEAN_NUM_THREADS=$JOBS）"
    LEAN_NUM_THREADS="$JOBS" lake build "$tgt" || die "[$t] 编译失败"
  fi
  say "[$t] 产物: $(du -sh "$PWD/.lake/build" 2>/dev/null | cut -f1)"
}

# ════════════════════════════════════════════════════════════════
# 阶段 3：测量
# ════════════════════════════════════════════════════════════════
do_measure() {
  local t="$1"
  local OUTD="$RES/$t"; mkdir -p "$OUTD"
  local TSV="$OUTD/refs.tsv"
  local PROJ ROOT_MODULE
  if [ "$t" = "mathlib" ]; then
    PROJ="$WORK/mathlib4"; ROOT_MODULE="Mathlib"
  else
    PROJ="$WORK/oai/lean"; ROOT_MODULE="$(echo "$OAI_SUBTREE" | tr '/' '.')"
    [ "$OAI_FULL" = "1" ] && ROOT_MODULE="OAI"
  fi

  say "[$t] 生成 MeasureRefs.lean（根模块 $ROOT_MODULE）"
  node "$APP/subst_template.mjs" "$APP/measure.lean" "$PROJ/MeasureRefs.lean" "$ROOT_MODULE" "$TSV" \
    || die "[$t] 模板替换失败"

  # 显式落一次依赖，确保 .lake/packages 齐全（否则 lake env lean 会加载失败）
  say "[$t] lake update（确保依赖齐全）"
  ( cd "$PROJ" && lake update ) > "$LOGS/$t-lakeupdate.log" 2>&1 \
    || say "[$t] ⚠️ lake update 返回非零，继续（详情见 $LOGS/$t-lakeupdate.log）"

  say "[$t] 确认根模块可加载: $ROOT_MODULE"
  ( cd "$PROJ" && lake env lean --version ) >/dev/null 2>&1 \
    || die "[$t] lake env 不可用（依赖没装好？）"

  say "[$t] elaboration 抽取（单线程遍历，可能几十分钟）"
  cd "$PROJ" || die "[$t] 目录不存在"
  # 把完整输出都打到阶段日志里：Lean 的报错全部在 stderr，被吞掉就没法排查
  local rc=0
  leandbg="$(mktemp)"
  lake env lean "$PROJ/MeasureRefs.lean" >"$leandbg" 2>&1 || rc=$?
  cat "$leandbg"
  if [ $rc -ne 0 ]; then
    say "──── Lean 输出（last 40 行）────"
    tail -40 "$leandbg"
    say "────────────────────────────────"
    die "[$t] lean 抽取失败，退出码 $rc"
  fi
  rm -f "$leandbg"
  [ -s "$TSV" ] || die "[$t] refs.tsv 不存在或为空"

  local ROWS; ROWS=$(wc -l < "$TSV")
  say "[$t] refs.tsv 行数: $ROWS"
  [ "$ROWS" -ge 100 ] || die "[$t] refs.tsv 仅 $ROWS 行，明显异常"
  # 占位符没被替换的话，Lean 会把结果写到字面名文件里 —— 这是之前的坑，主动检查
  if [ -e "$PROJ/OUT_PATH_PLACEHOLDER" ]; then
    die "[$t] 发现 $PROJ/OUT_PATH_PLACEHOLDER —— 占位符没替换成功"
  fi

  say "[$t] 后处理：depth / unwrapped / wrapped"
  node "$APP/post.mjs" "$TSV" "$OUTD" || die "[$t] post.mjs 失败"
  [ -s "$OUTD/measures.jsonl" ] || die "[$t] measures.jsonl 为空"
  [ -s "$OUTD/summary.json" ] || die "[$t] summary.json 为空"

  say "[$t] 生成可喂 AI 的报告"
  node "$APP/build_report.mjs" "$OUTD/measures.jsonl" "$OUTD" "$t${OAI_SUBTREE:+ $OAI_SUBTREE}" "$PROJ" \
    || say "[$t] ⚠️ 报告生成失败（不影响 measures.jsonl）"

  say "[$t] 完成：$(wc -l < "$OUTD/measures.jsonl") 条声明"
}

# ════════════════════════════════════════════════════════════════
# 阶段 4：上传
# ════════════════════════════════════════════════════════════════
do_upload() {
  [ "${SKIP_UPLOAD:-0}" = "1" ] && { say "SKIP_UPLOAD=1"; return 0; }
  [ -n "$GH_TOKEN" ] || die "缺少 GITHUB_TOKEN / LCM_GH_TOKEN"

  # meta.json
  RES="$RES" WORK="$WORK" TARGETS="$TARGETS" OAI_SUBTREE="$OAI_SUBTREE" node -e '
    const fs=require("fs"),os=require("os"),cp=require("child_process");
    const sh=c=>{try{return cp.execSync(c,{stdio:["ignore","pipe","ignore"]}).toString().trim()}catch{return null}};
    const R=process.env.RES,W=process.env.WORK;
    fs.writeFileSync(R+"/meta.json",JSON.stringify({
      targets:process.env.TARGETS.trim().split(/\s+/).filter(Boolean),
      subtree:process.env.OAI_SUBTREE||null,
      generated_at:new Date().toISOString(), work_dir:W,
      cpu:{vcpu:os.cpus().length,model:(os.cpus()[0]||{}).model},
      memory_gb:Math.round(os.totalmem()/1e9), node:process.version,
      lean:sh("lean --version"),
      commits:{mathlib:sh("git -C "+W+"/mathlib4 rev-parse HEAD"),
               oai:sh("git -C "+W+"/oai rev-parse HEAD")}
    },null,1));
  ' 2>/dev/null || true

  # 压缩大文件
  find "$RES" -name 'measures.jsonl' -not -name '*.gz' -exec gzip -9 -f {} + 2>/dev/null || true
  if [ "${LCM_PUSH_REFS:-0}" = "1" ]; then
    find "$RES" -name 'refs.tsv' -exec gzip -9 -f {} + 2>/dev/null || true
  fi

  # 体积守卫
  say "体积检查:"
  local EXCLUDE=""
  if ! node "$APP/sizeguard.mjs" "$RES" $([ "${LCM_PUSH_REFS:-0}" = "1" ] && echo --refs); then
    EXCLUDE="measures.jsonl.gz"
    say "⚠️ 有文件超 GitHub 单文件上限，排除 $EXCLUDE"
  fi

  # 暂存
  local STAGE="/tmp/stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE/results" "$STAGE/logs"
  while IFS= read -r f; do
    [ -e "$f" ] || continue
    local rel="${f#$RES/}" base; base="$(basename "$f")"
    [ -n "$EXCLUDE" ] && [ "$base" = "$EXCLUDE" ] && { say "  排除 $rel"; continue; }
    mkdir -p "$STAGE/results/$(dirname "$rel")"
    cp "$f" "$STAGE/results/$rel" 2>/dev/null || true
  done < <(find "$RES" -type f 2>/dev/null)
  cp -r "$LOGS"/. "$STAGE/logs/" 2>/dev/null || true

  local REMOTE="https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git"
  cd "$STAGE" || die "无法进入暂存目录"
  git init -q; git config user.email "bot@localhost"; git config user.name "lean-measure bot"
  git checkout -q -b "$RESULT_BRANCH"
  git add -f results logs 2>/dev/null || true
  git commit -q -m "measure: $TARGETS @ $(ts)" || { say "无变更可提交"; return 0; }
  # 分支名已按实例唯一，正常不会冲突；若非快进则强制覆盖自己的分支
  git push -q --force "$REMOTE" "$RESULT_BRANCH" || die "推送失败"
  say "已推送 → $GH_REPO 分支 $RESULT_BRANCH"
}

# ════════════════════════════════════════════════════════════════
# 自检
# ════════════════════════════════════════════════════════════════
preflight() {
  say "环境: ${VCPU} vCPU, ${MEM_GB} GB RAM"
  say "工作目录: $WORK（容器盘）"
  df -BG "$WORK" | awk 'NR==2{print "  可用: "$4" / 总量: "$2}'
  AVAIL_GB=$(df -BG "$WORK" | awk 'NR==2{gsub("G","",$4); print $4}')
  say "目标: $TARGETS${OAI_SUBTREE:+   subtree=$OAI_SUBTREE}"
  if [ "${JOBS_AUTO:-0}" = "1" ]; then
    say "并发: JOBS=$JOBS（自动：${VCPU} vCPU / ${MEM_GB}G → CPU上限 $JOBS_CPU, 内存上限 $JOBS_MEM）"
  else
    say "并发: JOBS=$JOBS（手动）"
  fi
  say "看门狗: ${DEADLINE_H}h"

  # 提前把"关不了机"这件事说清楚，别等跑完才发现
  if [ "${LCM_KEEPALIVE:-0}" = "1" ]; then
    say "关机: 保留 Pod（LCM_KEEPALIVE=1），SSH 可用，记得手动删"
  elif [ -z "${RUNPOD_API_KEY:-}" ]; then
    say "────────────────────────────────────────────────────────"
    say "⚠️ 没设 RUNPOD_API_KEY —— 跑完【不会】自动关机。"
    say "   本版不会用 kill 1 兜底（那会造成无限重启循环，把 SSH 挤掉）。"
    say "   Pod 会保持运行并计费，请手动删；或补上 RUNPOD_API_KEY 后下次生效。"
    say "────────────────────────────────────────────────────────"
  else
    say "关机: 跑完调 RunPod API 删除本 Pod"
  fi

  if [ "$OAI_FULL" = "1" ] && [ "$AVAIL_GB" -lt 110 ]; then
    die "全量 OAI 需约 110G，当前仅 ${AVAIL_GB}G"
  fi
  if [ "$AVAIL_GB" -lt "$WORK_NEED_GB" ]; then
    die "工作盘仅 ${AVAIL_GB}G，本次需约 ${WORK_NEED_GB}G。
    请加大 Container Disk，或设 LCM_WORK=<更大的挂载点>。"
  fi
}

# ════════════════════════════════════════════════════════════════
# 调度
# ════════════════════════════════════════════════════════════════
# 看门狗入口：必须在取实例锁之前，否则看门狗起子进程时会撞上自己的锁
if [ "$PHASE" = "__selfterm" ]; then selfterm; exit 0; fi

acquire_lock
trap release_lock EXIT INT TERM

RESULT_BRANCH="${LCM_RESULT_BRANCH:-results-${HOST_TAG}-$(date -u +%m%d-%H%M%S)}"

DEADLINE_H="${LCM_DEADLINE_HOURS:-24}"
if [ "$DEADLINE_H" != "0" ] && [ "${LCM_SELFTERM:-1}" != "0" ]; then
  ( sleep $(( DEADLINE_H * 3600 ))
    echo "[$(ts)] 看门狗到点，强制关机" >> "$LOGS/watchdog.log"
    bash "$APP/run.sh" __selfterm >> "$LOGS/watchdog.log" 2>&1
  ) &
  WATCHDOG_PID=$!
  say "看门狗已武装: ${DEADLINE_H}h 后强制关机（pid $WATCHDOG_PID）"
fi

# ════════════════════════════════════════════════════════════════
# 启动循环熔断
#   容器反复重启会一边烧钱一边把 SSH 挤掉，人根本进不去。
#   这里记录每次启动时间（持久化在 /work，容器重启后仍在），
#   短时间内反复启动就【拒绝干活并保持存活】，把控制权交回给人。
# ════════════════════════════════════════════════════════════════
BOOT_LOG="$WORK/.boots"
echo "$(date +%s)" >> "$BOOT_LOG" 2>/dev/null || true
if [ -f "$BOOT_LOG" ]; then
  NOW=$(date +%s)
  awk -v now="$NOW" '$1 > now-600' "$BOOT_LOG" > "$BOOT_LOG.tmp" 2>/dev/null && mv "$BOOT_LOG.tmp" "$BOOT_LOG"
  RECENT=$(wc -l < "$BOOT_LOG" 2>/dev/null || echo 1)
  say "启动计数（近 10 分钟）: $RECENT"
  if [ "$RECENT" -ge 3 ] && [ "${LCM_IGNORE_BOOTLOOP:-0}" != "1" ]; then
    say "════════════════════════════════════════════════════════"
    say "❌ 检测到启动循环：近 10 分钟内启动了 $RECENT 次。"
    say "   典型原因是上次结束时容器退出、被 RunPod 重新拉起。"
    say "   为止损，本次【不执行任何任务】，保持容器存活等人工处理。"
    say ""
    say "   处理办法（任选）："
    say "     1. 去 RunPod 控制台删掉本 Pod"
    say "     2. rm -f $BOOT_LOG 后重跑"
    say "     3. 设 LCM_IGNORE_BOOTLOOP=1 强制忽略"
    say "════════════════════════════════════════════════════════"
    notify fail "lean-measure 启动循环已熔断" \
      "近 10 分钟内启动了 $RECENT 次，已停止执行任务以止损。
Pod 保持存活（SSH 可用）。请删掉 Pod，或 SSH 进去执行：
    rm -f $BOOT_LOG
然后重跑。"
    [ -n "${WATCHDOG_PID:-}" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
    release_lock
    exec sleep infinity          # 保持存活，让 SSH 有办法进来
  fi
fi

preflight

case "$PHASE" in
  toolchain) run_stage toolchain do_toolchain ;;
  deps)      for t in $TARGETS; do run_stage "deps-$t" do_deps "$t"; done ;;
  build)     for t in $TARGETS; do run_stage "build-$t" do_build "$t"; done ;;
  measure)   for t in $TARGETS; do run_stage "measure-$t" do_measure "$t"; done ;;
  upload)    run_stage upload do_upload ;;
  all)
    MOUNTS="$(df -BG 2>/dev/null | awk 'NR>1{printf "%s 总%s 可用%s → %s\n",$1,$2,$4,$6}')"
    notify start "lean-measure 启动" \
      "目标: $TARGETS${OAI_SUBTREE:+   subtree=$OAI_SUBTREE}
主机: ${VCPU} vCPU / ${MEM_GB} GB RAM
并发: JOBS=$JOBS
工作目录: $WORK
分支: $RESULT_BRANCH

挂载点:
$MOUNTS"

    do_upload >/dev/null 2>&1 || say "首次占位上传失败（不致命）"

    FAILED=0
    run_stage toolchain do_toolchain || FAILED=1
    if [ $FAILED -eq 0 ]; then
      # 某个目标失败时【不中断】后面的目标：两个目标是独立的（OAI 自带 pinned
      # mathlib），而且失败信息都希望能传回来。只记录 FAILED。
      for t in $TARGETS; do
        say "════════ 目标: $t ════════"
        tf=0                      # 注意：这里在 case 块里，不能用 local
        run_stage "deps-$t"    do_deps    "$t" || tf=1
        run_stage "build-$t"   do_build   "$t" || tf=1
        run_stage "measure-$t" do_measure "$t" || tf=1
        do_upload >/dev/null 2>&1 || true
        if [ "${tf:-0}" -eq 0 ]; then
          say "════════ $t 完成 ════════"
        else
          say "════════ $t 未完成（详情见 $LOGS/*$t.log）════════"
          FAILED=1
        fi
      done
    fi
    do_upload || say "最终上传失败"

    if [ $FAILED -eq 0 ]; then
      SUM=""
      for t in $TARGETS; do
        [ -f "$RES/$t/summary.json" ] && SUM="$SUM
[$t] $(node -e "const o=require('$RES/$t/summary.json');console.log('斜率 '+o.fit.slope_bits_per_level+' bit/层, r='+o.fit.r+', 声明 '+o.declarations)" 2>/dev/null)"
      done
      notify ok "lean-measure 全部完成" \
        "目标: $TARGETS
总耗时: $(fmt_dur "$(elapsed)")$SUM
结果: https://github.com/$GH_REPO/tree/$RESULT_BRANCH
Pod 即将自动关机"
    else
      notify fail "lean-measure 未完成" \
        "目标: $TARGETS
已用: $(fmt_dur "$(elapsed)")
日志: https://github.com/$GH_REPO/tree/$RESULT_BRANCH/logs
Pod 即将自动关机（失败也关）"
    fi

    [ -n "${WATCHDOG_PID:-}" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
    selfterm
    exit $FAILED
    ;;
  *) die "未知阶段: $PHASE（toolchain|deps|build|measure|upload|all）" ;;
esac
