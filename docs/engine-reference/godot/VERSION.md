# Godot 引擎版本与导入预设钉定（Engine Reference · Godot）
> ⚠️ **ADR-6 状态声明（2026-11-06 · Wave 2）**：本文件为Godot 引擎版本与导入预设钉定（现行配置真源）。原「移动端 iOS / Android、触屏单手、竖屏 720×1280、≥48px 触控命中区、低端机真机判据」条款**已由 `docs/architecture/adr-006-pc-first.md` 废止**；现行契约为 **Windows Desktop 单平台（横屏 1280×720、键鼠输入、单局 10–20 分钟）**。相关规范句已按 ADR-6 重订；ADR-1/2/3/4/5、C1、Godot 4.3 冻结、Basic 非触控 a11y 项与所有历史测量数字不变。历史原文保留于 git 变更记录，未静默删除。

> **项目**：《深窟兽语 / Hollowkin》（像素风 Roguelike，Windows Desktop / PC 单平台；移动端已彻底放弃，见 ADR-6）
> **用途**：钉定 Godot 引擎版本 + 像素资产导入预设（ADR-4）。本目录为引擎相关配置的权威来源，与根 `CLAUDE.md` §2/§3 互锁。
> **关联**：`CLAUDE.md` §2（版本钉定）、§3（导入预设）、`docs/art-bible/pixel-asset-pipeline.md` §3（导入覆写项）、`docs/architecture/adr-control-checklist.md`（ADR-4）。

---

## 1. 引擎版本钉定

| 项 | 值 | 状态 |
|---|---|---|
| 主版本 | Godot **4.x** | ✅ 冻结（项目既定） |
| 次版本（具体） | **4.3** | ✅ 已签字冻结（2026-11-03）；撰写建议线 4.3/4.4，用户定 4.3 |
| `project.godot` `config_version` | 随次版本 | 签署后锁定 |

> ✅ **已签字（2026-11-03）**：Godot **4.3** 冻结。升级须走"主理人审批 + 回归测试 + 修订本文档"三步，任何人不得擅自升/降级次版本。
>
> **版本敏感 API 复核（已签字 4.3）**：`palette_validator.gd` 文件加载经 `_load_png`（`FileAccess.open` + `Image.load_png_from_buffer`）直接读原始 PNG 字节，绕过 Godot 导入系统（否则 `.png` 被当作 Texture2D 拦截、`load_from_file` 返回空图像）；`.import` 预设格式按 §2.1 固化即可。
> - `PaletteValidator` 文件加载：`_load_png` 用 `FileAccess` 读取 res:// 原始字节后 `load_png_from_buffer` 解析（PNG-8 真 PNG 可直接解析），不依赖 `Image.load_from_file` 的导入系统路径。
> - `.import` 预设格式与 Import Preset 应用方式随 4.x 小版本一致，按下方 §3 固化即可。

---

## 2. 像素资产导入预设（ADR-4 · 防偏色/渗色）

ADR-4 决策：离线产出 PNG-8 → Godot 按**目录导入预设**接收。Godot 4 默认图片导入为 Compress（BPTC），**必须显式改预设**，否则偏色/渗色。

### 2.1 覆写项（像素资产专用，与 CLAUDE.md §3 一致）
| 参数 | 取值 | 作用 | 不设的风险 |
|---|---|---|---|
| `importer` | `texture` | 走纹理导入器 | — |
| `compress/mode` | `0`（Lossless）或 `1`（Uncompressed） | 0=无损体积小；1=完全不压缩、像素最稳；均禁 BPTC | 默认 BPTC 偏色/渗色 |
| `filter` | `false` | 关双线性过滤 → 最近邻硬边 | 默认 true → 像素羽化、描边糊 |
| `gen_mipmaps` | `false` | 不生成 mipmap → 缩小不模糊、不串色 | 默认 true → 远/小尺寸渗色 |
| `detect_3d/compress_to` | `0`（关） | 禁用"检测为 3D"的色彩空间转换 | 默认会按 3D 改色彩空间 → 偏色 |
| `process/fix_alpha_border` | `true`（推荐） | 修补索引色透明边 1px 脏边 | 透明边缘出现杂色描边 |
| `editor/convert_indexed` | `false` | 保持 RGBA，不强制转索引 | — |

### 2.2 固化方式（二选一，建议两者都做）
1. **逐资产 `.import`**：见同目录 `pixel_texture.import.tpl`（Godot 4 `.import` 格式，关键覆写已高亮）。将正式资产落入 `assets/` 后，Godot 生成 `.import`；本模板即其"目标态"，可在导入面板逐项设定后提交生成的 `.import` 文件。
2. **可复用 Import Preset（推荐目录批量）**：在 Godot 编辑器选中任一像素资产 → Import 面板按 §2.1 设定 → 点 **"Save as Preset"** → 命名 `HollowkinPixel` → 选中 `assets/sprites/`、`assets/ui/`、`assets/tiles/`、`assets/effects/` 等像素目录 → Import 面板下拉选 `HollowkinPixel` → **"Apply to Folder"**（或批量选中资产 Apply）。该 Preset 随工程保存，**提交工程即版本化**。

> **2026-11-05 环境更新**：Godot 4.3 已在本机 Windows 与 GitHub Actions `windows-latest` 以 headless 方式真实运行（GUT 6 scripts / 50 tests / 50 passing / 11452 asserts 全绿，见 `docs/phase4/epic-breakdown.md §12`），但**当时仍未在编辑器内固化实际 `.import` / Import Preset 文件**；模板与步骤已就绪。headless 实跑不等于编辑器导入流程已完成。
>
> **2026-11-07 闭环**：14 个 `assets/**/*.png.import` 已由编辑器模式一次性固化并提交（含 ADR-4 关键覆写 `detect_3d/compress_to=0`、`compress/mode=0`、`filter=false`、`gen_mipmaps=false`、`fix_alpha_border=true`）；`palette_validator.gd` 由 `EditorScript` 改为 `extends SceneTree` 后可 headless `-s` 实跑，对 14 张 E1 资产 **0 失败 0 警告、R1–R6 全绿**。编辑器内 `EditorPlugin` 回调路径仍未实现（不影响 CI headless）。

---

## 3. 校验集成（ADR-4 硬阻断）
- **headless -s（CI / 本地预检）**：`godot --headless -s res://src/core/asset_pipeline/palette_validator.gd` 依据 `asset_manifest.csv` 全量扫描 `assets/`；退出码 = 失败资产数（0 = 全通过），任一 R1–R5 失败即 `push_error`（非零退出阻断流水线）。**已于 2026-11-07 对 14 张 E1 资产实跑：0 失败、0 警告，R1–R6 全绿**（此前 `extends EditorScript` 导致 -s 永远无法实例化、R5/R6 从未真正跑过，已修正）。
- **编辑器内 `EditorPlugin` 回调路径未实现**（无 EditorPlugin 落地），不影响 CI headless 实跑；R6 为软警告不阻断。
- **Python 侧**：`pixel_pipeline.py --selftest` 与导出前可复用同等规则（`validate_python`，R1–R4）本地预检；R5/R6 由 Godot/manifest 侧覆盖。

---

*本文件钉定 Godot 4.3（已签字冻结）与 ADR-4 导入预设，与 `CLAUDE.md` 及 `pixel-asset-pipeline.md` 一致；已入库，导入预设固化状态见 §2.2。*
