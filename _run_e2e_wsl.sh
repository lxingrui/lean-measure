#!/usr/bin/env bash
# 运行 E2E 模拟。凭证从环境变量传入，不落盘。
#   LCM_GH_TOKEN      推送到测试仓库用
#   FEISHU_WEBHOOK / FEISHU_SECRET   通知用
set -o pipefail

MODE="${1:-ok}"
TOKEN="${LCM_GH_TOKEN:-}"
[ -n "$TOKEN" ] || { echo "!! 缺少 LCM_GH_TOKEN"; exit 1; }
[ -n "${FEISHU_WEBHOOK:-}" ] || echo "（未提供 FEISHU_WEBHOOK，通知会被跳过）"

export PATH="/tmp/lcm-app:$PATH"

# WSL 的 git 默认没有凭证助手，会卡在交互提示上；给一个从环境变量读的
cat > /tmp/lcm-app/cred.sh <<'CE'
#!/usr/bin/env bash
[ "$1" = get ] && printf 'username=x-access-token\npassword=%s\n' "$LCM_GH_TOKEN"
CE
chmod +x /tmp/lcm-app/cred.sh
git config --global credential.helper /tmp/lcm-app/cred.sh

# 关掉 git 的交互提示，避免任何情况下卡住
export GIT_TERMINAL_PROMPT=0

echo "===== 预检 ====="
echo "  git:  $(git --version)"
echo "  node: $(node --version)"
echo "  token 长度: ${#TOKEN}"
echo "  webhook: ${FEISHU_WEBHOOK:0:45}..."
echo "  secret 长度: ${#FEISHU_SECRET}"
echo "  测试仓库: ${LCM_GH_REPO:-lxingrui/lean-measure-test}"
echo

# 先单独验证推送能力（省得跑完 5 分钟才发现推不上去）
D=/tmp/lcm-prepush; rm -rf "$D"; mkdir -p "$D"
( cd "$D" && git init -q && echo hi > a.txt && git add -A \
  && git -c user.email=t@t -c user.name=t commit -q -m preflight \
  && git push -q "https://x-access-token:${TOKEN}@github.com/${LCM_GH_REPO:-lxingrui/lean-measure-test}.git" --force HEAD:refs/heads/preflight-check 2>&1 )
if [ $? -eq 0 ]; then echo "  ✅ 推送预检通过"; else echo "  ❌ 推送预检失败，停止"; exit 1; fi
echo

bash /tmp/lcm-app/test_e2e.sh "$MODE"
