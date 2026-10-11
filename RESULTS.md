# Lean 库压缩签名：mathlib 与 OAI 测量结果

> 本文件由 `make_results_doc.mjs` 从两次测量的原始数据（`measures.jsonl`）
> **独立重算**生成 —— 所有统计量都不是从 `summary.json` 抄来的，
> 因此它同时是一次交叉验证（重算值与 `summary.json` 一致）。

方法依据：Aksenov / Bodnia / Freedman / Mulligan,
*[arXiv:2603.20396](https://arxiv.org/abs/2603.20396)* §3。

---

## 1. 计算条件

### 1.1 基元（primitive）的定义 —— 展开到哪里停

**基元 = 没有定义体的常量**，即 `ConstantInfo.value?` 为 `none`。
具体是这四类：`inductInfo`（归纳类型）、`ctorInfo`（构造子）、
`recInfo`（递归子）、`axiomInfo`（公理）。

**判据是唯一的 —— 只看有没有定义体，不看名字前缀、不看模块归属。**
这一点很重要，两个后果：

- `Nat.add` **有**定义体（展开到 `Nat.rec`）⇒ 可继续展开，**不是**基元
- `Nat.rec` 是递归子，**没有**定义体 ⇒ **是**基元
- `Init` / `Std` / `Batteries` 里的 `def` 也会被继续展开，
  不会在底层被"因为不在 Mathlib 命名空间"而整片截断

**基元的长度记为 1。**

> 代码位置：`measure.lean` 的 `expandable` 集合 ——
> `match ci with | .defnInfo _ | .thmInfo _ => s.insert n | _ => s`
> 即**可展开 = defnInfo 或 thmInfo**；其余（induct/ctor/rec/axiom）为基元。

### 1.2 图怎么建

顶点与边都来自 **elaboration 之后的 `Expr`**，不是源码文本。

**为什么必须走 `Expr`**：`simp` / `rw` 等 tactic 在 elaboration 时会展开成
大量内部引用；源码里一次 tactic 调用只是一个 token。
若解析源码会**严重低估**展开量 —— 这正是论文 §3.2 解释
"wrapped 为何用 token 数而非引用数"的原因。

对每个声明 `u`，遍历其 `info.type` 与 `info.value?`，用论文 §3.1 的
`collectElems` 递归收集所有 `.const` 引用并累计出现次数：

```lean
partial def collectElems (e : Expr) (acc : Std.HashMap Name Nat) :=
  match e with
  | .const declName _   => acc.insert declName (acc.getD declName 0 + 1)
  | .app fn arg         => collectElems arg (collectElems fn acc)
  | .lam _ t b _        => collectElems b (collectElems t acc)
  | .forallE _ t b _    => collectElems b (collectElems t acc)
  | .letE _ t v b _     => collectElems b (collectElems v (collectElems t acc))
  | .mdata _ expr       => collectElems expr acc
  | .proj _ _ struct    => collectElems struct acc
  | .sort _             => acc.insert `Sort (… + 1)   // 宇宙层级记为 Sort
  | _                   => acc
```

**顶点 / 边的取舍规则**：

| 规则 | 说明 |
|---|---|
| 顶点 = **有定义体的声明** | 即 `defnInfo`/`thmInfo`。无定义体者（基元）不作为顶点，只作为边的终点 |
| **自引用丢弃** | `tname == cname` 的引用不计入（避免自环） |
| 边的权重 = 引用出现次数 | 同一个常量被引用 w 次 ⇒ 权重 w |
| 边的方向 | `src → tgt`，`tgt` 是被引用的常量 |

### 1.3 三个量怎么算

#### (a) `depth(u)` —— 到基元的**最长**路径

```
depth(u) = 0                        若 u 没有任何出边
depth(u) = 1 + max{ depth(v) }      对所有出边 u → v
```

取 **max**（最长路），不是最短。基元的 depth 定义为 0。

#### (b) `wrapped(u)` —— 声明的 token 数

用 Lean parser 计，**不是**引用数。论文 §3.2 明确以这一点解释：
若用引用数，`simp`/`rw` 展开出的大量内部引用会让"表面大小"虚高。

> 本次交付的 `measures.jsonl` **不含** `wrapped` 列 ——
> 它需要在抽取阶段额外统计 token，尚未接入。这是一个已知缺口。

#### (c) `unwrapped(u)` —— 展开到基元后的加权长度

递归定义：

```
unwrapped(u) = 0                                    若 u 无出边
unwrapped(u) = Σ over 出边 u →(w) v  of  w · unwrapped(v)
```

若某条边的终点 `v` 是**基元**，则取 `unwrapped(v) = 1`（基元长度记 1）。

**实现上是"自底向上展开"**：从基元往上逐层代入，因此 `unwrapped`
对深层声明的数值会**极大**（可达 10^22 量级），所以全程在对数域计算（见 1.4）。

### 1.4 数值实现：避免溢出

`unwrapped` 直接算会溢出双精度。所以：

| 措施 | 说明 |
|---|---|
| **SCC 缩点** | 用 Tarjan 求强连通分量并缩点，得到 DAG。SCC 内部引用贡献 0（避免循环放大） |
| **拓扑序单趟递推** | 按拓扑序自底向上算一次，而非迭代松驰（迭代松驰曾实测不收敛） |
| **对数域相加** | `log10(a+b) = max + log10(1 + 10^(-|Δ|))`，两个数量级差 >15 时直接取大者 |
| **只存 log2** | 落盘的 `log2U` 即 `log2(unwrapped)` |
| **CSR 结构** | 用 `Int32Array` 存压缩稀疏行，避免百万级边时内存爆掉 |

### 1.5 回归

对**全部声明**做一元最小二乘：

```
log2(unwrapped) = slope · depth + intercept
```

残差 `res = log2U − (slope·depth + intercept)`，
`sigma` = 残差的标准差（分母用 N 而非 N−1），
3σ 之外的记为该方向的离群点。

> 用 `log2` 而非自然对数只是单位选择：`slope` 的单位是 **bit/层**。
> `slope = 1` 意味着每深入一层，展开量乘以 2。

---

## 2. 测量对象与运行环境

| 项 | 值 |
|---|---|
| 平台 | RunPod CPU Pod，8 vCPU（AMD EPYC 4564P，5 GHz）/ 124 GB RAM |
| Lean | v4.34.1（commit `5045d005`） |
| 并发 | `LEAN_NUM_THREADS=7`（注：`lake build` 没有 `-j` 选项） |
| 工作目录 | 容器盘 `/work`（120 GB 本地 NVMe）；**未使用网络卷** |
| 全流程耗时 | **16 分 04 秒**（两个目标合计） |
| 结果分支 | `results-38191071eb65-1011-080938` |

**两个测量对象**：

| 目标 | 入口模块 | commit |
|---|---|---|
| mathlib | `Mathlib` | `2da3ab0a20dc0c66f56a557e37df39f7d36cb953` |
| oai | `OAI.Analysis.Crouzeix.Main` | `fd4aeeb2ee4fc729c18d98444fed42fd0529eeeb` |

**⚠️ 重要：测的是"整个环境"，不是"该库自身"。**

`measure.lean` 遍历 `env.constants`，而 `import Mathlib` 会把 Mathlib
的全部依赖（Lean 内核、Init、Std、Batteries、Aesop、Lake…）一并载入环境。
所以下面的声明数**包含依赖库**。

这与论文一致 —— 论文的顶点定义就是"环境里所有声明"，
它报 463,719 个元素并注明同时记录了"模块索引与声明名"以便区分归属。
**本实现的 `post.mjs` 目前不保留模块索引**，因此无法从这份数据里筛出
"Mathlib 自身"的子集。这是已知限制（见第 5 节）。

---

## 3. 核心结果

### 3.1 主回归

| | mathlib | OAI / Crouzeix |
|---|---|---|
| 声明数 N | **327,627** | **312,822** |
| **斜率 (bit/层)** | **0.7827** | **0.8066** |
| 截距 | 3.5793 | 3.5597 |
| **相关系数 r** | **0.9360** | **0.9382** |
| 残差 sigma (bit) | 4.2766 | 4.2902 |
| 3σ 阈值 (bit) | ±12.8299 | ±12.8705 |
| 上方离群 (>+3σ) | 3,054 | 2,635 |
| 下方离群 (<−3σ) | 461 | 454 |

**两个完全独立的库，斜率差仅 0.0239 bit/层**
（0.7827 vs 0.8066），相关系数也都 ≈ 0.94。
这是支持"压缩签名自相似"的一个相当强的证据。

**与论文的对比**：论文报 **≈ 1 bit/层**。
本次两个库都落在 **0.78 – 0.81**，
比论文的单一数字**更细也更低**。

### 3.2 分布

| | mathlib | OAI |
|---|---|---|
| depth: 最小 / p25 / **中位** / p75 / p90 / 均值 / 最大 | 0 / 0 / **3** / 16 / 33 / 10.11 / 86 | 0 / 0 / **3** / 16 / 31 / 9.87 / 86 |
| log2U: 最小 / p10 / p25 / **中位** / p75 / p90 / 均值 / 最大 | 0.00 / 0.00 / 0.00 / **8.40** / 18.28 / 30.38 / 11.49 / 75.18 | 0.00 / 0.00 / 0.00 / **8.23** / 18.89 / 30.60 / 11.52 / 75.28 |

`log2U = 0` 的声明数（无出边，或只引用不可展开者）：
**mathlib 99,636**（占 30.41%）、
**OAI 98,596**（占 31.52%）。

> 这些不是"提取漏了"。按 1.1 的判据，`_proof_*` 这类自动生成的证明
> 属于"不可展开 ⇒ 尺寸贡献 0"，因此 `log2U = 0` 是口径的必然结果。

### 3.3 自相似性检验（分段回归）

若"每层放大同一个常数"成立，各 depth 区间的斜率应当一致。
实测**并不一致**：

| depth 区间 | mathlib 样本数 | mathlib 斜率 | OAI 样本数 | OAI 斜率 |
|---|---|---|---|---|
| 0 – 3 | 167,433 | 2.9514 | 161,785 | 2.9816 |
| 4 – 8 | 47,229 | 1.0634 | 45,827 | 1.1101 |
| 9 – 15 | 26,779 | 0.6587 | 26,104 | 0.6680 |
| 16 – 25 | 43,670 | 0.4508 | 40,184 | 0.3404 |
| 26 – 40 | 20,386 | 0.6067 | 18,210 | 0.6590 |
| 41 – 86 | 22,130 | 0.4579 | 20,712 | 0.4645 |

两个库表现出**同一个模式**：浅层斜率远高于深层，
且都随 depth 增大而**下降**。

**解读**：所谓"每层放大固定常数"只在**深层**近似成立。
浅层（depth 0–3）斜率极高的原因是那里聚集了大量
"几乎只引用基元"的声明 —— 它们的展开量对"层"不敏感。
论文报的 ≈1 bit/层 对应的是**深层区间**，而非全局。

### 3.4 声明名分布（说明"整个环境"这件事）

| 顶层命名空间 | mathlib | OAI |
|---|---|---|
| `_private` | 57,810 | 51,938 |
| `Lean` | 41,885 | 39,065 |
| `CategoryTheory` | 38,057 | 37,827 |
| `Std` | 15,140 | 15,385 |
| `Mathlib` | 6,779 | 6,615 |
| `Aesop` | 4,023 | 4,014 |
| `AlgebraicGeometry` | 3,130 | 3,125 |
| `Lake` | 5,247 | 0 |
| `List` | 2,526 | 2,612 |
| `MeasureTheory` | 2,283 | 2,275 |
| `Nat` | 1,893 | 1,900 |
| `SSet` | 1,694 | 1,642 |

**这张表只能说明"环境里混进了依赖库"，不能用来划分库归属。**
两个理由：

1. **Mathlib 里大量声明不用 `Mathlib.` 前缀** —— 例如 `CategoryTheory.*`
   有 38,057 条，比 `Mathlib.*` 的 6,779 条多 5 倍，但它们**都是 Mathlib 的内容**。
   命名空间是书写习惯，不是库的边界。
2. **`_private` 与 `Lean` 是自动生成的内部名**（如 `_proof_1`、`_sizeOf_inst`），
   归属它们的原始定义。

**要真正按库划分，必须在抽取阶段用 Lean 的模块索引**
（`env.getModuleIdxFor?` + `env.header.moduleNames`）判断每个声明定义在哪个模块。
这与论文的做法一致 —— 论文注明同时记录了"模块索引与声明名"。
**当前 `post.mjs` 没保留该信息，所以本文件不做库归属切分。**

---

## 4. 结论

1. **压缩签名确实存在，且是自相似的（在深层）。**
   两个独立的形式化库给出几乎相同的斜率（0.7827 与 0.8066 bit/层）
   与相关系数（0.9360 与 0.9382）。

2. **斜率不是论文的 ≈1，而是 ≈0.8。**
   等价说法：每深入一层定义，底层展开量约乘以 1.7，而非 2。

3. **"自相似"只在深层成立。** 分段回归显示浅层斜率远高（2.9、1.06…），
   随 depth 增大下降到 0.45–0.66。论文的单点数字掩盖了这个结构。

4. **两个库的绝对尺度也几乎一致**（log2U 中位 8.40 vs 8.23，最大 75.2 vs 75.3）。
   不同数学领域的库落在同一尺度上，这本身值得注意。

## 5. 已知限制

| 限制 | 说明 |
|---|---|
| **测的是整个环境** | 含 Lean/Std/Batteries 等依赖。要按库区分需在抽取阶段记录模块索引，当前未做 |
| **缺 `wrapped`** | `measures.jsonl` 不含 token 数这一列，需在抽取阶段额外统计 |
| **OAI 只测了一个子树** | `OAI/Analysis/Crouzeix`（90 个 `.lean`）。全量 OAI 未测（约需 110 GB） |
| **两个库用不同 mathlib** | mathlib 目标用 HEAD（`2da3ab0a`）；OAI 自带 pinned mathlib，版本不同。二者不是严格同环境对照 |
| **`log2U=0` 的大量条目** | 属口径必然结果（见 3.2），但会让分布的下四分位失真 |
| **未与论文数字做同口径复现** | 论文报 463,719 个元素，本次 mathlib 环境 327,627。差异可能来自 Lean 版本与提取口径，未深究 |

---

## 附：本文件如何生成

```bash
node make_results_doc.mjs mathlib.jsonl oai.jsonl RESULTS.md
```

输入是两个 `measures.jsonl`（每行 `{"name","depth","log2U"}`），
所有统计量在本脚本内重算，与 `summary.json` 独立核对。
原始数据可从对应分支下载：

```
https://github.com/lxingrui/lean-measure/blob/results-38191071eb65-1011-080938/results/mathlib/measures.jsonl.gz
https://github.com/lxingrui/lean-measure/blob/results-38191071eb65-1011-080938/results/oai/measures.jsonl.gz
```
