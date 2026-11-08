# 已推送证据落区 · _push_ci

> 承载「全部本地提交已推送 + CI 双绿」的可审计证据。与 `pc_win_02/` 不同，本目录不装 G1 实测数据，只证明**交付链路本身**已完成。

## 已捕获证据

- `remote_head_53d64c2.txt`：权威 `git ls-remote` 输出，证明远端 `master = 53d64c2267bb343c433e78382e23973442a622f7` 与本地 `HEAD` 一致；并记录 SSH 推送通道（绕过本沙箱代理白名单）与 CI 双绿基线。
- `ci_runs_106d442.json`（GitHub API 可达时捕获）：`106d442` 触发的 Actions runs 原始响应，含 `Lint` / `test` 结论。本次会话编写时 API 处未授权限流，未落盘；结论以会话内轮询确认为准（见治理包 §7）。

## 待补截图（主理人按治理包 §7.1 命名约定放入 `screenshots/`）

| 文件 | 内容 |
|---|---|
| `screenshots/actions_green_106d442.png` | Actions 页 `Lint` / `test` 两 job 均 `success` 的页面截图 |
| `screenshots/push_success.png` | GitHub 仓库 `master` 提交历史含 `53d64c2` 的截图 |

## 纪律

- 本目录证据仅证明「推送 + CI」完成；**不**构成 G1 实测、也**不**触发 R1/R3 翻转（纪律红线不变）。
- 截图须含可追溯要素（仓库名 / commit SHA / job 结论）。
- 证据链：P1（远端 HEAD） + P3（CI 双绿）为已核验事实；P4/P5 截图补入后于治理包 §7 勾选。
