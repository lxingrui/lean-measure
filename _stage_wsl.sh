#!/usr/bin/env bash
# 把 Windows 侧的代码复制到 WSL 的 /tmp/lcm-app，并准备 node 转发。
set -e
SRC="/mnt/c/Users/Gionix/Desktop/project Caelum/modello/lean-measure"
DST=/tmp/lcm-app
mkdir -p "$DST"

# node 转发（WSL 里没有 node，但能执行 Windows 的 node.exe）
printf '#!/usr/bin/env bash\nexec "/mnt/c/Program Files/nodejs/node.exe" "$@"\n' > "$DST/node"
chmod +x "$DST/node"

for f in run.sh bootstrap.sh post.mjs build_report.mjs notify.mjs sizeguard.mjs subst_template.mjs test_e2e.sh diagnose_selfterm.sh measure.lean; do
  cp "$SRC/$f" "$DST/$f"
done
# .env.example 用不上，跳过

echo "复制完成:"
ls -la "$DST"
echo
echo "node 版本: $("$DST/node" --version)"
