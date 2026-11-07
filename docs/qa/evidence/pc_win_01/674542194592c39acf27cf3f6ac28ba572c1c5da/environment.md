# 采集环境（客观只读读数，2026-11-07 · 纯 SHA 终版批次）

> 本文件记录**可从系统 / 引擎日志客观读到**的机器与采集条件，供 19 列人工字段核对。
> 主观判断项与受限项见 `verification.md`。数据来源：Windows CIM 只读查询、
> `powercfg /getactivescheme`、Godot 4.3 导出的 `console.log` 首部。

## 机器规格

| 项 | 实测值 | 来源 |
|---|---|---|
| 操作系统 | Windows 11 专业版 build 26100，版本 10.0.26100 | `Win32_OperatingSystem`；CSV `os_version=10.0.26100` 一致 |
| CPU | 11th Gen Intel Core i7-1185G7 @ 3.00GHz，4 核 8 线程 | `Win32_Processor` |
| 内存 | 31.75 GB | `Win32_ComputerSystem.TotalPhysicalMemory` |
| GPU 0 | Intel Iris Xe Graphics，驱动 32.0.101.6129，1920×1080 @120Hz | `Win32_VideoController` |
| GPU 1 | NVIDIA GeForce MX450，驱动 31.0.15.1747 | `Win32_VideoController` |
| 渲染设备 | `Vulkan 1.3.205 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce MX450` | 四轮 `console.log` 第 2 行，四轮一致 |
| 显示会话 | Console，会话 ID 16，`DISPLAY_SERVER=Windows`，`SCREEN_COUNT=1` | 只读会话检查 + `ROUND\|` 日志 |
| 电源方案 | 平衡（GUID `381b4222-f694-41f0-9685-ff5bb260df2e`） | `powercfg /getactivescheme` |
| 电池 | 12:19 92% → 12:29 93% → 12:34 95%，`BatteryStatus=2`（AC 供电 / 充电中） | `Win32_Battery` 三次只读读数；**非逐轮首尾**，见受限项 |
| Godot | `4.3.stable.official.77dcf97d8` | `console.log` 首行；CSV `godot_version=4.3.stable` |

## 构建溯源

- `build_sha = 674542194592c39acf27cf3f6ac28ba572c1c5da`（`6745421`），导出前 `git status --porcelain` 为空、导出后复核仍为空：**纯 git SHA 构建，无未提交源码差异**。
- 唯一构建期差异：`run/main_scene` 从 `res://src/main.tscn` 临时切到 `res://src/qa/probe_runner.tscn`（§7 规定，Godot 导出预设不覆盖主场景），导出后 `finally` 无条件恢复。该切换对四轮完全一致，已记入 `build_provenance.json`。
- 预设 `Windows Desktop Probe`，`--export-release`，`build_type=release`，四轮一致，未混算 debug。

## 采集条件

- **轮次**：窗口 / 全屏 × 60 / 30fps 共 4 轮，每轮独立 `round_id`、独立两份 CSV、独立 `console.log`。
- **窗口档**：`WINDOW_MODE_WINDOWED`，窗口尺寸按 `project.godot` 配置 1280×720（**日志未打印实测像素尺寸**，此处只记配置值，不冒充实测）。**全屏档**：`WINDOW_MODE_FULLSCREEN`，物理面板 1920×1080 @120Hz。
- **帧率档**：`Engine.max_fps = 60 / 30`，`vsync=1`。实测 `frame_wall_ms` 均值：16.6667 / 16.6657（60 档）、33.3333 / 33.3352（30 档），四轮均与预期一致；全屏档出现真实测量噪声，非人为取整。
- **预热**：每轮 `--warmup-frames=300`，脚本内剔除、原始值不删。按实测帧间隔折算 60 档 ≈5.00s、30 档 ≈10.00s，满足 §3 的「≥5s」。预热从 `_begin()` 起算，引擎启动到 `_ready()` 的初始化时间未计入；本机 `vulkan/` / `shader_cache/` 在采集前已存在。
- **逐帧样本**：每轮 120 帧 GPU / CPU / 墙钟时间，GPU 样本 120/120 全非零。
- **后台策略**：采集期间未做后台进程隔离，WorkBuddy 会话与常规 Windows 后台服务在运行。如实描述，未写入采集原始 CSV。

## 关键口径提醒

- 帧时间样本 `load_kind=DEBUG_PLACEHOLDER_FRAME_NOT_A_BASELINE`：瓦片 / 实体 / 粒子贴图仍是运行时 debug 占位，**只作链路证据，不进 19 列汇总、不参与 verdict、不构成 GPU 帧预算判据**。
- 采集原始 CSV 的 `gpu_backend=forward_plus` 是 `rendering_method` 代理值；真实后端按引擎日志为 **Vulkan**，归档版已按此核对改写。
- 归档版 `metrics.csv` 只改元数据列，`samples/mean/p95/target/verdict` 与 `metrics_original.csv` 逐字段一致（已程序化比对）。
