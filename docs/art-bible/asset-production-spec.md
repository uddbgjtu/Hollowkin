# 资产生产规格 / Asset Production Spec（ADR-4 落地）
> ⚠️ **ADR-6 状态声明（2026-11-06 · Wave 2）**：本文件为资产生产规格（现行规格）。原「移动端 iOS / Android、触屏单手、竖屏 720×1280、≥48px 触控命中区、低端机真机判据」条款**已由 `docs/architecture/adr-006-pc-first.md` 废止**；现行契约为 **Windows Desktop 单平台（横屏 1280×720、键鼠输入、单局 10–20 分钟）**。相关规范句已按 ADR-6 重订；ADR-1/2/3/4/5、C1、Godot 4.3 冻结、Basic 非触控 a11y 项与所有历史测量数字不变。历史原文保留于 git 变更记录，未静默删除。

> **文档类型**：MVP 像素资产生产清单与闭环排产（Canonical for art pipeline）
> **归属**：art-director 起草，主理人签发
> **引用**：`docs/art-bible/pixel-asset-pipeline.md`（ADR-4 后处理链路）、`src/core/asset_pipeline/palette_source.json`（场景子集权威）、`design/gdd/mvp-spirit-bestiary.md` v1.3（slug 唯一源）
> **版本**：v1.2 · 2026-11-06 按 ADR-6 重订为 PC 单平台口径；v1.1 已修正 §3 Manifest 字段，与 canonical 14 列对齐。

---

## 0. 生产闭环（强制）

```
AI 原图 → pixel_pipeline.py(降采样→≤16色索引→2×2 Bayer抖动→1-2px描边#1A1C2C)
       → palette_validator.gd(R1–R5 硬阻断 / R6 软警告)
       → Godot 导入预设(pixel_texture.import.tpl, filter=false/mipmap=false)
       → asset_manifest.csv(14列登记)
```
**人工不得跳过任一环节**（CLAUDE.md 资产红线）。尺寸档仅 `16 / 24 / 32 / 48`（VALID_SIZES）。

## 1. 资产分类与 MVP 清单

### 1.1 角色（characters）— category `char`
| 实体 slug | 类型 | 尺寸 | 场景子集 | 备注 |
|---|---|---|---|---|
| `tamer` | 主角驯导者 | 24 | upper | 人类基准，无兽耳/角/尾 |
| `mossback` | 灵兽·坦克 | 24 | upper | 双外上耳/圆尾 |
| `emberhorn` | 灵兽·火输出 | 24 | upper | 独角右/右尾 |
| `frostling` | 灵兽·控制 | 24 | upper | 双下耳/双上尾 |
| `voltsprite` | 灵兽·敏捷 | 24 | upper | 单后耳/后上尾/尖喙 |
| `boss_deep` | Boss 深层 | 32~48 | boss(10) | 局部向上熔岩辉光 accent |
| （Phase 2 扩 5–8 只） | 灵兽 | 16/24 | upper/mid | 复用 bestiary §6 审计 |

### 1.2 地砖与场景（tiles）— category `tile`
| 资产 | 尺寸 | 场景子集 | 备注 |
|---|---|---|---|
| 上层地面/墙/边 | 16/24 | upper(9) | 描边#1A1C2C 1px |
| 中层地面/墙/边 | 16/24 | mid(7) | 更暗、冷调 |
| Boss 深层地面/熔岩 | 24 | boss(10) | 向上辉光 accent |
| 庇护所营地/家具 | 16/24 | sanctuary(9) | 暖、安全语义 |

### 1.3 物件与互动物（props）— category `prop`
| 资产 | 尺寸 | 场景子集 | 双编码形状 |
|---|---|---|---|
| 可互动物(宝箱/机关) | 16/24 | 依所在层 | 圆角高亮+青绿 |
| 陷阱 | 16 | 依所在层 | 锯齿框+琥珀 |
| 拾取物(灵蛋/符文) | 16 | 依所在层 | 形状区分类型 |

### 1.4 UI 图标（ui）— category `ui`
| 资产 | 尺寸 | 调色板 | 备注 |
|---|---|---|---|
| 技能/状态图标 | 24/32 | 全母库(≤32) | 状态用形状双编码(§3.1) |
| 资源/货币图标 | 16/24 | sanctuary 子集优先 | 文字标签辅助 |
| Tab/按钮底 | 48/64 | 中性岩灰为主 | 点击区域 ≥24×24px + 键盘可达（ADR-6） |

## 2. 场景子集归属（硬约束）

- 每个不透明色 ∈ 资产声明 `scene` 的**场景子集**（bestiary §4 / palette_source.json）。
- `upper`=9 / `mid`=7 / `boss`=10 / `sanctuary`=9，均 ≤16，全取自美术圣经 §2.2 母库。
- 跨场景复用资产须按使用场景分别后处理（同一视觉可有多份 scene 变体）。

## 3. Manifest 字段（canonical 14 列）

> **权威来源**：`docs/art-bible/pixel-asset-pipeline.md §2` +
> `src/core/asset_pipeline/pixel_pipeline.py::MANIFEST_COLUMNS`（代码实现），
> `src/core/asset_pipeline/asset_manifest.csv` 表头与之一致。本规格只引用该 schema，
> **不另立一套字段**。列名与顺序如下（`*` 为必含 6 列）：

```
asset_path, entity_slug, seed, prompt_digest, color_count, checksum,
category, variant, size, scene, palette_subset,
validator_result, source_raw, generated_at
```

| 列名 | 必含 | 说明 |
|---|---|---|
| `asset_path`* | ✅ | 相对仓库根的输出资产路径 |
| `entity_slug`* | ✅ | bestiary §0.1 唯一命名源 |
| `seed`* | ✅ | AI 生成种子（同类资产共用 base seed） |
| `prompt_digest`* | ✅ | 提示词摘要或 sha256，保证可追溯 |
| `color_count`* | ✅ | 不透明色数，须 ≤16，由 PaletteValidator 复核 |
| `checksum`* | ✅ | **输出资产文件** sha256（R5 比对防篡改/重量化） |
| `category` | — | `char` / `tile` / `ui` / `fx` |
| `variant` | — | `idle` / `walk` / `atk` / `a01`… |
| `size` | — | `16 / 24 / 32 / 48`（VALID_SIZES） |
| `scene` | — | `upper` / `mid` / `boss` / `sanctuary` |
| `palette_subset` | — | 引用的场景子集键，如 `upper` |
| `validator_result` | — | `pass` / `fail`（R1–R6 校验结论） |
| `source_raw` | — | 原始 AI 图路径 `assets/reference/_raw/...` |
| `generated_at` | — | ISO8601 生成时间 |

- `scene` / `size` 决定后处理分支与 R3 校验；`validator_result` 为 `pass`
  （R1–R6 全绿）方可入库。
- **已废弃的旧稿字段**（v1.0 §3 曾列，与 canonical 冲突，不得写入 manifest）：
  `src_md5`（源图 md5，与输出 sha256 语义冲突）、`validator_pass`（布尔，
  应为 `validator_result` 枚举）、`import_preset`（导入预设由
  `docs/engine-reference/godot/VERSION.md §2` 与 `.import` / Preset 管理，不进 manifest）、
  `palette_version`、`author`、`note`。任何新增审计信息以代码/schema 变更为准，
  不得在本规格中另造列。

## 4. 排产与吞吐（占位）

| 阶段 | 交付 | 负责 | 吞吐估计 |
|---|---|---|---|
| P4 锁定清单 | 本规格 + slug 映射 | art-director | 已交付 |
| 原图生成 | AI 原图(高分辨率) | 美术 | 每只 0.5–1d |
| 后处理 | pixel_pipeline.py 批处理 | 工程 | 脚本化，分钟级 |
| 校验 | palette_validator.gd | CI | 自动 |
| 导入预设 | Godot 导入 | 工程 | 自动 |

## 5. 验收标准（美术负责人签批项）

- [ ] 清单全部 slug 与 bestiary §0.1 一致，无漂移。
- [ ] 每资产 R1–R6 校验 True，manifest 登记完整。
- [ ] 四场景子集色数 ≤16 且 ∈ 母库。
- [ ] 双编码形状（敌我/状态/可互动物）落实，CVD 模拟不丢信息。

---

*本规格为资产生产 Canonical，不实际生成图片；后处理与校验以 `pixel-asset-pipeline.md` + `palette_source.json` 为权威，manifest schema 以 §3 canonical 14 列为准。已入库（v1.1，2026-11-05）。*
