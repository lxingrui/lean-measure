# 压缩签名测量报告：mathlib OAI/Analysis/Crouzeix

> 本文件由 `build_report.mjs` 从完整数据集（327,627 条声明）计算得出。
> 原始数据是 `measures.jsonl.gz`（体积过大，不适合直接喂给模型）。
> **本报告已包含全量数据的统计结论；AI 不需要读原始数据。**

## 1. 数据集

| 量 | 值 |
|---|---|
| 声明总数 | 327,627 |
| depth 范围 | 0 – 86 |
| depth 中位 / 均值 | 3 / 10.11 |
| log2U 范围 | 0.00 – 75.18 |
| log2U 中位 / 均值 | 8.40 / 11.49 |
| log2U 分位 p10/p25/p75/p90 | 0.00 / 0.00 / 18.28 / 30.38 |

## 2. 主回归（核心结论）

```
log2(unwrapped) = 0.7827 · depth + 3.5793
n = 327627    r = 0.9360
残差 sigma = 4.2766 bit    3-sigma = ±12.8299 bit
```

**斜率 ≈ 0.78 bit/层**，即 `unwrapped ≈ 2^(0.78·depth)`，
等价于**每深入一层定义，底层展开量乘以 1.72**。

论文（arXiv:2603.20396）报的斜率是 **≈ 1 bit/层**（每层 ×2）。

## 3. 自相似性检验（按 depth 分段回归）

若「每层放大同一个常数」成立，则各 depth 区间的斜率应当一致。

| depth 区间 | 样本数 | 该区间斜率 |
|---|---|---|
| 0 – 3 | 167,433 | 2.9514 |
| 4 – 8 | 47,229 | 1.0634 |
| 9 – 15 | 26,779 | 0.6587 |
| 16 – 25 | 43,670 | 0.4508 |
| 26 – 40 | 20,386 | 0.6067 |
| 41 – 86 | 22,130 | 0.4579 |

## 4. 按 depth 的分布

| depth | 数量 | p10 | 中位 | p90 | 均值 |
|---|---|---|---|---|---|
| 0 | 118698 | 0.00 | 0.00 | 2.00 | 0.45 |
| 1 | 21315 | 3.00 | 5.29 | 6.79 | 5.16 |
| 2 | 16141 | 5.04 | 6.69 | 9.09 | 6.92 |
| 3 | 11279 | 5.83 | 8.07 | 10.58 | 8.18 |
| 4 | 9005 | 6.95 | 9.58 | 12.72 | 9.75 |
| 5 | 13910 | 8.58 | 10.47 | 13.31 | 10.83 |
| 6 | 10736 | 8.74 | 11.98 | 15.98 | 12.21 |
| 7 | 7284 | 9.22 | 12.61 | 17.18 | 12.93 |
| 8 | 6294 | 9.71 | 13.70 | 18.72 | 13.96 |
| 9 | 5927 | 10.89 | 15.43 | 20.70 | 15.59 |
| 10 | 4536 | 11.63 | 15.94 | 21.22 | 16.22 |
| 11 | 3813 | 12.35 | 17.52 | 23.14 | 17.65 |
| 12 | 3740 | 12.14 | 16.98 | 23.97 | 17.61 |
| 13 | 3083 | 13.29 | 18.61 | 25.13 | 19.04 |
| 14 | 3186 | 12.91 | 18.03 | 25.62 | 18.82 |
| 15 | 2494 | 13.38 | 18.27 | 26.61 | 19.28 |
| 16 | 7919 | 14.68 | 18.32 | 21.18 | 18.72 |
| 17 | 8557 | 16.05 | 18.33 | 21.73 | 19.14 |
| 18 | 3194 | 14.67 | 19.16 | 25.94 | 19.76 |
| 19 | 3216 | 14.45 | 19.12 | 26.38 | 19.91 |
| 20 | 3698 | 15.15 | 19.32 | 26.78 | 20.1 |
| 21 | 3185 | 15.20 | 20.14 | 28.29 | 21.12 |
| 22 | 4651 | 17.62 | 19.98 | 27.05 | 21.16 |
| 23 | 2833 | 17.99 | 22.40 | 29.23 | 22.98 |
| 24 | 4404 | 17.13 | 18.88 | 27.22 | 20.92 |
| 25 | 2013 | 18.60 | 24.38 | 30.72 | 24.57 |
| 26 | 1542 | 19.54 | 25.88 | 32.75 | 26.17 |
| 27 | 1209 | 20.94 | 27.53 | 34.78 | 27.79 |
| 28 | 1268 | 22.59 | 27.45 | 35.12 | 28.19 |
| 29 | 1403 | 19.41 | 25.96 | 35.20 | 27.02 |
| 30 | 1336 | 19.05 | 26.34 | 34.18 | 26.94 |
| 31 | 1196 | 20.70 | 27.48 | 35.85 | 28.02 |
| 32 | 1064 | 20.76 | 28.33 | 38.68 | 29.07 |
| 33 | 1049 | 24.33 | 28.61 | 37.62 | 29.66 |
| 34 | 952 | 25.38 | 29.49 | 38.80 | 30.64 |
| 35 | 979 | 26.96 | 31.07 | 39.97 | 32.05 |
| 36 | 1917 | 26.96 | 31.49 | 38.58 | 31.82 |
| 37 | 1515 | 27.96 | 31.61 | 41.26 | 32.98 |
| 38 | 2400 | 29.29 | 31.18 | 37.27 | 32.38 |
| 39 | 1430 | 28.96 | 33.19 | 43.87 | 34.63 |
| 40 | 1126 | 29.28 | 34.30 | 41.80 | 35.2 |
| 41 | 947 | 29.81 | 34.55 | 41.79 | 35.63 |
| 42 | 1284 | 30.94 | 34.34 | 41.82 | 35.62 |
| 43 | 1282 | 32.15 | 34.61 | 42.29 | 35.89 |
| 44 | 2404 | 32.70 | 34.41 | 39.98 | 35.36 |
| … | 共 87 个 depth 取值，完整表见 depth_stats.csv | | | | |

## 5. 离群点

| 侧 | 数量 | 占比 |
|---|---|---|
| 上方（展开异常大，残差 > +3σ） | 3,054 | 0.932% |
| 下方（展开异常小，残差 < −3σ） | 461 | 0.141% |

### 5.1 离群点成模块聚集（不是随机散布）

| 模块（前两级命名空间） | ↑上方 | ↓下方 | 上方平均残差 | 下方平均残差 |
|---|---|---|---|---|
| `AlgebraicGeometry.Scheme` | 287 | 0 | 16.5 | — |
| `_private.Mathlib` | 213 | 26 | 16.1 | 14.2 |
| `CategoryTheory.Limits` | 190 | 0 | 14.3 | — |
| `CategoryTheory.Pseudofunctor` | 162 | 0 | 16.8 | — |
| `Lean.Elab` | 0 | 82 | — | 17.8 |
| `CategoryTheory.Functor` | 72 | 0 | 15.7 | — |
| `Mathlib.Tactic` | 1 | 56 | 13.2 | 13.9 |
| `CategoryTheory.Abelian` | 56 | 0 | 16.8 | — |
| `_private.Lean` | 0 | 55 | — | 14.5 |
| `CategoryTheory.MonoidalCategory` | 47 | 0 | 14.3 | — |
| `CategoryTheory.Triangulated` | 45 | 0 | 16.5 | — |
| `CategoryTheory.GrothendieckTopology` | 40 | 0 | 14.1 | — |
| `Std.Time` | 38 | 0 | 15.1 | — |
| `CategoryTheory.Localization` | 34 | 0 | 16.8 | — |
| `Lean.Meta` | 5 | 28 | 13.2 | 13.9 |
| `CategoryTheory.ShortComplex` | 27 | 0 | 13.7 | — |
| `CategoryTheory.Grothendieck` | 26 | 0 | 15.5 | — |
| `CategoryTheory.Oplax` | 26 | 0 | 14.3 | — |
| `CategoryTheory.Pretriangulated` | 24 | 0 | 18.1 | — |
| `CategoryTheory.Sheaf` | 24 | 0 | 14.6 | — |
| `CochainComplex.HomComplex` | 23 | 0 | 16.9 | — |
| `CategoryTheory.OverPresheafAux` | 22 | 0 | 15.0 | — |
| `CategoryTheory.FreeBicategory` | 22 | 0 | 14.4 | — |
| `Polynomial.Gal` | 21 | 0 | 24.1 | — |
| `SSet.Truncated` | 21 | 0 | 14.2 | — |
| `AlgebraicGeometry.PresheafedSpace` | 20 | 0 | 16.2 | — |
| `Polynomial.SplittingField` | 20 | 0 | 16.6 | — |
| `CategoryTheory.Lax` | 20 | 0 | 14.0 | — |
| `FiniteField.instFieldExtension` | 19 | 0 | 15.8 | — |
| `Lean.Language` | 0 | 19 | — | 16.7 |
| `SheafOfModules.Presentation` | 18 | 0 | 16.0 | — |
| `CyclotomicField.instField` | 18 | 0 | 16.4 | — |
| `SheafOfModules.QuasicoherentData` | 17 | 0 | 16.1 | — |
| `CategoryTheory.CatEnrichedOrdinary` | 16 | 0 | 18.0 | — |
| `Aesop.Script` | 0 | 16 | — | 17.5 |
| `PresheafOfModules.Sheafify` | 15 | 0 | 16.5 | — |
| `CategoryTheory.CostructuredArrow` | 15 | 0 | 15.6 | — |
| `PresheafOfModulesOfCommRing.Derivation` | 15 | 0 | 15.8 | — |
| `CategoryTheory.Over` | 15 | 0 | 14.5 | — |
| `SSet.prodStdSimplex` | 15 | 0 | 13.7 | — |

### 5.2 上方离群（展开异常大）极端例子

| 残差 | depth | log2U | 声明 |
|---|---|---|---|
| +31.9 | 49 | 73.8 | `AlgebraicGeometry.Scheme.IdealSheafData.subschemeObjIso` |
| +31.7 | 51 | 75.2 | `_private.Mathlib.NumberTheory.Cyclotomic.Basic.0.CyclotomicRing.instIsFractionRingCyclotomicFieldOfIsDomainOfNeZeroCast.match_1` |
| +30.1 | 16 | 46.2 | `_private.Mathlib.CategoryTheory.Sites.Coherent.SequentialLimit.0.CategoryTheory.coherentTopology.cone` |
| +30.1 | 44 | 68.1 | `_private.Mathlib.AlgebraicGeometry.Limits.0.AlgebraicGeometry.isOpenImmersion_sigmaDesc_aux.match_1_2` |
| +30.0 | 51 | 73.5 | `AlgebraicGeometry.Scheme.kerAdjunction` |
| +29.6 | 51 | 73.1 | `AlgebraicGeometry.IsClosedImmersion.overEquivIdealSheafData` |
| +29.5 | 30 | 56.6 | `CategoryTheory.Abelian.FreydMitchell.functor` |
| +28.4 | 46 | 68.0 | `AlgebraicGeometry.Scheme.Hom.normalizationObjIso` |
| +28.3 | 29 | 54.6 | `_private.Mathlib.CategoryTheory.Abelian.FreydMitchell.0.CategoryTheory.Abelian.FreydMitchell.H` |
| +28.1 | 49 | 70.0 | `AlgebraicGeometry.Scheme.IdealSheafData.inclusion` |
| +28.1 | 28 | 53.6 | `CategoryTheory.Abelian.FreydMitchell.instRingEmbeddingRing` |
| +28.0 | 50 | 70.7 | `AlgebraicGeometry.Scheme.IdealSheafData.subschemeFunctor` |
| +27.9 | 51 | 71.4 | `AlgebraicGeometry.Scheme.IdealSheafData.comapIso` |
| +27.7 | 51 | 71.2 | `Polynomial.Gal.restrictProd` |
| +27.3 | 40 | 62.1 | `AlgebraicGeometry.presentationTilde` |
| +27.2 | 51 | 70.7 | `AlgebraicGeometry.IsClosedImmersion.lift` |
| +27.1 | 50 | 69.9 | `Polynomial.Gal.restrictDvd` |
| +27.1 | 14 | 41.6 | `_private.Mathlib.CategoryTheory.Sites.Coherent.SequentialLimit.0.CategoryTheory.coherentTopology.preimage._sunfold` |
| +27.1 | 52 | 71.3 | `CyclotomicRing.algebraBase` |
| +27.0 | 52 | 71.3 | `AlgebraicGeometry.Scheme.IdealSheafData.subschemeMap` |
| +27.0 | 52 | 71.3 | `CyclotomicRing.instAlgebraCyclotomicField` |
| +26.9 | 50 | 69.6 | `instCommRingCyclotomicRing` |
| +26.8 | 47 | 67.2 | `Polynomial.instFintypeGal._aux_1` |
| +26.8 | 49 | 68.7 | `Polynomial.instMulSemiringActionGalSplittingField` |
| +26.7 | 49 | 68.6 | `AlgebraicGeometry.Scheme.IdealSheafData.comap` |

### 5.3 下方离群（展开异常小）极端例子

| 残差 | depth | log2U | 声明 |
|---|---|---|---|
| -25.9 | 79 | 39.5 | `Lean.Server.RequestContext._sizeOf_inst` |
| -25.1 | 78 | 39.5 | `Lean.Server.RequestContext._sizeOf_1` |
| -24.6 | 77 | 39.2 | `Lean.Elab.DefsParsedSnapshot._sizeOf_inst` |
| -24.3 | 77 | 39.5 | `Lean.Server.FileWorker.EditableDocument._sizeOf_inst` |
| -23.9 | 77 | 39.9 | `Lean.Elab.DefViewElabHeader._sizeOf_inst` |
| -23.8 | 76 | 39.2 | `Lean.Elab.DefsParsedSnapshot._sizeOf_1` |
| -23.5 | 76 | 39.5 | `Lean.Server.FileWorker.EditableDocument._sizeOf_1` |
| -23.4 | 75 | 38.9 | `_private.Lean.Elab.Frontend.0.Lean.Elab.IncrSnapshot._sizeOf_inst` |
| -23.2 | 76 | 39.9 | `Lean.Elab.DefViewElabHeader._sizeOf_1` |
| -23.1 | 75 | 39.2 | `Lean.Elab.DefView._sizeOf_inst` |
| -23.1 | 75 | 39.2 | `Lean.Elab.DefParsed._sizeOf_inst` |
| -23.0 | 73 | 37.7 | `Lean.Elab.Term.Context._sizeOf_inst` |
| -22.7 | 75 | 39.5 | `Lean.Server.FileWorker.EditableDocumentCore._sizeOf_inst` |
| -22.6 | 74 | 38.9 | `_private.Lean.Elab.Frontend.0.Lean.Elab.IncrSnapshot._sizeOf_1` |
| -22.5 | 73 | 38.2 | `Aesop.UnsafeQueueEntry._sizeOf_inst` |
| -22.5 | 73 | 38.2 | `Aesop.SafeRulesResult._sizeOf_inst` |
| -22.5 | 73 | 38.2 | `Aesop.SafeRuleResult._sizeOf_inst` |
| -22.3 | 74 | 39.2 | `Lean.Elab.DefView._sizeOf_1` |
| -22.3 | 74 | 39.2 | `Lean.Elab.DefParsed._sizeOf_1` |
| -22.2 | 72 | 37.7 | `Lean.Elab.Term.Context._sizeOf_1` |
| -22.0 | 74 | 39.5 | `Lean.Server.FileWorker.EditableDocumentCore._sizeOf_1` |
| -21.8 | 73 | 38.9 | `Lean.Language.Lean.HeaderParsedSnapshot._sizeOf_inst` |
| -21.8 | 72 | 38.2 | `Aesop.SafeRulesResult._sizeOf_1` |
| -21.8 | 72 | 38.2 | `Aesop.SafeRuleResult._sizeOf_1` |
| -21.8 | 72 | 38.2 | `Aesop.UnsafeQueueEntry._sizeOf_1` |

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
> 本节索引命中：**17 / 50** 条。

#### 上方离群

**上方 残差 +31.9 ｜ depth 49 ｜ log2U 73.8**

`AlgebraicGeometry.Scheme.IdealSheafData.subschemeObjIso`

`Mathlib/AlgebraicGeometry/IdealSheaf/Subscheme.lean:532`

```lean
def subschemeObjIso (U : X.affineOpens) :
    Γ(I.subscheme, I.subschemeι ⁻¹ᵁ U) ≅ ↧(Γ(X, U) ⧸ I.ideal U) :=
  I.subscheme.presheaf.mapIso (eqToIso (by simp)).op ≪≫
    (I.subschemeCover.f U).appIso _ ≪≫ Scheme.ΓSpecIso ↧(Γ(X, U) ⧸ I.ideal U)

set_option backward.isDefEq.respectTransparency false in
lemma subschemeι_app (U : X.affineOpens) : I.subschemeι.app U =
    CommRingCat.ofHom (Ideal.Quotient.mk (I.ideal U)) ≫
    (I.subschemeObjIso U).inv := by
  have := I.subschemeCover_map_subschemeι U
  simp only [glueDataObjι, Category.assoc, IsAffineOpen.isoSpec_inv_ι] at this
  replace this := Scheme.Hom.congr_app this U
```

**上方 残差 +31.7 ｜ depth 51 ｜ log2U 75.2**

`_private.Mathlib.NumberTheory.Cyclotomic.Basic.0.CyclotomicRing.instIsFractionRingCyclotomicFieldOfIsDomainOfNeZeroCast.match_1`

（未索引到源码位置）

**上方 残差 +30.1 ｜ depth 16 ｜ log2U 46.2**

`_private.Mathlib.CategoryTheory.Sites.Coherent.SequentialLimit.0.CategoryTheory.coherentTopology.cone`

`Mathlib/CategoryTheory/Filtered/Basic.lean:842`

```lean
noncomputable def cone (F : J ⥤ C) : Cone F :=
  (cone_nonempty F).some

variable {D : Type u₁} [Category.{v₁} D]

/-- If `C` is cofiltered, and we have a functor `L : C ⥤ D` with a right adjoint,
then `D` is cofiltered.
-/
theorem of_left_adjoint {L : C ⥤ D} {R : D ⥤ C} (h : L ⊣ R) : IsCofiltered D :=
  { IsCofilteredOrEmpty.of_left_adjoint h with
    nonempty := IsCofiltered.nonempty.map L.obj }
```

**上方 残差 +30.1 ｜ depth 44 ｜ log2U 68.1**

`_private.Mathlib.AlgebraicGeometry.Limits.0.AlgebraicGeometry.isOpenImmersion_sigmaDesc_aux.match_1_2`

（未索引到源码位置）

**上方 残差 +30.0 ｜ depth 51 ｜ log2U 73.5**

`AlgebraicGeometry.Scheme.kerAdjunction`

`Mathlib/AlgebraicGeometry/IdealSheaf/Subscheme.lean:770`

```lean
def kerAdjunction (Y : Scheme.{u}) : (subschemeFunctor Y).rightOp ⊣ Y.kerFunctor where
  unit.app I := eqToHom (by simp)
  counit.app f := (Over.homMk f.unop.hom.toImage f.unop.hom.toImage_imageι).op
  counit.naturality _ _ _ := Quiver.Hom.unop_inj (by ext1; simp [← cancel_mono (subschemeι _)])
  left_triangle_components I := Quiver.Hom.unop_inj (by ext1; simp [← cancel_mono (subschemeι _)])

set_option backward.isDefEq.respectTransparency.types false in
set_option backward.defeqAttrib.useBackward true in
instance : (IdealSheafData.subschemeFunctor Y).Full :=
  have : IsIso Y.kerAdjunction.rightOp.counit := by
    simp [NatTrans.isIso_iff_isIso_app, CategoryTheory.instIsIsoEqToHom]
  Y.kerAdjunction.rightOp.fullyFaithfulROfIsIsoCounit.full
```

**上方 残差 +29.6 ｜ depth 51 ｜ log2U 73.1**

`AlgebraicGeometry.IsClosedImmersion.overEquivIdealSheafData`

`Mathlib/AlgebraicGeometry/Morphisms/ClosedImmersion.lean:176`

```lean
def overEquivIdealSheafData (X : Scheme.{u}) :
    (MorphismProperty.Over @IsClosedImmersion ⊤ X)ᵒᵖ ≌ X.IdealSheafData where
  functor := (MorphismProperty.Over.forget _ _ _).op ⋙ X.kerFunctor
  inverse :=
  { obj I := .op <| .mk _ I.subschemeι inferInstance
    map {I J} h := (MorphismProperty.Over.homMk (Scheme.IdealSheafData.inclusion h.le)).op
    map_comp f g := Quiver.Hom.unop_inj (by ext1; simp) }
  unitIso := NatIso.ofComponents (fun Y ↦
    letI : IsClosedImmersion Y.unop.hom := Y.unop.prop
    ((MorphismProperty.Over.isoMk (asIso Y.unop.hom.toImage).symm).op)) fun {X Y} f ↦ by
      apply Quiver.Hom.unop_inj
      ext1
```

#### 下方离群

**下方 残差 -25.9 ｜ depth 79 ｜ log2U 39.5**

`Lean.Server.RequestContext._sizeOf_inst`

（未索引到源码位置）

**下方 残差 -25.1 ｜ depth 78 ｜ log2U 39.5**

`Lean.Server.RequestContext._sizeOf_1`

（未索引到源码位置）

**下方 残差 -24.6 ｜ depth 77 ｜ log2U 39.2**

`Lean.Elab.DefsParsedSnapshot._sizeOf_inst`

（未索引到源码位置）

**下方 残差 -24.3 ｜ depth 77 ｜ log2U 39.5**

`Lean.Server.FileWorker.EditableDocument._sizeOf_inst`

（未索引到源码位置）

**下方 残差 -23.9 ｜ depth 77 ｜ log2U 39.9**

`Lean.Elab.DefViewElabHeader._sizeOf_inst`

（未索引到源码位置）

**下方 残差 -23.8 ｜ depth 76 ｜ log2U 39.2**

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
