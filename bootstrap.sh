#!/usr/bin/env bash
# 一行启动：取代码 → 交给 run.sh。
#
# 幂等：/app/run.sh 已存在就复用，不重复克隆。
#
# 可覆盖（都不必设）：
#   LCM_REPO_URL   代码仓库
#   LCM_REF        分支/标签
#   LCM_WORK       工作目录（默认 /work，容器盘）
#   GITHUB_TOKEN / FEISHU_WEBHOOK / FEISHU_SECRET   凭证
set -o pipefail

REPO_URL="${LCM_REPO_URL:-https://github.com/lxingrui/lean-measure.git}"
REF="${LCM_REF:-main}"
APP=/app

echo "===== 引导 $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
echo "仓库: $REPO_URL  分支: $REF"

if [ -f "$APP/run.sh" ]; then
  echo "代码已存在，复用 $APP"
else
  command -v git >/dev/null 2>&1 || {
    echo "安装 git / ca-certificates"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends git ca-certificates
  }
  rm -rf "$APP"
  echo "克隆代码"
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$APP" || { echo "!! 克隆失败" >&2; exit 1; }
fi

exec bash "$APP/run.sh" all
