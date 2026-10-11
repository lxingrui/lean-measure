// 交叉核对：从 root .jsonl 重算的统计量 vs 远端 summary.json 里的值。
// 用法: node crosscheck.js <mathlib.jsonl> <oai.jsonl> <mathlib.summary.json> <oai.summary.json>
const fs = require('fs');

function stat(file) {
  const L = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
  const d = [], u = [];
  for (const l of L) { const o = JSON.parse(l); d.push(o.depth); u.push(o.log2U); }
  const N = d.length;
  let sx = 0, sy = 0, sxx = 0, sxy = 0;
  for (let i = 0; i < N; i++) { sx += d[i]; sy += u[i]; sxx += d[i] * d[i]; sxy += d[i] * u[i]; }
  const slope = (N * sxy - sx * sy) / (N * sxx - sx * sx);
  const ic = (sy - slope * sx) / N;
  let ss = 0, cov = 0, vx = 0, vy = 0;
  const mx = sx / N, my = sy / N;
  for (let i = 0; i < N; i++) {
    const r = u[i] - (slope * d[i] + ic);
    ss += r * r;
    cov += (d[i] - mx) * (u[i] - my); vx += (d[i] - mx) ** 2; vy += (u[i] - my) ** 2;
  }
  // 注意：不要用 Math.max(...d) —— 30 万元素会爆调用栈（实测 RangeError）
  const maxOf = a => a.reduce((x, y) => (y > x ? y : x), -Infinity);
  return { N, slope, sigma: Math.sqrt(ss / N), r: cov / Math.sqrt(vx * vy),
           maxD: maxOf(d), maxU: maxOf(u) };
}

const jobs = [
  ['mathlib', process.argv[2], process.argv[4]],
  ['oai    ', process.argv[3], process.argv[5]],
];

let allOk = true;
for (const [tag, jl, sm] of jobs) {
  const mine = stat(jl);
  const ref = JSON.parse(fs.readFileSync(sm, 'utf8'));
  const cmp = (k, a, b, tol) => {
    const ok = Math.abs(a - b) <= (tol ?? 5e-4);
    if (!ok) allOk = false;
    console.log(`  ${ok ? 'OK  ' : 'DIFF'} ${tag} ${k.padEnd(16)} 重算=${a}   summary=${b}`);
  };
  cmp('declarations', mine.N, ref.declarations, 0);
  cmp('slope', +mine.slope.toFixed(4), ref.fit.slope_bits_per_level);
  cmp('r', +mine.r.toFixed(4), ref.fit.r);
  cmp('sigma', +mine.sigma.toFixed(4), ref.fit.residual_sigma);
  cmp('depth.max', mine.maxD, ref.depth.max, 0);
  cmp('log2U.max', +mine.maxU.toFixed(3), ref.log2Unwrapped.max, 1e-3);
}
console.log(allOk ? '\n全部一致 ✅' : '\n有不一致项 ❌');
process.exit(allOk ? 0 : 1);
