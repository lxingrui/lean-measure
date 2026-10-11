# 压缩签名测量报告：oai OAI/Analysis/Crouzeix

> 本文件由 `build_report.mjs` 从完整数据集（312,822 条声明）计算得出。
> 原始数据是 `measures.jsonl.gz`（体积过大，不适合直接喂给模型）。
> **本报告已包含全量数据的统计结论；AI 不需要读原始数据。**

## 1. 数据集

| 量 | 值 |
|---|---|
| 声明总数 | 312,822 |
| depth 范围 | 0 – 86 |
| depth 中位 / 均值 | 3 / 9.87 |
| log2U 范围 | 0.00 – 75.28 |
| log2U 中位 / 均值 | 8.23 / 11.52 |
| log2U 分位 p10/p25/p75/p90 | 0.00 / 0.00 / 18.89 / 30.60 |

## 2. 主回归（核心结论）

```
log2(unwrapped) = 0.8066 · depth + 3.5597
n = 312822    r = 0.9382
残差 sigma = 4.2902 bit    3-sigma = ±12.8705 bit
```

**斜率 ≈ 0.81 bit/层**，即 `unwrapped ≈ 2^(0.81·depth)`，
等价于**每深入一层定义，底层展开量乘以 1.75**。

论文（arXiv:2603.20396）报的斜率是 **≈ 1 bit/层**（每层 ×2）。

## 3. 自相似性检验（按 depth 分段回归）

若「每层放大同一个常数」成立，则各 depth 区间的斜率应当一致。

| depth 区间 | 样本数 | 该区间斜率 |
|---|---|---|
| 0 – 3 | 161,785 | 2.9816 |
| 4 – 8 | 45,827 | 1.1101 |
| 9 – 15 | 26,104 | 0.668 |
| 16 – 25 | 40,184 | 0.3404 |
| 26 – 40 | 18,210 | 0.659 |
| 41 – 86 | 20,712 | 0.4645 |

## 4. 按 depth 的分布

| depth | 数量 | p10 | 中位 | p90 | 均值 |
|---|---|---|---|---|---|
| 0 | 115933 | 0.00 | 0.00 | 2.00 | 0.42 |
| 1 | 19710 | 3.00 | 5.32 | 6.83 | 5.21 |
| 2 | 15469 | 5.09 | 6.77 | 9.12 | 6.96 |
| 3 | 10673 | 5.86 | 8.07 | 10.67 | 8.22 |
| 4 | 8711 | 7.07 | 9.59 | 12.78 | 9.83 |
| 5 | 13770 | 8.67 | 10.47 | 13.34 | 10.86 |
| 6 | 9859 | 9.09 | 12.07 | 16.14 | 12.43 |
| 7 | 7136 | 9.82 | 12.84 | 17.20 | 13.12 |
| 8 | 6351 | 10.37 | 13.85 | 18.79 | 14.17 |
| 9 | 5776 | 11.23 | 15.57 | 20.83 | 15.73 |
| 10 | 4402 | 11.81 | 16.04 | 21.33 | 16.4 |
| 11 | 3756 | 12.68 | 17.58 | 22.98 | 17.72 |
| 12 | 3646 | 12.15 | 17.25 | 24.00 | 17.79 |
| 13 | 3030 | 13.74 | 18.72 | 25.15 | 19.2 |
| 14 | 3108 | 13.38 | 18.16 | 25.55 | 19 |
| 15 | 2386 | 13.63 | 18.46 | 26.58 | 19.5 |
| 16 | 6995 | 15.17 | 19.58 | 22.09 | 19.67 |
| 17 | 7714 | 16.17 | 19.58 | 22.99 | 20.11 |
| 18 | 3043 | 15.41 | 20.10 | 26.82 | 20.52 |
| 19 | 2524 | 15.74 | 20.82 | 28.29 | 21.42 |
| 20 | 3005 | 15.48 | 20.59 | 28.06 | 21.29 |
| 21 | 3389 | 15.66 | 20.50 | 28.34 | 21.21 |
| 22 | 3328 | 17.52 | 21.92 | 29.22 | 22.57 |
| 23 | 3901 | 18.62 | 21.06 | 28.23 | 22.15 |
| 24 | 2191 | 19.24 | 23.77 | 30.21 | 24.26 |
| 25 | 4094 | 17.93 | 19.55 | 28.50 | 21.81 |
| 26 | 1573 | 19.86 | 26.05 | 33.24 | 26.37 |
| 27 | 1214 | 21.84 | 27.78 | 35.10 | 28.23 |
| 28 | 1219 | 23.13 | 27.80 | 35.77 | 28.71 |
| 29 | 1357 | 19.47 | 26.63 | 35.26 | 27.49 |
| 30 | 1258 | 18.98 | 27.27 | 34.32 | 27.51 |
| 31 | 1119 | 21.04 | 28.13 | 36.21 | 28.74 |
| 32 | 1000 | 20.92 | 29.34 | 38.88 | 29.79 |
| 33 | 927 | 25.09 | 29.36 | 38.04 | 30.38 |
| 34 | 831 | 25.85 | 30.09 | 39.33 | 31.33 |
| 35 | 815 | 28.02 | 31.89 | 40.63 | 32.87 |
| 36 | 1556 | 28.24 | 32.53 | 40.41 | 33.05 |
| 37 | 1147 | 29.02 | 32.65 | 42.71 | 34.07 |
| 38 | 2013 | 30.34 | 32.24 | 38.80 | 33.36 |
| 39 | 1229 | 30.02 | 34.28 | 44.94 | 35.73 |
| 40 | 952 | 30.34 | 35.37 | 42.14 | 35.96 |
| 41 | 827 | 31.00 | 35.90 | 42.86 | 36.86 |
| 42 | 1146 | 32.00 | 35.39 | 42.44 | 36.63 |
| 43 | 1129 | 33.33 | 35.80 | 42.75 | 36.92 |
| 44 | 2185 | 33.76 | 35.51 | 40.77 | 36.4 |
| … | 共 87 个 depth 取值，完整表见 depth_stats.csv | | | | |

## 5. 离群点

| 侧 | 数量 | 占比 |
|---|---|---|
| 上方（展开异常大，残差 > +3σ） | 2,635 | 0.842% |
| 下方（展开异常小，残差 < −3σ） | 454 | 0.145% |

### 5.1 离群点成模块聚集（不是随机散布）

| 模块（前两级命名空间） | ↑上方 | ↓下方 | 上方平均残差 | 下方平均残差 |
|---|---|---|---|---|
| `AlgebraicGeometry.Scheme` | 228 | 0 | 16.4 | — |
| `_private.Mathlib` | 189 | 33 | 16.0 | 14.4 |
| `CategoryTheory.Limits` | 170 | 0 | 14.0 | — |
| `CategoryTheory.Pseudofunctor` | 160 | 0 | 16.7 | — |
| `Lean.Elab` | 0 | 83 | — | 18.2 |
| `Mathlib.Tactic` | 1 | 78 | 13.0 | 14.2 |
| `CategoryTheory.Abelian` | 64 | 0 | 16.5 | — |
| `CategoryTheory.Functor` | 55 | 0 | 15.4 | — |
| `_private.Lean` | 1 | 51 | 13.4 | 14.8 |
| `Lean.Meta` | 8 | 36 | 13.5 | 14.2 |
| `CategoryTheory.Triangulated` | 41 | 0 | 16.3 | — |
| `Std.Time` | 38 | 0 | 14.9 | — |
| `CategoryTheory.MonoidalCategory` | 35 | 0 | 14.1 | — |
| `CategoryTheory.GrothendieckTopology` | 31 | 0 | 14.0 | — |
| `CategoryTheory.Pretriangulated` | 23 | 0 | 17.7 | — |
| `CategoryTheory.Grothendieck` | 23 | 0 | 15.5 | — |
| `CategoryTheory.OverPresheafAux` | 23 | 0 | 15.4 | — |
| `CategoryTheory.Sheaf` | 23 | 0 | 14.2 | — |
| `CategoryTheory.Oplax` | 23 | 0 | 14.2 | — |
| `Polynomial.Gal` | 21 | 0 | 23.0 | — |
| `Polynomial.SplittingField` | 20 | 0 | 15.8 | — |
| `SSet.Truncated` | 20 | 0 | 14.6 | — |
| `CategoryTheory.Localization` | 19 | 0 | 15.0 | — |
| `FiniteField.instFieldExtension` | 19 | 0 | 15.0 | — |
| `Lean.Language` | 0 | 19 | — | 17.2 |
| `AlgebraicGeometry.PresheafedSpace` | 18 | 0 | 16.1 | — |
| `CyclotomicField.instField` | 18 | 0 | 15.6 | — |
| `SSet.prodStdSimplex` | 18 | 0 | 14.3 | — |
| `CategoryTheory.Lax` | 17 | 0 | 14.0 | — |
| `CategoryTheory.CatEnrichedOrdinary` | 16 | 0 | 18.3 | — |
| `Aesop.Script` | 0 | 16 | — | 18.0 |
| `SheafOfModules.Presentation` | 15 | 0 | 16.0 | — |
| `SheafOfModules.QuasicoherentData` | 15 | 0 | 16.1 | — |
| `PresheafOfModules.Sheafify` | 15 | 0 | 16.2 | — |
| `SSet.PtSimplex` | 15 | 0 | 14.4 | — |
| `CochainComplex.HomComplex` | 14 | 0 | 15.7 | — |
| `PresheafOfModulesOfCommRing.Derivation` | 14 | 0 | 15.6 | — |
| `CategoryTheory.SimplicialObject` | 14 | 0 | 14.4 | — |
| `CategoryTheory.ShortComplex` | 13 | 0 | 13.6 | — |
| `CategoryTheory.CostructuredArrow` | 12 | 0 | 15.8 | — |

### 5.2 上方离群（展开异常大）极端例子

| 残差 | depth | log2U | 声明 |
|---|---|---|---|
| +30.7 | 49 | 73.8 | `AlgebraicGeometry.Scheme.IdealSheafData.subschemeObjIso` |
| +30.6 | 51 | 75.3 | `_private.Mathlib.NumberTheory.Cyclotomic.Basic.0.CyclotomicRing.instIsFractionRingCyclotomicFieldOfIsDomainOfNeZeroCast.match_1` |
| +29.7 | 16 | 46.2 | `_private.Mathlib.CategoryTheory.Sites.Coherent.SequentialLimit.0.CategoryTheory.coherentTopology.cone` |
| +29.1 | 30 | 56.8 | `CategoryTheory.Abelian.FreydMitchell.functor` |
| +29.0 | 44 | 68.1 | `_private.Mathlib.AlgebraicGeometry.Limits.0.AlgebraicGeometry.isOpenImmersion_sigmaDesc_aux.match_1_2` |
| +28.8 | 51 | 73.5 | `AlgebraicGeometry.Scheme.kerAdjunction` |
| +28.4 | 51 | 73.1 | `AlgebraicGeometry.IsClosedImmersion.overEquivIdealSheafData` |
| +27.9 | 29 | 54.8 | `_private.Mathlib.CategoryTheory.Abelian.FreydMitchell.0.CategoryTheory.Abelian.FreydMitchell.H` |
| +27.6 | 28 | 53.8 | `CategoryTheory.Abelian.FreydMitchell.instRingEmbeddingRing` |
| +27.3 | 46 | 68.0 | `AlgebraicGeometry.Scheme.Hom.normalizationObjIso` |
| +26.9 | 49 | 70.0 | `AlgebraicGeometry.Scheme.IdealSheafData.inclusion` |
| +26.8 | 14 | 41.7 | `_private.Mathlib.CategoryTheory.Sites.Coherent.SequentialLimit.0.CategoryTheory.coherentTopology.preimage._sunfold` |
| +26.8 | 50 | 70.7 | `AlgebraicGeometry.Scheme.IdealSheafData.subschemeFunctor` |
| +26.7 | 51 | 71.4 | `AlgebraicGeometry.Scheme.IdealSheafData.comapIso` |
| +26.6 | 51 | 71.3 | `Polynomial.Gal.restrictProd` |
| +26.3 | 40 | 62.1 | `AlgebraicGeometry.presentationTilde` |
| +26.1 | 15 | 41.8 | `_private.Mathlib.CategoryTheory.Sites.Coherent.SequentialLimit.0.CategoryTheory.coherentTopology.preimageDiagram` |
| +26.1 | 50 | 70.0 | `Polynomial.Gal.restrictDvd` |
| +26.0 | 51 | 70.7 | `AlgebraicGeometry.IsClosedImmersion.lift` |
| +25.9 | 52 | 71.4 | `CyclotomicRing.algebraBase` |
| +25.9 | 14 | 40.8 | `_private.Mathlib.CategoryTheory.Sites.Coherent.SequentialLimit.0.CategoryTheory.coherentTopology.preimageStruct` |
| +25.9 | 52 | 71.4 | `CyclotomicRing.instAlgebraCyclotomicField` |
| +25.8 | 47 | 67.3 | `Polynomial.instFintypeGal._aux_1` |
| +25.8 | 50 | 69.7 | `instCommRingCyclotomicRing` |
| +25.8 | 52 | 71.3 | `AlgebraicGeometry.Scheme.IdealSheafData.subschemeMap` |

### 5.3 下方离群（展开异常小）极端例子

| 残差 | depth | log2U | 声明 |
|---|---|---|---|
| -26.7 | 79 | 40.6 | `Lean.Server.RequestContext._sizeOf_inst` |
| -25.9 | 78 | 40.6 | `Lean.Server.RequestContext._sizeOf_1` |
| -25.4 | 77 | 40.3 | `Lean.Elab.DefsParsedSnapshot._sizeOf_inst` |
| -25.1 | 77 | 40.6 | `Lean.Server.FileWorker.EditableDocument._sizeOf_inst` |
| -24.7 | 77 | 41.0 | `Lean.Elab.DefViewElabHeader._sizeOf_inst` |
| -24.6 | 76 | 40.3 | `Lean.Elab.DefsParsedSnapshot._sizeOf_1` |
| -24.3 | 76 | 40.6 | `Lean.Server.FileWorker.EditableDocument._sizeOf_1` |
| -23.9 | 76 | 41.0 | `Lean.Elab.DefViewElabHeader._sizeOf_1` |
| -23.8 | 75 | 40.2 | `Lean.Elab.DefView._sizeOf_inst` |
| -23.8 | 75 | 40.2 | `Lean.Elab.DefParsed._sizeOf_inst` |
| -23.7 | 73 | 38.8 | `Lean.Elab.Term.Context._sizeOf_inst` |
| -23.5 | 75 | 40.6 | `Lean.Server.FileWorker.EditableDocumentCore._sizeOf_inst` |
| -23.2 | 73 | 39.2 | `Aesop.SafeRulesResult._sizeOf_inst` |
| -23.2 | 73 | 39.2 | `Aesop.SafeRuleResult._sizeOf_inst` |
| -23.2 | 73 | 39.2 | `Aesop.UnsafeQueueEntry._sizeOf_inst` |
| -23.0 | 74 | 40.2 | `Lean.Elab.DefView._sizeOf_1` |
| -23.0 | 74 | 40.2 | `Lean.Elab.DefParsed._sizeOf_1` |
| -22.9 | 72 | 38.8 | `Lean.Elab.Term.Context._sizeOf_1` |
| -22.7 | 74 | 40.6 | `Lean.Server.FileWorker.EditableDocumentCore._sizeOf_1` |
| -22.5 | 73 | 39.9 | `Lean.Language.Lean.HeaderParsedSnapshot._sizeOf_inst` |
| -22.4 | 72 | 39.2 | `Aesop.SafeRulesResult._sizeOf_1` |
| -22.4 | 72 | 39.2 | `Aesop.SafeRuleResult._sizeOf_1` |
| -22.4 | 72 | 39.2 | `Aesop.UnsafeQueueEntry._sizeOf_1` |
| -22.2 | 73 | 40.2 | `Lean.Elab.HeaderProcessedSnapshot._sizeOf_inst` |
| -22.1 | 71 | 38.8 | `Lean.Elab.Tactic.TacticParsedSnapshot._sizeOf_inst` |

### 5.4 离群点源码片段

前面几节说明「**哪些**声明偏离了拟合线」，本节给出 **Lean 源码片段**，
作为回答「**为什么**偏离」的线索。

> ⚠️ **可靠性警告（务必读）**
>
> 下面的「声明名 → 源码文件」映射是**按名字反查源码**得到的，**不保证准确**。
> 已知失效情形：
>
> 1. **同名不同声明**：不同命名空间下有同名 `functor` / `map`，可能匹配到无关的那个；
> 2. **自动生成的名字**（`instXxx`、`_private.*`、`*._proof_1`）在源码里没有字面对应，必然匹配失败或错配；
> 3. 50 条离群点里，本次只索引到个位数到二十几条。
>
> **正确做法**是在抽取阶段（`measure.lean`）用 Lean 自己的 API 带上声明所在的
> 文件名与行号，而不是事后按名字猜。当前版本尚未这么做。
>
> **结论**：把本节当"在哪个文件附近"的弱线索，**不要当作确证**。
> 本节索引命中：**5 / 50** 条。

#### 上方离群

**上方 残差 +30.7 ｜ depth 49 ｜ log2U 73.8**

`AlgebraicGeometry.Scheme.IdealSheafData.subschemeObjIso`

（未索引到源码位置）

**上方 残差 +30.6 ｜ depth 51 ｜ log2U 75.3**

`_private.Mathlib.NumberTheory.Cyclotomic.Basic.0.CyclotomicRing.instIsFractionRingCyclotomicFieldOfIsDomainOfNeZeroCast.match_1`

（未索引到源码位置）

**上方 残差 +29.7 ｜ depth 16 ｜ log2U 46.2**

`_private.Mathlib.CategoryTheory.Sites.Coherent.SequentialLimit.0.CategoryTheory.coherentTopology.cone`

`ComparatorChallenges/HyperbolicCones.lean:64`

```lean
def cone : Set Ambient :=
  {x | ∀ t : ℂ, (linePolynomial x).aeval t = 0 → t.im = 0 ∧ 0 ≤ t.re}

theorem main_result :
    Module.finrank ℝ Ambient = 23 ∧
    polynomial.IsHomogeneous 20 ∧
    polynomial.totalDegree = 20 ∧
    MvPolynomial.eval (coordinates basePoint) polynomial = 1 ∧
    (∀ (x : Ambient) (z : ℂ), (linePolynomial x).aeval z = 0 → z.im = 0) ∧
    ∀ (N : ℕ) (_hN : 0 < N) (L : Ambient →ₗ[ℝ] Sym N),
      cone ≠ {x | (L x : Mat N ℝ).PosSemidef} := by
  sorry
```

**上方 残差 +29.1 ｜ depth 30 ｜ log2U 56.8**

`CategoryTheory.Abelian.FreydMitchell.functor`

`OAI/Algebra/AuslanderReiten/Tensor/BalancedTensorCategory.lean:39`

```lean
def functor : ModuleCat.{u} R ⥤ ModuleCat.{u} S where
  obj M := ModuleCat.of S (BalancedTensor k R F M)
  map a := ModuleCat.ofHom (mapRight (k := k) (F := F) (S := S) a.hom)
  map_id M := by apply ModuleCat.hom_ext; exact mapRight_id
  map_comp a b := by apply ModuleCat.hom_ext; exact mapRight_comp a.hom b.hom

instance : (functor (k := k) (R := R) (S := S) (F := F)).Additive where
  map_add := by intros; apply ModuleCat.hom_ext; exact mapRight_add _ _

def naturalMap (a : F →ₗ[Rᵐᵒᵖ] G) (ha : ∀ (s : S) f, a (s • f) = s • a f) :
    functor (k := k) (R := R) (S := S) (F := F) ⟶ functor (k := k) (R := R) (S := S) (F := G) where
  app M := ModuleCat.ofHom (mapLeftLinear (k := k) a ha M)
```

**上方 残差 +29.0 ｜ depth 44 ｜ log2U 68.1**

`_private.Mathlib.AlgebraicGeometry.Limits.0.AlgebraicGeometry.isOpenImmersion_sigmaDesc_aux.match_1_2`

（未索引到源码位置）

**上方 残差 +28.8 ｜ depth 51 ｜ log2U 73.5**

`AlgebraicGeometry.Scheme.kerAdjunction`

（未索引到源码位置）

#### 下方离群

**下方 残差 -26.7 ｜ depth 79 ｜ log2U 40.6**

`Lean.Server.RequestContext._sizeOf_inst`

（未索引到源码位置）

**下方 残差 -25.9 ｜ depth 78 ｜ log2U 40.6**

`Lean.Server.RequestContext._sizeOf_1`

（未索引到源码位置）

**下方 残差 -25.4 ｜ depth 77 ｜ log2U 40.3**

`Lean.Elab.DefsParsedSnapshot._sizeOf_inst`

（未索引到源码位置）

**下方 残差 -25.1 ｜ depth 77 ｜ log2U 40.6**

`Lean.Server.FileWorker.EditableDocument._sizeOf_inst`

（未索引到源码位置）

**下方 残差 -24.7 ｜ depth 77 ｜ log2U 41.0**

`Lean.Elab.DefViewElabHeader._sizeOf_inst`

（未索引到源码位置）

**下方 残差 -24.6 ｜ depth 76 ｜ log2U 40.3**

`Lean.Elab.DefsParsedSnapshot._sizeOf_1`

（未索引到源码位置）

## 6. 给分析者的提示

- **斜率与 r 是主结论**，可与论文的 ≈1 bit/层 直接对照。
- **第 3 节的分段斜率**回答"自相似是否成立"：若各区间的斜率接近，说明放大倍率与层级无关。
- **第 5.1 节**是最有信息量的部分：离群点按命名空间聚集，说明偏离来自**模块级的写法**而非个别声明。
- **第 5.4 节**给出离群点的 Lean 源码片段——这是回答「为什么偏离」的直接材料。
- 需要具体某条声明的细节时，再按需从 `measures.jsonl.gz` 里 grep，不要把整份数据喂给模型。

## 7. 关于「为什么」的诚实边界

本报告能回答的问题与不能回答的问题：

| 问题 | 本报告能否回答 | 依据 |
|---|---|---|
| 斜率是多少？ | ✅ | 第 2 节的回归 |
| 斜率在不同层级是否一致？ | ✅ | 第 3 节分段回归 |
| 哪些声明偏离最大？ | ✅ | 第 5.1–5.3 节 |
| 偏离是否按模块聚集？ | ✅ | 第 5.1 节 |
| **偏离的数学原因是什么？** | ⚠️ 部分 | 5.4 节给了源码片段，但**名称反查不可靠**，需人工核对 |
| **这些偏离意味着什么样的「更好定义」？** | ❌ | 需要数学判断，本报告不涉及 |

**已知的最有价值线索**：第 5.1 节的模块聚类是**可靠**的（它只依赖声明名，不依赖源码反查），
所以"某些数学领域的压缩签名系统性偏离"这个结论是站得住的。
