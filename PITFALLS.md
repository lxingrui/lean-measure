# 踩坑登记簿

按"症状 → 根因 → 修法"记录。每条都来自真机运行，不是推测。
**新条目追加在对应分区末尾。**

---

## A. 环境 / 平台

### A-1 `kill 1` 关不掉 RunPod Pod，反而无限重启

**症状**：飞书连续收到"🚀 启动"，间隔 15 秒；`/work` 数据被反复覆盖；SSH 挤不进去。

**根因**：`kill 1` 只让容器主进程退出。RunPod 按重启策略**把容器再拉起来**，
于是又跑一遍 → 循环。官方文档的模型是主进程**不该退出**
（"ensure you have an idle job (e.g. `sleep infinity`) if using SSH"）。

**修法**：
- 自动关机唯一可靠路径是 `DELETE https://rest.runpod.io/v1/pods/<id>` + `RUNPOD_API_KEY`
- 拿不到 key 就**什么都不做**，保留容器（SSH 可用），发飞书提醒手动删
- 新增**启动循环熔断**：把启动时间记到 `$WORK/.boots`，近 10 分钟 ≥3 次就拒绝干活
  并 `exec sleep infinity` 保持存活，把控制权交回给人（`LCM_IGNORE_BOOTLOOP=1` 可绕过）

### A-2 RunPod 的容器盘 / 网络卷容易用错

**症状**：`No space left on device (os error 28)`，而"网络卷"一直空着。

**根因**：混淆了两者 ——
| | 位置 | 特性 |
|---|---|---|
| Container Disk | `/`（系统盘） | **本地 NVMe，快**；Pod 删除即失 |
| Volume（网络卷） | `/workspace` | 网络存储（实测 MooseFS），**慢**；可持久 |

脚本原来写死 `/work`（容器盘），但创建 Pod 时把 80 GB 给了网络卷，
于是系统盘只有 10 GB → 写满。另有一次反过来：网络卷没挂上，
脚本"探测到 `/workspace` 存在"就采用，实际那只是系统盘上的空目录。

**修法**：**固定用容器盘 `/work`**，不再做任何自动探测。结果都推 GitHub，不需要持久化。
跑 mathlib + oai 两个目标约需 60 GB，启动即检查。

### A-3 网络卷上编译明显更慢

**实测**：网络卷是 `mfs#euro-2.runpod.net:9421`（MooseFS，跨数据中心）。
Lean 编译是几万个小文件的 I/O，放网络卷上不划算。**用容器盘。**

### A-4 git 不读系统代理；`.gitconfig` 里的空 proxy 会静默压掉通用代理

**症状**：`curl` 经代理正常，`git push` 却连不上 443。

**根因**（两个叠加）：
1. git 的 schannel TLS 后端在重协商时挂掉 → 换 OpenSSL 后端即可
   （`git config --global http.sslBackend openssl`）
2. `.gitconfig` 里存在 `[http "https://github.com"] proxy =`（**空值**），
   比通用 `http.proxy` 更具体，**优先级更高** → 把代理压成直连

**修法**：删掉那些空覆盖；TUN 关闭时给 git 显式配 `http.proxy`。

---

## B. Lean / Lake

### B-1 `lake build` 没有 `-j` 选项

**症状**：
```
[mathlib] 编译 Mathlib 根模块，-j 7
error: unknown short option '-j'
[mathlib] build 完成，产物: 6.7G      ← 假成功
```

**根因**：我凭记忆写了 `lake build -j N`，从没在本机验证。
本机 v4.34.1 实测复现（`lake build --help` 只有 `-o`）。

**修法**：并发用环境变量 `LEAN_NUM_THREADS`：
```bash
LEAN_NUM_THREADS="$JOBS" lake build Mathlib || die
```

### B-2 Lean 版本与项目 `lean-toolchain` 不一致

**症状**：`ps` 里出现 `toolchain/leanprover--lean4---v4.35.0-rc4/bin/lake`，
而脚本安装的是 v4.34.1。

**根因**：`lake` 会读工作区 `.lean-toolchain` 并自动切工具链。
mathlib HEAD 当时是 `v4.35.0-rc3`，于是 elan 拉了一套新的。

**影响**：不会失败，但**多下一次工具链**，而且测量的 Lean 版本与预期不同。
`meta.json` 里应记录实际版本以便事后核对。

---

## C. 脚本逻辑（都是"报成功但实际失败"）

### C-1 `if ! cmd | tee log` 测的是 `tee` 的退出码 ⭐

**症状**：`measure` 明明失败，飞书却推"✅ 阶段完成"；仓库里始终没有
`measure-mathlib.log`；`progress.json` 永远停在 `build-mathlib`。

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
**本机已复现并验证**（旧写法漏报 / 新写法正确捕获 `rc=3`）。

### C-2 `local` 用在函数外

**症状**：
```
run.sh: line 579: local: can only be used in a function
run.sh: line 584: [: -eq: unary operator expected
```

**根因**：`local tf=0` 写在 `case` 块里（不是函数内），于是 `tf` 未赋值，
后面 `[ $tf -eq 0 ]` 报一元运算符错误，目标成败判断错乱。

**修法**：改成 `tf=0`，判断处用 `[ "${tf:-0}" -eq 0 ]`。
已加静态检查确认**所有 `local` 都在函数体内**。

### C-3 模板替换的 sed 三层转义地狱

**症状**：`sed: -e expression #1, char 22: unterminated 's' command`

**根因**：`measure.lean` 第 91 行是 Lean 自定义引号语法
```lean
#eval go "OUT_PATH_PLACEHOLDER" `Mathlib
```
要替换反引号里的模块名，同时碰到**反引号 + sed 转义 + shell 双引号**三层。
另外用 `#` 当 sed 分隔符时，路径里的字符会破坏表达式。

**修法**：改用 **node 做纯文本替换**（`subst_template.mjs`），没有转义问题。
并且**主动检查**占位符没被替换的后果 —— 那会把结果写到名叫
`OUT_PATH_PLACEHOLDER` 的文件里，表现为"lean 正常跑但找不到 refs.tsv"。

### C-4 并发实例互相覆盖

**症状**：推上来的日志里同一段内容出现两次；`meta.json` 的 vcpu 与启动通知对不上。

**根因**：Docker Command 的实例与 SSH 里手动起的实例同时跑：
写同一份 `/work/` 文件，又都 `--force` 推同一个 `results` 分支。

**修法**：
- **实例锁** `/tmp/lean-measure.lock`（`mkdir` 原子创建；持有者存活时后来者拒绝启动；
  持有者已死则接管陈旧锁）。已实测三种情况。
- **分支隔离**：结果推到 `results-<主机名>-<时间戳>`，各推各的。

### C-5 `break` 掩盖了后一个目标

**症状**：飞书里从头到尾看不到 OAI 的任何内容。

**根因**：`for t in mathlib oai` 里 `run_stage ... || { FAILED=1; break; }`，
mathlib 的 `measure` 一失败就跳出整个循环，**OAI 一步都没跑**。

**修法**：改为记录 `tf` 后**继续下一个目标**（两个目标独立，OAI 自带 pinned mathlib），
失败信息都传回来。

### C-6 `refs.tsv` 被推上去了，尽管 sizeguard 说 skip

**症状**：体积检查明明打印 `[skip] refs.* 中间产物`，但仓库里出现了 `refs.tsv`。

**根因**：`sizeguard.mjs` 只是**打印**跳过信息，**不会替上传逻辑做决定**；
而暂存循环只按 `\`（仅在超限时被设为 `measures.jsonl.gz`）排除文件，
对 `refs.*` 没有任何判断 → 照推。

**修法**：暂存循环自己判断 —— 文件名是 `refs.tsv`/`refs.tsv.gz` 且
`LCM_PUSH_REFS != 1` 就跳过。
**教训**：校验脚本的输出如果没有被调用方消费，就只是日志，不是约束。

### C-7 本机测试装置踩的坑（不属于产品代码，但值得记）

- **WSL 不能用**：本机 WSL 是 NAT 网络，实测直连 github 100% 超时
  （curl 返回 000、git 报 `GnuTLS recv error (-110)`）。改用 **Git Bash**（走 Windows 网络栈）正常。
- **本机有两个 WSL 发行版**（`TTC-study` 是默认、`Ubuntu` 是另一个），
  `wsl` 不带 `-d Ubuntu` 会进错发行版，导致 `pkill` / `--terminate` 打空。
- 测试装置必须**预置 mock 仓库**（`\/mathlib4`、`\/oai` 已含 `.git`），
  否则 `deps` 阶段会去真克隆 mathlib4 与 openai/math（1.5 GB），测试要等很久。

---

## D. 部署与凭证

### D-1 必须给 `RUNPOD_API_KEY` 才能真正自动关机

见 A-1。取 key：RunPod → Settings → API Keys。
`RUNPOD_POD_ID` 由运行时**自动注入**，不需要手动设。

### D-2 Fine-grained PAT 要重新授权到新仓库

换仓库名后，PAT 的 repository access 不会自动跟过去。要重新勾选新仓库，
权限 `Contents: Read and write`。

### D-3 飞书机器人开了签名校验就必须给密钥

否则返回 `19021 sign match fail`。算法：
`base64(HMAC-SHA256(key = "<timestamp>\n<secret>", data = ""))`，
请求体带 `timestamp` + `sign`。
另注意飞书要求 timestamp 与服务器时间相差 **不超过 1 小时**。

---

## E. 尚未定位

| 项 | 状态 |
|---|---|
| `measure` 阶段在真机上失败的真实报错 | **未取得**。失败检测修好后应该能自动传回 |
| `do_upload` 在真机上是否真的把产物推上去 | 本地模拟通过；真机因 C-1 从未走到 |
| OAI 那 24 个兼容补丁能否自动应用 | `deps` 阶段通过两次，但 `lake update` 的补丁步骤未单独确认 |
| 全量 OAI（`LCM_OAI_FULL=1`）能否跑通 | 未测，需 ~110 GB |
