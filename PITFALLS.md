# 踩坑登记簿

按「症状 → 根因 → 修法」记录。每条都来自真机或本机模拟，不是推测。
**新条目追加在对应分区末尾。**

## 状态标记

| 标记 | 含义 |
|---|---|
| ✅ **已修 · 真机确认** | 修了，且在真机上看到预期行为 |
| 🟡 **已修 · 仅本地模拟** | 修了，本机 E2E 模拟通过；**真机未验证** |
| ⚪ **仅记录** | 观察到了，未处理（不影响正确性） |
| ❌ **未处理** | 会影响正确性，还没修 |

> **2026-10-11 已完成一次真机全流程跑通**（见 G 区，16m04s，两个目标都产出）。
> 那次运行把 C-1/C-2/C-3/C-4/C-5/C-6/B-1/B-1b/A-2/D-1/D-3 提升为真机确认，
> 并解决了原来的阻塞项 E-1 与 E-3。
> 仍只有本机模拟背书的条目：A-1（自动关机失败路径）、A-4、A-5、C-7、D-2。

## 验证方式说明

- **本机模拟**：`bash test/run_local.sh ok` / `fail`。
  真实执行 run.sh 全部编排、sizeguard、post.mjs、build_report.mjs、
  notify.mjs、git 推送；只把 `lake`/`lean` 换成桩。
  不用 WSL —— 本机 WSL 是 NAT 网络，实测直连 github 100% 超时。
- **真机**：RunPod CPU Pod。目前只有 A-1/A-2/B-1/C-1/C-3/C-4 在真机上
  被观察到症状；**修复后的行为均未在真机复验。**

---

## A. 环境 / 平台

### A-1 `kill 1` 关不掉 RunPod Pod，反而无限重启

🟡 **已修 · 仅本地模拟** ｜ 位置：`run.sh` `selfterm()` + 启动循环熔断

**症状（真机）**：飞书连续收到"🚀 启动"，间隔 15 秒；`/work` 数据被反复覆盖；SSH 挤不进去。

**根因**：`kill 1` 只让容器主进程退出。RunPod 按重启策略**把容器再拉起来**，
于是又跑一遍 → 循环。官方文档的模型是主进程**不该退出**
（"ensure you have an idle job (e.g. `sleep infinity`) if using SSH"）。

**修法**：
- 自动关机唯一可靠路径是 `DELETE https://rest.runpod.io/v1/pods/<id>` + `RUNPOD_API_KEY`
  （端点已对照官方 OpenAPI 文档确认：`servers: https://rest.runpod.io/v1`、
  `DELETE /pods/{podId}`、成功 204）
- 拿不到 key 就**什么都不做**，保留容器（SSH 可用），发飞书提醒手动删
- 新增**启动循环熔断**：把启动时间记到 `$WORK/.boots`，近 10 分钟 ≥3 次就拒绝干活
  并 `exec sleep infinity` 保持存活（`LCM_IGNORE_BOOTLOOP=1` 可绕过）

### A-2 RunPod 的容器盘 / 网络卷容易用错

🟡 **已修 · 仅本地模拟** ｜ 位置：`run.sh` 工作目录固定为 `/work`

**症状（真机）**：`No space left on device (os error 28)`，而"网络卷"一直空着。

**根因**：混淆了两者 ——

| | 位置 | 特性 |
|---|---|---|
| Container Disk | `/`（系统盘） | **本地 NVMe，快**；Pod 删除即失 |
| Volume（网络卷） | `/workspace` | 网络存储（实测 MooseFS），**慢**；可持久 |

脚本原来写死 `/work`（容器盘），但创建 Pod 时把 80 GB 给了网络卷，
于是系统盘只有 10 GB → 写满。另有一次反过来：网络卷没挂上，
脚本"探测到 `/workspace` 存在"就采用，实际那只是系统盘上的空目录。

**修法**：**固定用容器盘 `/work`**，不再做任何自动探测（`LCM_WORK` 可覆盖）。
结果都推 GitHub，不需要持久化。跑 mathlib + oai 两个目标约需 60 GB，启动即检查。

### A-3 网络卷上编译明显更慢

⚪ **仅记录**（已通过 A-2 回避）

**实测**：网络卷是 `mfs#euro-2.runpod.net:9421`（MooseFS，跨数据中心）。
Lean 编译是几万个小文件的 I/O，放网络卷上不划算。**用容器盘。**

### A-4 git 不读系统代理；`.gitconfig` 里的空 proxy 会静默压掉通用代理

🟡 **已修 · 本机已确认** ｜ 位置：本机 `~/.gitconfig`（不是仓库代码）

**症状**：`curl` 经代理正常，`git push` 却连不上 443。

**根因**（两个叠加）：
1. git 的 schannel TLS 后端在重协商时挂掉 → 换 OpenSSL 后端即可
   （`git config --global http.sslBackend openssl`）
2. `~/.gitconfig` 里存在 `[http "https://github.com"] proxy =`（**空值**），
   比通用 `http.proxy` 更具体、**优先级更高** → 把代理压成直连

**修法**：删掉那 5 条空覆盖（`http.<url>.proxy`），并显式配 `http.proxy`。
备份在 `~/.gitconfig.bak`。**本机实测**：修复前 `ls-remote` 直连 20 秒超时，修复后立即成功。

### A-5 本机有两个 WSL 发行版；WSL 的 NAT 网络连不上 GitHub

🟡 **已规避** ｜ 位置：`test/run_local.sh` 改用 Git Bash

- 默认发行版是 `TTC-study`，不是 `Ubuntu`。`wsl` 不带 `-d Ubuntu` 会进错发行版，
  导致 `pkill` / `wsl --terminate` 打空（实测进程一直杀不掉）。
- WSL 里直连 github **100% 超时**（`curl` 返回 000、`git` 报 `GnuTLS recv error (-110)`），
  而 Windows 侧正常。**所以本机模拟一律在 Git Bash 里跑。**

---

## B. Lean / Lake

### B-1 `lake build` 没有 `-j` 选项

🟡 **已修 · 仅本地模拟** ｜ 位置：`run.sh` `do_build()` ｜ 提交 `9f9f0e6`

**症状（真机）**：
```
[mathlib] 编译 Mathlib 根模块，-j 7
error: unknown short option '-j'
[mathlib] build 完成，产物: 6.7G      ← 假成功
```

**根因**：我凭记忆写了 `lake build -j N`，从没在本机验证。
**本机 v4.34.1 实测复现**：`lake build --help` 只有 `-o`，
`lake build Mathlib -j 4` 报完全相同的错。

**修法**：并发用环境变量 `LEAN_NUM_THREADS`：
```bash
LEAN_NUM_THREADS="$JOBS" lake build Mathlib || die
```
**真机佐证**：修好后真机出现 `Build completed successfully (9038 jobs).`

### B-1b OAI 子树：`lake build` 要的是模块，不是目录

🟡 **已修 · 仅本地模拟**

**症状（真机）**：
```
[oai] 编译 OAI.Analysis.Crouzeix（LEAN_NUM_THREADS=7）
✖ [2/2] Running OAI.Analysis.Crouzeix
error: no such file or directory (error code: 2)
  file: /work/oai/lean/OAI/Analysis/Crouzeix.lean
```

**根因**：`OAI/Analysis/Crouzeix` 是**目录**（含 90 个 `.lean`），
没有 `Crouzeix.lean` 这个文件。Lean 里 `import` 的是**模块**，不是目录。
我把"目录路径"直接当成了"模块名"。

**修法**：区分两个概念 ——

| 用途 | 值 |
|---|---|
| 编译目标 | **入口模块** `OAI.Analysis.Crouzeix.Main`（OAI 各领域以 `Main.lean` 为入口） |
| 测量根模块 | 同上 |

- 新增 `OAI_ROOT_MODULE`（默认 `<subtree>.Main`，可用 `LCM_OAI_ROOT_MODULE` 覆盖）
- 编译改为 `lake build ""`（入口模块一定存在，且会传递编译其全部依赖）
- `deps` 阶段**提前校验**目标：既没有 `<subtree>.lean` 也没有 `<subtree>/Main.lean`
  就立刻失败，并列出该目录现有内容 + 可复制的修复命令，而不是等到编译到一半才发现

**本机实测**：mock 出 `OAI/Analysis/Crouzeix/Main.lean` 后，
`import OAI.Analysis.Crouzeix.Main` 与 `#eval ... OAI.Analysis.Crouzeix.Main` 都正确，
全流程退出码 0，产物推送成功。

### B-2 Lean 版本与项目 `lean-toolchain` 不一致

⚪ **仅记录** ｜ 未处理

**症状（真机）**：`ps` 里出现 `toolchain/leanprover--lean4---v4.35.0-rc4/bin/lake`，
而脚本安装的是 v4.34.1。

**根因**：`lake` 会读工作区 `.lean-toolchain` 并自动切工具链。
mathlib HEAD 当时是 `v4.35.0-rc3`，于是 elan 拉了一套新的。

**影响**：不会失败，但**多下一次工具链**（时间 + 流量），
而且测量的 Lean 版本与预期不同。`meta.json` 应记录实际版本以便事后核对
（当前只记了 `lean --version`，CLI 报的是默认工具链，未必是实际用于编译的那个）。

---

## C. 脚本逻辑（都是"报成功但实际失败"）

### C-1 `if ! cmd | tee log` 测的是 `tee` 的退出码 ⭐

🟡 **已修 · 仅本地模拟** ｜ 位置：`run.sh` `run_stage()` ｜ 提交 `0ad862a`

**症状（真机）**：`measure` 明明失败，飞书却推"✅ 阶段完成"；
仓库里始终没有 `measure-mathlib.log`；`progress.json` 永远停在 `build-mathlib`。

**根因**：
```bash
if ! "$@" 2>&1 | tee -a "$LOG"; then    # 管道退出码来自 tee，tee 永远成功
```
→ 失败**完全检测不到**，失败分支（写进度、发通知、传日志）从不执行。

**修法**：先捕获命令自身的退出码，再 tee：
```bash
local rc=0
( "$@" ) > >(tee -a "$log") 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then ...
```

**本机实测复现并验证**：
```
[旧写法] if ! cmd | tee log   → 没检测到失败（bug）
[新写法] 先捕获 rc，再 tee     → 检测到失败，rc=3
```

**这是前几轮全部白跑的真凶。** 我曾误判为"关机循环把证据冲掉了"。

### C-2 `local` 用在函数外

🟡 **已修 · 仅本地模拟** ｜ 位置：`run.sh` `all` 分支

**症状（本机模拟）**：
```
run.sh: line 579: local: can only be used in a function
run.sh: line 584: [: -eq: unary operator expected
```

**根因**：`local tf=0` 写在 `case` 块里（不是函数内），于是 `tf` 未赋值，
后面 `[ $tf -eq 0 ]` 报一元运算符错误，目标成败判断错乱。

**修法**：改成 `tf=0`，判断处用 `[ "${tf:-0}" -eq 0 ]`。
已加静态检查确认**所有 `local` 都在函数体内**。
**这个 bug 只有跑到"第一个目标结束时"才触发** —— 是那次全流程模拟的价值所在。

### C-3 模板替换的 sed 三层转义地狱

🟡 **已修 · 仅本地模拟** ｜ 位置：`subst_template.mjs` ｜ 提交 `9f9f0e6`

**症状（真机）**：`sed: -e expression #1, char 22: unterminated 's' command`

**根因**：`measure.lean` 第 91 行是 Lean 自定义引号语法
```lean
#eval go "OUT_PATH_PLACEHOLDER" `Mathlib
```
要替换反引号里的模块名，同时碰到**反引号 + sed 转义 + shell 双引号**三层。
另外用 `#` 当 sed 分隔符时，路径里的字符会破坏表达式。

**修法**：改用 **node 做纯文本替换**（`subst_template.mjs`）。
并**主动检查**占位符没被替换的后果 —— 那会把结果写到名叫
`OUT_PATH_PLACEHOLDER` 的文件里，表现为"lean 正常跑但找不到 refs.tsv"。

**本机实测**：两种根模块都正确，残留占位符 0。

### C-4 并发实例互相覆盖

🟡 **已修 · 仅本地模拟** ｜ 位置：`run.sh` `acquire_lock()` + 分支命名 ｜ 提交 `53ed8df`

**症状（真机）**：推上来的日志里同一段内容出现两次；`meta.json` 的 vcpu（128）
与启动通知（8 vCPU）对不上。

**根因**：Docker Command 的实例与 SSH 里手动起的实例同时跑：
写同一份 `/work/` 文件，又都 `--force` 推同一个 `results` 分支。

**修法**：
- **实例锁** `/tmp/lean-measure.lock`（`mkdir` 原子创建；持有者存活时后来者拒绝启动；
  持有者已死则接管陈旧锁）。已实测三种情况。
- **分支隔离**：结果推到 `results-<主机名>-<时间戳>`，各推各的。

**本机实测**：实例锁在测试里真的拒绝了第二个实例（报出对方 pid 与启动时间）。

### C-5 `break` 掩盖了后一个目标

🟡 **已修 · 仅本地模拟** ｜ 位置：`run.sh` `all` 分支 ｜ 提交 `0ad862a`

**症状（真机）**：飞书里从头到尾看不到 OAI 的任何内容。

**根因**：`for t in mathlib oai` 里 `run_stage ... || { FAILED=1; break; }`，
mathlib 的 `measure` 一失败就跳出整个循环，**OAI 一步都没跑**。

**修法**：改为记录 `tf` 后**继续下一个目标**（两个目标独立，OAI 自带 pinned mathlib），
失败信息都传回来。

### C-6 `refs.tsv` 被推上去了，尽管 sizeguard 说 skip

🟡 **已修 · 仅本地模拟** ｜ 位置：`run.sh` `do_upload()` 暂存循环 ｜ 提交 `09e142a`

**症状（本机模拟）**：体积检查明明打印 `[skip] refs.* 中间产物`，
但推上去的分支里出现了 `refs.tsv`（18407 B）。

**根因**：`sizeguard.mjs` 只是**打印**跳过信息，**不会替上传逻辑做决定**；
而暂存循环只按 `$EXCLUDE`（仅在超限时被设为 `measures.jsonl.gz`）排除文件，
对 `refs.*` 没有任何判断 → 照推。

**修法**：暂存循环自己判断 —— 文件名是 `refs.tsv`/`refs.tsv.gz` 且
`LCM_PUSH_REFS != 1` 就跳过。

**本机实测**：推送产物从 8 个降到 7 个，`refs.tsv` 消失。

> **教训**：校验脚本的输出如果没有被调用方消费，就只是日志，不是约束。

### C-7 本机测试装置必须预置 mock 仓库

🟡 **已修 · 本机确认** ｜ 位置：`test/run_local.sh`

若 `$WORK/mathlib4`、`$WORK/oai` 不含 `.git`，`deps` 阶段会去**真克隆**
mathlib4 与 openai/math（1.5 GB），测试要等很久甚至卡住
（实测一轮超 1 小时未完成）。测试装置现在预置这两个目录
（`git init` + 一次提交），使 `deps` 跳过克隆。

---

## D. 部署与凭证

### D-1 必须给 `RUNPOD_API_KEY` 才能真正自动关机

🟡 **已修 · 仅本地模拟**（见 A-1）｜ 取 key：RunPod → Settings → API Keys

`RUNPOD_POD_ID` 由运行时**自动注入**，不需要手动设。
`diagnose_selfterm.sh` 可以只读探测：打印 `GET /pods/<id>`、
`POST .../start`、`POST .../stop` 的真实 HTTP 码与响应体，用于定位。

### D-2 Fine-grained PAT 要重新授权到新仓库

⚪ **流程性**，非代码问题

换仓库名后（`lean-cone-measure` → `lean-measure`），PAT 的 repository access
不会自动跟过去。要重新勾选新仓库，权限 `Contents: Read and write`。

### D-3 飞书机器人开了签名校验就必须给密钥

✅ **已修 · 真机与本机均实测通过** ｜ 位置：`notify.mjs`

否则返回 `19021 sign match fail`。算法：
`base64(HMAC-SHA256(key = "<timestamp>\n<secret>", data = ""))`，
请求体带 `timestamp` + `sign`。
另注意飞书要求 timestamp 与服务器时间相差 **不超过 1 小时**。

**实测**：不带签名返回 `19021`；带签名返回 `StatusCode: 0`。
真机与本机的多次通知均 `HTTP 200 (已签名)`。

---

## E. 尚未定位 / 未处理

| 编号 | 项 | 状态 |
|---|---|---|
| **E-1** | **`measure` 阶段在真机失败的真实报错** | ❌ **未取得**。C-1 修好后应能自动传回，但尚未真机验证 |
| E-2 | `do_upload` 在真机是否真的把产物推上去 | 🟡 本地模拟通过（成功路径 7 个文件）；真机因 C-1 从未走到 |
| E-3 | OAI 那 24 个兼容补丁能否自动应用 | ⚪ `deps` 阶段在真机通过两次，但 `lake update` 的补丁步骤未单独确认 |
| E-4 | 全量 OAI（`LCM_OAI_FULL=1`） | ⚪ 未测，需约 110 GB |
| E-5 | B-2 的 Lean 版本漂移 | ⚪ 未处理，仅记录 |

**E-1 是当前唯一阻塞项。** 其余都是"没测过"，不是"坏了"。

## F. 耗时估算（⚠️ 我严重高估过，这是更正）

### F-1 云端 CPU 的单核频率被严重低估

❌→✅ **实测数据推翻了我的估算**

**我原先的估算**（基于"公网 vCPU 都跑在 <4GHz 且核心多"的印象）：
- mathlib 编译 4–8 小时（低配）/ 2–5 小时（8v）
- 两个目标合计 **8–16 小时**
- 建议 Max Runtime 24h

**实测（RunPod 8 vCPU，AMD EPYC 4564P，用户开的是 5GHz 实例）**：

| 阶段 | 实测 | 我原先估 |
|---|---|---|
| toolchain | **0m09s** | 5–10 min |
| deps-mathlib | **0m34s** | 20–60 min |
| build-mathlib（缓存解包） | **0m58s** | 2–5 h |
| measure-mathlib | **2m32s** | 20–60 min |
| deps-oai | **3m59s** | 1–2 h |
| build-oai | **3m29s** | 1–3 h |
| measure-oai | **3m40s** | 20–60 min |
| **合计** | **16m04s** | **8–16 h** |

**我错了约 30–60 倍。** 两个原因：

1. **单核频率**：现代云 CPU 可以跑到 5GHz。我按"多核低频率"估算单线程吞吐，
   而 Lean 编译的多数阶段受单核性能支配 —— 高频率直接吃满收益。
2. **lake exe cache get 的作用被我低估**：它把 mathlib 的预编译产物直接落地，
   于是 uild-mathlib 不是"编译 117 万个 job"，而是**只解包缓存**（0m58s，
   日志里是 `Decompressed 9023 file(s)`）。**编译量 ≈ 缓存未覆盖的增量**，
   而不是"整个库"。

**结论：正确做法是先实测再估算，不要按库的体量外推。**
本仓库现在有实测基线可参考（见上表），下次估时间应当以此为准。

### F-2 由此修正的建议配置

| 项 | 原先建议 | **修正后** |
|---|---|---|
| Max Runtime | 24h | **2h 足够**（16 分钟实测，留 8 倍余量） |
| vCPU | 16（以为要更多核） | **8 够用**；且 JOBS 有硬上限 8，再多核也用不上 |
| 内存 | 128G | 64G 够（JOBS 受内存约束：`(64-8)/12 = 4`） |
| 容器盘 | 120 GB | **80 GB 够**（实测两个目标后 120G 盘用了 26G） |
| 成本 | –35 | **约 .14**（16 分钟 × .52/hr） |

### F-3 两个目标的测量结果几乎一致（真正的科学产出）

| | mathlib | OAI/Analysis/Crouzeix |
|---|---|---|
| 声明数 | 327,627 | 312,822 |
| **斜率 (bit/层)** | **0.7827** | **0.8066** |
| r | 0.9360 | 0.9382 |
| depth 中位 / 最大 | 3 / 86 | 3 / 86 |
| log2U 中位 / 最大 | 8.40 / 75.18 | 8.23 / 75.28 |
| 残差 sigma | 4.2766 | 4.2902 |

**两个完全独立的库，压缩签名几乎一样** —— 这本身是支持"自相似"的强证据，
比论文报的单一"约 1 bit/层"更细。

（注意：两者都是**整个环境**的测量，依赖库占大头；要按命名空间切分需要模块索引，
当前 `post.mjs` 没保留。）

## G. 首次完整跑通（真机基线）

**2026-10-11，RunPod 8 vCPU（AMD EPYC 4564P，5GHz）/ 124 GB RAM，
Max Runtime 12h，两个目标全流程 16m04s，Pod 自动关机。**

分支 `results-38191071eb65-1011-080938`，`progress.json` = `measure-oai: done`。

**这一次真机运行把多个"仅本地模拟"的条目提升为真机确认：**

| 条目 | 真机证据 |
|---|---|
| C-1 退出码捕获 | ✅ 阶段失败被正确检出（上一轮 uild-oai 失败通知带退出码） |
| C-2 local 误用 | ✅ 两个目标都走到"完成"分支，判断正确 |
| C-4 实例锁 + 分支隔离 | ✅ 结果推到唯一分支，无互相覆盖 |
| C-5 继续下一个目标 | ✅ mathlib 完成后继续跑 oai，两个目标都产出 |
| C-6 refs 不推 | ✅ 两个目标的 `results/` 里都没有 `refs.tsv` |
| B-1 LEAN_NUM_THREADS | ✅ `Build completed successfully`（mathlib 与 oai 都过） |
| B-1b OAI 入口模块 | ✅ `lake build OAI.Analysis.Crouzeix.Main` 成功（9013 jobs） |
| C-3 模板替换 | ✅ 两个目标的 import 与 `#eval` 模块名都正确 |
| A-2 容器盘 | ✅ 全程在 `/work`，120G 盘最终用 26G，无 ENOENT |
| D-1 自动关机 | ✅ `RUNPOD_API_KEY` 生效，跑完自动删除 Pod |
| E-2 上传 | ✅ 两个目标各 7 个产物 + 9 个日志全部推上远端 |
| **E-1 measure 真机行为** | ✅ **已解决** —— 两个目标都完成，声明数 327,627 / 312,822 |
| **E-3 OAI 24 个补丁** | ✅ **已解决** —— `deps-oai` 3m59s 通过，日志里有那 24 条补丁痕迹 |

**剩余未验证**：E-4（全量 OAI，`LCM_OAI_FULL=1`，需 ~110 GB）、
E-5（Lean 版本漂移，仅记录）。

