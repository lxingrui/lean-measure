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
# ⚠️ 关键教训：kill 1 只是让容器主进程退出，**RunPod 会按重启策略把容器
#    再拉起来** —— 结果是无限循环重启（实测每 15 秒一轮），而不是关机。
#    所以唯一可靠的关机方式是调 RunPod API 【删除 Pod】。
#
#   RUNPOD_POD_ID  由 RunPod 运行时自动注入，无需设置
#   RUNPOD_API_KEY 必须提供，否则删不了 Pod（RunPod → Settings → API Keys）
#   LCM_KEEPALIVE=1  跑完不关机、保留现场（调试用）
#
# 拿不到 key 时只做 kill 1，并明确警告它会触发重启循环。
# ════════════════════════════════════════════════════════════════
selfterm() {
  if [ "${LCM_KEEPALIVE:-0}" = "1" ]; then
    say "LCM_KEEPALIVE=1：不关机，Pod 保留现场供排查"
    return 0
  fi
  if [ "${LCM_SELFTERM:-1}" = "0" ]; then
    say "LCM_SELFTERM=0，跳过自动关机（记得手动删 Pod）"; return 0
  fi

  local pid="${RUNPOD_POD_ID:-}" key="${RUNPOD_API_KEY:-}"

  if [ -z "$key" ]; then
    say "────────────────────────────────────────────────────────"
    say "⚠️ 未提供 RUNPOD_API_KEY，无法删除 Pod。"
    say "   只能 kill 1，而 RunPod 会按重启策略把容器再拉起来 ——"
    say "   这会导致【无限循环重启】（实测每 15 秒一轮），不是关机。"
    say "   两个解决办法（任选其一）："
    say "     a) 加环境变量 RUNPOD_API_KEY=<你的 RunPod API Key>"
    say "     b) 在 RunPod 控制台把本 Pod 的重启策略设为不重启"
    say "────────────────────────────────────────────────────────"
    say "自动关机：kill 1（会触发重启循环，请手动删 Pod）"
    sync; sleep 3; kill 1 2>/dev/null || true
    return 0
  fi

  if [ -z "$pid" ]; then
    say "⚠️ RUNPOD_POD_ID 为空（非 RunPod 环境？），跳过删除"
    return 0
  fi

  say "自动关机：DELETE https://rest.runpod.io/v1/pods/$pid"
  local code
  code=$(curl -sS -o /tmp/rp_del.txt -w '%{http_code}' --max-time 30 \
    -X DELETE "https://rest.runpod.io/v1/pods/${pid}" \
    -H "Authorization: Bearer ${key}" 2>/dev/null || echo 000)
  say "  HTTP $code  $(head -c 300 /tmp/rp_del.txt 2>/dev/null)"
  case "$code" in
    200|204) say "Pod 删除请求已接受，即将随容器一起消失"; sleep 20 ;;
    *) say "⚠️ 删除失败（HTTP $code）。改用 kill 1 兜底 —— 注意这可能触发重启循环。"
       sync; sleep 3; kill 1 2>/dev/null || true ;;
  esac
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
  say "==> $name"
  if ! "$@" 2>&1 | tee -a "$LOGS/$name.log"; then
    local d=$(( $(date +%s) - t0 ))
    mark_progress "$name" failed
    notify fail "lean-measure 失败" \
      "阶段: $name
耗时: $(fmt_dur $d)（累计 $(fmt_dur "$(elapsed)")）
目标: $TARGETS${OAI_SUBTREE:+  subtree=$OAI_SUBTREE}

最近日志:
$(tail -n 15 "$LOGS/$name.log" 2>/dev/null || echo '(无)')"
    die "$name 阶段失败，详见 $LOGS/$name.log"
  fi
  local d=$(( $(date +%s) - t0 ))
  notify ok "阶段完成: $name" \
    "耗时: $(fmt_dur $d)（累计 $(fmt_dur "$(elapsed)")）
目标: $TARGETS"
  mark_progress "$name" done
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
    say "关机: 已关闭（LCM_KEEPALIVE=1），Pod 会保留，记得手动删"
  elif [ "${LCM_SELFTERM:-1}" = "0" ]; then
    say "关机: 已关闭（LCM_SELFTERM=0），记得手动删 Pod"
  elif [ -z "${RUNPOD_API_KEY:-}" ]; then
    say "────────────────────────────────────────────────────────"
    say "⚠️ 没设 RUNPOD_API_KEY —— 跑完只能 kill 1，而 RunPod 会重启容器，"
    say "   会造成【无限循环重启】而不是关机。"
    say "   现在补上还来得及：给本 Pod 加环境变量 RUNPOD_API_KEY"
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

HOST_TAG="$(hostname 2>/dev/null | tr -cd 'a-zA-Z0-9' | head -c 12)"; [ -z "$HOST_TAG" ] && HOST_TAG=pod
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
      for t in $TARGETS; do
        say "════════ 目标: $t ════════"
        run_stage "deps-$t"    do_deps    "$t" || { FAILED=1; break; }
        run_stage "build-$t"   do_build   "$t" || { FAILED=1; break; }
        run_stage "measure-$t" do_measure "$t" || { FAILED=1; break; }
        do_upload >/dev/null 2>&1 || true
        say "════════ $t 完成 ════════"
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
