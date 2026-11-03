# 资产生产规格 / Asset Production Spec（ADR-4 落地）

> **文档类型**：MVP 像素资产生产清单与闭环排产（Canonical for art pipeline）
> **归属**：art-director 起草，主理人签发
> **引用**：`docs/art-bible/pixel-asset-pipeline.md`（ADR-4 后处理链路）、`src/core/asset_pipeline/palette_source.json`（场景子集权威）、`design/gdd/mvp-spirit-bestiary.md` v1.3（slug 唯一源）
> **版本**：v1.0 · 未 git commit。

---

## 0. 生产闭环（强制）

```
AI 原图 → pixel_pipeline.py(降采样→≤16色索引→2×2 Bayer抖动→1-2px描边#1A1C2C)
       → palette_validator.gd(R1-R6 硬阻断)
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
| Tab/按钮底 | 48/64 | 中性岩灰为主 | 命中区 ≥48px |

## 2. 场景子集归属（硬约束）

- 每个不透明色 ∈ 资产声明 `scene` 的**场景子集**（bestiary §4 / palette_source.json）。
- `upper`=9 / `mid`=7 / `boss`=10 / `sanctuary`=9，均 ≤16，全取自美术圣经 §2.2 母库。
- 跨场景复用资产须按使用场景分别后处理（同一视觉可有多份 scene 变体）。

## 3. Manifest 字段（复用 asset_manifest.csv 14 列）

`asset_path, entity_slug, seed, category, scene, size, color_count, src_md5, generated_at, validator_pass, import_preset, palette_version, author, note`

- `entity_slug` 取自 bestiary §0.1（唯一命名源）。
- `scene` / `size` 决定后处理分支与 R3 校验。
- `validator_pass` 须为 True 方可入库（R1–R6 全绿）。

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

*本规格为资产生产 Canonical，不实际生成图片；后处理与校验以 `pixel-asset-pipeline.md` + `palette_source.json` 为权威。未 git commit。*
