# lean-measure

在 RunPod CPU Pod 上测量 Lean 库的**压缩签名**，按 [arXiv:2603.20396](https://arxiv.org/abs/2603.20396) §3 的口径：

| 量 | 含义 |
|---|---|
| `depth(u)` | 到 primitive（无定义体的常量）的**最长**路径 |
| `wrapped(u)` | 声明的 token 数（Lean parser 计） |
| `unwrapped(u)` | 展开到 primitive 后的加权长度，`Σ wᵢ·\|vᵢ\|`，primitive = 1 |

输出每个声明的 `depth` / `log2U`，以及全库回归 `log2(unwrapped) = a·depth + b`。

## 用法

RunPod 建 **CPU Pod**，镜像 `ubuntu:24.04`，Container Disk **120 GB**，**不要网络卷**（容器盘是本地 NVMe，快得多）。

Container Start Command：

```bash
bash -c "curl -fsSL https://raw.githubusercontent.com/lxingrui/lean-measure/main/bootstrap.sh -o /tmp/b.sh && bash /tmp/b.sh"
```

环境变量（**只有凭证是必需的**）：

| 变量 | 必需 | 说明 |
|---|---|---|
| `GITHUB_TOKEN` | ✅ | Fine-grained PAT，`Contents: Read and write`，只授权本仓库 |
| **`RUNPOD_API_KEY`** | ✅ | **自动关机用**，见下 |
| `FEISHU_WEBHOOK` | 可选 | 飞书自定义机器人 webhook |
| `FEISHU_SECRET` | 可选 | 机器人开了签名校验时必填 |

### 为什么必须要 `RUNPOD_API_KEY`

⚠️ **`kill 1` 关不掉 Pod。** 它只是让容器主进程退出，而 RunPod 会按重启策略
**把容器再拉起来** —— 结果是**无限循环重启**（实测每 15 秒一轮），不是关机。

唯一可靠的自动关机方式是调 RunPod API **删除 Pod**。所以：

1. 打开 https://www.runpod.io/console/user/settings → **API Keys** → 新建
2. 作为环境变量 `RUNPOD_API_KEY` 加到 Pod 上

`RUNPOD_POD_ID` 由 RunPod 运行时自动注入，**不需要你设**。

> 不想给这个 key，就在 RunPod 控制台把 Pod 的**重启策略设为不重启**，
> 这样 `kill 1` 才能真正结束它。否则脚本会明确警告并仍然尝试 `kill 1`。

### 调试时保留现场

| 变量 | 作用 |
|---|---|
| `LCM_KEEPALIVE=1` | 跑完**不关机**，Pod 保留，可以 SSH 进去查 |
| `LCM_SELFTERM=0` | 同上（语义更明确） |

**不需要设目标、子树、并发** —— 都在代码里有默认值：

| 默认 | 值 |
|---|---|
| 目标 | `mathlib,oai`（顺序跑两个） |
| OAI 子树 | `OAI/Analysis/Crouzeix` |
| 并发 | 按 vCPU 与内存自动定，`min(min(vCPU-1,8), (内存-8)/12)` |
| 看门狗 | 24 小时 |
| 跑完 | 自动关机 |

## 覆盖默认值

| 变量 | 作用 |
|---|---|
| `LCM_TARGETS` | 例如 `mathlib` 只跑一个 |
| `LCM_OAI_SUBTREE` | 换 OAI 子树 |
| `LCM_OAI_FULL=1` | 编译整个 OAI（需 ~110 GB，默认拒绝） |
| `LCM_WORK` | 换工作目录（默认 `/work`） |
| `JOBS` | 手动指定并发 |
| `LCM_DEADLINE_HOURS` | 看门狗时限，`0` 关闭 |
| `LCM_SELFTERM=0` | 关闭自动关机 |
| `LCM_RUNPOD_API_KEY` | 给了就真正删除 Pod（否则 `kill 1` 让容器退出） |
| `LCM_PUSH_REFS=1` | 连 `refs.tsv` 中间产物一起推 |
| `LCM_RESULT_BRANCH` | 指定结果分支（默认 `results-<主机名>-<时间戳>`） |

## 产物

推到 **`results-<主机名>-<时间戳>`** 分支（分支按运行实例隔离，避免并发互相覆盖）。

| 文件 | 给谁 | 说明 |
|---|---|---|
| `<目标>/report.md` | **AI** | ~6k token，含全部统计结论 |
| `<目标>/summary.json` | 机器 | 回归系数、分位数、离群计数 |
| `<目标>/measures.jsonl.gz` | 人/机器复算 | 每条声明的 depth/log2U |
| `<目标>/outliers.csv` 等 | AI | 离群点与模块聚类 |
| `logs/*.log` | 排障 | 每阶段一份 |

`measures.jsonl` 在跑完后自动 gzip，`<目标>` 为 `mathlib` / `oai`。

## 分阶段重跑

SSH 或 Web Terminal 里：

```bash
bash /app/run.sh measure     # 只重跑测量（编译产物还在）
bash /app/run.sh upload      # 只重传结果
bash /app/run.sh build       # 只重编译
```

同一台机器**只允许一个实例**：第二个会拒绝启动并告诉你占用者的 pid。

## 已知边界

- **`lake build` 没有 `-j` 选项**（v4.34.1 实测 `unknown short option '-j'`），并发由 `LEAN_NUM_THREADS` 控制。
- 抽取阶段是**单线程**的 `#eval`，589k 条声明约 20–60 分钟，`lean` 进程内存约 15 GB。
- OAI 仓库带 24 个兼容补丁，由 `lake update` 自动打；这个机制未在真机外验证过。
- 结果分支名随运行变化，飞书通知里带链接。
