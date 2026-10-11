#!/usr/bin/env bash
# 诊断 RunPod 自动关机为什么不生效。
#
# 在 Pod 里跑：bash /app/diagnose_selfterm.sh
# 只做只读探测（不会真的删 Pod），把每条请求的 HTTP 码与响应体打出来。
set -o pipefail

echo "===== 1. 环境变量 ====="
echo "  RUNPOD_POD_ID     = '${RUNPOD_POD_ID:-（空）}'"
echo "  RUNPOD_POD_ID 长度 = ${#RUNPOD_POD_ID}"
echo "  RUNPOD_API_KEY    = '${RUNPOD_API_KEY:0:6}...（长度 ${#RUNPOD_API_KEY}）'"
echo "  hostname          = '$(hostname)'"
echo "  LCM_KEEPALIVE     = '${LCM_KEEPALIVE:-（未设）}'"
echo "  LCM_SELFTERM      = '${LCM_SELFTERM:-（未设，默认 1）}'"
echo

PID="${RUNPOD_POD_ID:-}"
KEY="${RUNPOD_API_KEY:-}"
[ -n "$PID" ] || { echo "!! RUNPOD_POD_ID 为空 —— RunPod 没注入，无法定位 Pod"; exit 1; }
[ -n "$KEY" ] || { echo "!! RUNPOD_API_KEY 为空"; exit 1; }

echo "===== 2. API key 是否有效（GET 自己的 Pod，只读）====="
code=$(curl -sS -o /tmp/d1.txt -w '%{http_code}' --max-time 30 \
  "https://rest.runpod.io/v1/pods/${PID}" \
  -H "Authorization: Bearer ${KEY}" 2>&1 || echo 000)
echo "  GET /pods/$PID  →  HTTP $code"
head -c 400 /tmp/d1.txt 2>/dev/null; echo
echo

echo "===== 3. Pod ID 是否被 RunPod 认成合法 ID ====="
echo "  （若上面返回 400/404，说明 PID 形式不对；对照控制台里的 Pod ID）"
echo

echo "===== 4. 试各端点的【响应码】（start 是幂等的，stop 才是关机）====="
for ep in "pods/${PID}/start" "pods/${PID}/stop"; do
  code=$(curl -sS -o /tmp/d2.txt -w '%{http_code}' --max-time 30 \
    -X POST "https://rest.runpod.io/v1/${ep}" \
    -H "Authorization: Bearer ${KEY}" -H 'Content-Type: application/json' \
    -d '{}' 2>&1 || echo 000)
  echo "  POST /$ep  →  HTTP $code"
  echo "     $(head -c 300 /tmp/d2.txt 2>/dev/null)"
done
echo

echo "===== 5. 结论提示 ====="
cat <<'EOF'
  · GET 返回 200            → key 有效、PID 正确。删除应该能成；若删除失败看第 6 步。
  · GET 返回 401            → key 错或已失效
  · GET 返回 400 / 404      → RUNPOD_POD_ID 不是 RunPod 认的 ID
                              （对照控制台 Pod 详情里的 ID）
  · start 返回 200/204      → 说明写操作权限没问题，DELETE 也应能成
  · start 返回 401          → key 只有读权限（RunPod 的 key 是读写一体的，少见）
EOF
echo
echo "===== 6. 真正删除（会立刻删掉本 Pod，谨慎！）====="
echo "  想真的删就手动执行："
echo "    curl -sS -o /tmp/del.txt -w 'HTTP %{http_code}\\n' -X DELETE \\"
echo "      https://rest.runpod.io/v1/pods/${PID} \\"
echo "      -H 'Authorization: Bearer ${KEY}'; cat /tmp/del.txt"
