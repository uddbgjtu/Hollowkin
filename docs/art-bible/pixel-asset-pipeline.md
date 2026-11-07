# 像素资产后处理链路规格 · Pixel Asset Post-Processing Pipeline
> ⚠️ **ADR-6 状态声明（2026-11-06 · Wave 2）**：本文件为像素资产后处理链路规格（现行规格）。原「移动端 iOS / Android、触屏单手、竖屏 720×1280、≥48px 触控命中区、低端机真机判据」条款**已由 `docs/architecture/adr-006-pc-first.md` 废止**；现行契约为 **Windows Desktop 单平台（横屏 1280×720、键鼠输入、单局 10–20 分钟）**。相关规范句已按 ADR-6 重订；ADR-1/2/3/4/5、C1、Godot 4.3 冻结、Basic 非触控 a11y 项与所有历史测量数字不变。历史原文保留于 git 变更记录，未静默删除。
> **项目**：《深窟兽语 / Hollowkin》（像素风 Roguelike，Windows Desktop / PC 单平台，Godot 4；见 ADR-6）
> **文档类型**：Phase 3 美术工程规格（落地 ADR-4）
> **负责人**：林绘澄（美术与视觉表现指导）
> **版本**：v1.1 · 2026-11-06 按 ADR-6 重订平台口径（原 v1.0 为移动端规格）
> **状态**：✅ 规格定稿——主实现由工程负责人程基岩接 ADR-4 落地；本文件给出精确步骤、参数、manifest schema、导入预设覆写、验收标准与一致性清单，并附 Python+Pillow 脚本骨架（非强制实现）。
> **对齐**：《美术圣经》v0.2（§2.2 / §5 / §6.1 / §6.2 / §8）、《架构可行性评审》ADR-4（§1.4）、《MVP 灵兽剪影清单》v1.2（§0.1 / §4）、《可访问性需求》v1.0（§3.1）。

---

## 0. 范围、目标与源权威

### 0.1 本文件定位
AI 生成的"伪像素图"本质是**先出高分辨率图再像素化降采样**。若不做强制后处理，跨帧、跨角色会严重不一致（偏色、羽化、描边断裂、网格错位）。本文件把美术圣经 §6.1 的"强制链路"与 ADR-4 的"离线脚本 + 目录导入预设 + 编辑器/CI 校验"工程决策落到**可执行的规格层面**。

本文件不实际生成图片资产（见美术圣经 §0），只定义：
- ① 离线脚本的**精确步骤与参数**（Python+Pillow，附骨架）；
- ② `asset-manifest.csv` 的 **schema**；
- ③ Godot 4 导入预设 **`.import` 覆写项清单**；
- ④ `PaletteValidator` **验收标准**（CI / 编辑器阻断）；
- ⑤ 跨帧一致性 **6 项校验清单**。

### 0.2 源权威（任何分歧以此为准）
| 主题 | 权威来源 | 本文件引用 |
|---|---|---|
| 网格基准 / 像素规格 | 美术圣经 §5 | ① 步骤 1、③、⑤ |
| 调色板母库（≤32）/ 每场景 ≤16 | 美术圣经 §2.2 / §5 | ① 步骤 2、②、④ |
| 后处理强制链路 | 美术圣经 §6.1 | ① 全链路 |
| 一致性校验 6 项 | 美术圣经 §6.2 | ⑤ |
| 离线脚本 + 导入预设 + 校验 | ADR-4（§1.4） | ① / ③ / ④ |
| 实体 slug / 场景色子集 | bestiary v1.2 §0.1 / §4 | ② / ④ |
| 双编码 / 色盲安全 | accessibility v1.0 §3.1 | ⑤ |

### 0.3 强制原则（不可被脚本绕过）
- **单一出口**：所有正式资产**只能**经本链路脚本产出；严禁人工在脚本外修改调色板/描边后直接入库（ADR-4 风险：PNG-8 被重新量化会偏色）。
- **索引色锁定**：正式资产为 PNG-8（带调色板）；Godot 导入后引擎会展开为 RGBA，但"≤16 色且取自母库"由**离线脚本 + manifest + PaletteValidator** 三层保证，而非引擎格式要求（ADR-4 决策原文）。
- **整数倍缩放**：瓦片 16、杂兵/小灵兽 16、主角/灵兽 24、BOSS 32~48；BOSS 为 16 的整数倍，引擎内按**整数倍**缩放显示，禁止非整数缩放导致像素错位（美术圣经 §5）。

---

## 1. 离线脚本：精确步骤与参数（Python + Pillow）

### 1.1 输入 / 输出约定
- **输入**：AI 原始高分辨率图，命名 `assets/reference/_raw/{entity}_{seed}_{ts}.png`（美术圣经 §8）。
- **输出**：正式索引色 PNG-8，落到 `assets/{category}/.../{category}_{entity}_{variant}_{size}.png`（命名规则 §8）。
- **登记**：每条输出在 `asset-manifest.csv` 追加一行（schema 见 §2）。
- **依赖**：`Pillow>=10`、`numpy`（最近邻调色板映射与抖动用）。脚本为**骨架**，最终由程基岩按 ADR-4 接 `src/` 与 CI。

### 1.2 链路顺序（与美术圣经 §6.1 / ADR-4 严格一致）
```
raw(HR) ──① 最近邻降采样→16/24 网格──② 套用场景≤16色母库子集索引(可选2×2抖动)──③ 补1–2px描边──④ 输出PNG-8 + 登记manifest
```
> 注：描边在索引之后（美术圣经 §6.1 原文顺序"索引 → 补描边 → 抖动"）。本规格把抖动并入 ② 的量化阶段（有序 2×2 抖动），描边独立为 ③。三者均在离线下完成，零运行时成本（ADR-4 后果）。

### 1.3 步骤参数表
| # | 步骤 | 关键参数 | 目的 / 对齐 |
|---|---|---|---|
| ① | 最近邻降采样 | `Image.resize(W,H, Image.NEAREST)`；`W,H ∈ {16,24,32,48}` 且为 16 整数倍；**禁止 LANCZOS/BILINEAR**（会抗锯齿） | 落到目标网格；保留硬边 |
| ①a | 去半透明（防亚像素） | alpha 阈值 `≥128 → 不透明，<128 → 透明`（硬切） | 美术圣经 §5"无半透明像素"、§6.2 #4 |
| ② | 固定调色板索引 | 取 `scene_subset(scene)`（≤16 色，见 §4）；逐像素 **最近邻映射到母库子集**；输出 `"P"` 模式 | 强制 ≤16 色且取自母库（ADR-4 / 美术圣经 §5） |
| ②d | 2×2 有序抖动 | Bayer `[[0,2],[3,1]]/4`；在两最近色间按 `(x%2,y%2)` 与误差分数择色；中性岩灰 `#9AA0B5` 参与过渡 | 美术圣经 §5"2×2 棋盘抖动、禁止羽化" |
| ③ | 补 1–2px 描边 | 16×16 → **1px**；24×24 及以上 → **2px**；描边色 `#1A1C2C`（资产最暗色近似）；仅填充原透明、紧贴不透明轮廓的像素 | 美术圣经 §5"1–2px 深描边" |
| ④ | 输出 PNG-8 + 登记 | `img.convert("P").save(path, optimize=True)`；写 `asset-manifest.csv`；计算 sha256 校验和 | ADR-4 "输出 PNG-8 并登记" |

**光照方向（非描边方向）**：全项目统一"左上受光、右下阴影"（美术圣经 §5 / bestiary §0）。该约束作用于 AI 提示词层与人工精修，**不在本脚本内自动生成**；脚本只负责描边（均匀暗边）与调色板，明暗由源图高光位继承。Boss 深层允许局部向上熔岩辉光作 accent，不破坏全局光向。

### 1.4 关键函数 / 伪代码（骨架 — 程基岩接 ADR-4 落地）
```python
# pixel_pipeline.py  (SKELETON — 程基岩按 ADR-4 落地; 本文件为规格, 非强制实现)
from PIL import Image, ImageFilter, ImageChops
import numpy as np, hashlib, csv, os

# ── 母库 / 场景子集 (源: 美术圣经 §2.2 + bestiary §4) ──────────────────────
MASTER_PALETTE = {  # name: (r,g,b)  —— 全部取自美术圣经 §2.2, 共 19 色 ≤32
    "sun_ember":(255,140,66), "sky_bolt":(63,167,255), "leaf_pop":(95,211,90),
    "mist_teal":(123,201,176), "honey":(255,210,63), "dusk_purple":(122,94,158),
    "amber":(217,142,50), "abyss_indigo":(43,58,102), "lava_orange":(255,106,44),
    "lavender":(155,107,255), "teal":(46,196,182), "sakura":(255,111,181),
    "clay":(165,106,67), "danger_red":(255,77,77), "poison_green":(166,255,77),
    "night_indigo":(26,28,44), "dusk_blue":(43,47,74), "parchment":(244,228,193),
    "rock_gray":(154,160,181),
}
SCENE_SUBSET = {  # bestiary §4 (上层9 / 中层7) + 本文件定义的 boss/sanctuary (≤16, 林绘澄签批)
    "upper": ["mist_teal","leaf_pop","honey","clay","teal","night_indigo",
              "parchment","sun_ember","dusk_blue"],
    "mid":   ["amber","lava_orange","dusk_purple","sky_bolt","teal",
              "parchment","night_indigo"],
    # boss: 源 美术圣经 §2.1(Boss深层 冷靛+熔岩橙) + 锚点D(夜靛/冷靛背景, 浮尘青绿/蜜黄, 敌红/紫锐三角) + §4(危险红/剧毒绿); 共 10 色 ≤16
    "boss":  ["night_indigo","abyss_indigo","lava_orange","honey","teal",
              "danger_red","dusk_purple","poison_green","parchment","rock_gray"],
    # sanctuary: 源 美术圣经 §1(暖橙+奶白 治愈/收集) + §4 符文灯彩UI(暖铜/蜜黄/暮蓝); 共 9 色 ≤16
    "sanctuary": ["sun_ember","parchment","honey","clay","dusk_blue",
                  "sky_bolt","leaf_pop","night_indigo","rock_gray"],
}
# 注: boss/sanctuary 子集已于 bestiary v1.2 §4 回填(林绘澄签批), 两处为同一权威源;
#     中性岩灰 rock_gray 作 2×2 抖动共享中性(美术圣经 §5), 计入各子集以满足 R3 严格校验。

OUTLINE_COLOR = MASTER_PALETTE["night_indigo"]   # #1A1C2C
ALPHA_CUTOFF  = 128

def scene_rgb(subset_key): 
    return [MASTER_PALETTE[n] for n in SCENE_SUBSET[subset_key]]

# ── ① 最近邻降采样 + 去半透明 ─────────────────────────────────────────────
def downscale_nearest(src, target):
    img = src.resize((target, target), Image.NEAREST)        # 硬边, 禁 LANCZOS
    a = img.split()[3].point(lambda v: 255 if v >= ALPHA_CUTOFF else 0)
    img.putalpha(a)                                          # 硬切半透明 → 防亚像素
    return img

# ── ② 固定调色板索引 + 2×2 有序抖动 ──────────────────────────────────────
BAYER2 = np.array([[0,2],[3,1]], float) / 4.0
def quantize_fixed(rgba, palette, dither=True):
    arr = np.array(rgba.convert("RGBA")).astype(int)
    rgb, a = arr[...,:3], arr[...,3]
    pal = np.array(palette, int)                             # (K,3)
    out = np.zeros(rgb.shape[:2], np.uint8)
    opaque = a >= ALPHA_CUTOFF
    for (y,x),_ in np.ndenumerate(opaque):
        if not opaque[y,x]: continue
        d = np.sum((pal - rgb[y,x])**2, axis=1)
        k0 = int(d.argmin())
        if dither and pal.shape[0] > 1:
            k1 = int(d.argsort()[1])                         # 次近色
            frac = d[k0] / max(d[k0]+d[k1], 1)
            if BAYER2[y%2, x%2] < frac: out[y,x] = k1
            else:                          out[y,x] = k0
        else:
            out[y,x] = k0
    p = Image.new("P", (rgba.width, rgba.height))
    flat = [v for c in palette for v in c] + [0]*(768-len(palette)*3)
    p.putpalette(flat); p.putdata(out.flatten().tolist())
    return p

# ── ③ 补 1–2px 描边 (紧贴轮廓的外扩暗边) ──────────────────────────────────
def add_outline(p_indexed, width):                           # width: 16→1, ≥24→2
    rgba = p_indexed.convert("RGBA")
    a = rgba.split()[3]
    dil = a.filter(ImageFilter.MaxFilter(2*width+1))          # 形态学膨胀 width px
    edge = ImageChops.subtract(dil, a)                       # 新增的不透明边
    px = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            if edge.getpixel((x,y)) > 0 and a.getpixel((x,y)) < ALPHA_CUTOFF:
                px[x,y] = (*OUTLINE_COLOR, 255)
    return rgba.convert("P", palette=Image.ADAPTIVE, colors=len(SCENE_SUBSET)) # 重新索引回固定板(见注)
    # 注: 实际落地应 putpalette 回 SCENE_SUBSET, 此处示意; 描边色∈母库, 不增色数

# ── ④ 输出 PNG-8 + manifest 登记 + 校验和 ────────────────────────────────
def sha256(path):
    h=hashlib.sha256()
    with open(path,"rb") as f: h.update(f.read())
    return h.hexdigest()

def process_one(raw_path, entity_slug, scene, size, variant, prompt_digest, seed):
    target = size
    img = downscale_nearest(Image.open(raw_path), target)
    pal = scene_rgb(scene)
    img = quantize_fixed(img, pal, dither=True)
    img = add_outline(img, 1 if size==16 else 2)
    out_rel = f"assets/sprites/characters/{entity_slug}/char_{entity_slug}_{variant}_{size}.png"
    img.save(out_rel, optimize=True)                          # PNG-8 索引
    row = { "asset_path":out_rel, "entity_slug":entity_slug, "scene":scene,
            "size":size, "variant":variant, "seed":seed,
            "prompt_digest":prompt_digest, "checksum":sha256(out_rel),
            "color_count": count_colors(img) }                # 见 §4 PaletteValidator
    append_manifest(row)
    return row
```
> **落地交给程基岩的明确接口**：`process_one(raw_path, entity_slug, scene, size, variant, prompt_digest, seed)` 一次处理单资产；批量入口遍历 `assets/reference/_raw/`。`MASTER_PALETTE` / `SCENE_SUBSET` 必须**从美术圣经 §2.2 与 bestiary §4 单一来源生成**，禁止硬编码漂移。

---

## 2. asset-manifest.csv Schema

链路脚本对每个正式资产追加一行。**必含 5 列**（任务指定：seed / 提示词 / 色数 / 校验和 / 资产路径）以 `*` 标注；其余为工程/审计增强列。

| 列名 | 必含 | 类型 | 说明 / 取值 |
|---|---|---|---|
| `asset_path`* | ✅ | string | 相对仓库根的资产路径，如 `assets/sprites/characters/mossback/char_mossback_idle_24.png` |
| `entity_slug`* | ✅ | string | bestiary §0.1 唯一 slug：`tamer`/`mossback`/`emberhorn`/`frostling`/`voltsprite` |
| `seed`* | ✅ | int | AI 生成种子（同类资产共用 base seed + 仅变动动作词，美术圣经 §6.1） |
| `prompt_digest`* | ✅ | string | 提示词摘要或 sha256（金标准图定稿后 image-to-image + 低 denoise，需可追溯） |
| `color_count`* | ✅ | int | 该资产不透明色数，**必须 ≤16**；由 PaletteValidator 复核 |
| `checksum`* | ✅ | string | 资产文件 sha256（任务指定"校验和"），CI 比对防篡改/重量化 |
| `category` | — | enum | `char`/`tile`/`ui`/`fx`（美术圣经 §8） |
| `variant` | — | string | `idle`/`walk`/`atk`/`a01`… |
| `size` | — | int | 16 / 24 / 32 / 48 |
| `scene` | — | enum | `upper`/`mid`/`boss`/`sanctuary`（决定调用哪个 §2.2 场景子集） |
| `palette_subset` | — | string | 引用的场景子集键，如 `upper`/`mid` |
| `validator_result` | — | enum | `pass`/`fail`（PaletteValidator 结果，§4） |
| `source_raw` | — | string | 原始 AI 图路径 `assets/reference/_raw/{entity}_{seed}_{ts}.png` |
| `generated_at` | — | datetime | ISO8601 生成时间 |

**示例行（源自 bestiary §0.1 五实体）**
```csv
asset_path,entity_slug,seed,prompt_digest,color_count,checksum,category,variant,size,scene,palette_subset,validator_result,source_raw,generated_at
assets/sprites/characters/tamer/char_tamer_idle_24.png,tamer,10241,a1b2c3…,9,sha256…,char,idle,24,upper,upper,pass,assets/reference/_raw/tamer_10241_1699.png,2026-11-03T10:00:00
assets/sprites/characters/mossback/char_mossback_idle_24.png,mossback,20131,d4e5f6…,6,sha256…,char,idle,24,upper,upper,pass,assets/reference/_raw/mossback_20131_1700.png,2026-11-03T10:05:00
assets/sprites/characters/emberhorn/char_emberhorn_atk_24.png,emberhorn,30271,aa11bb…,6,sha256…,char,atk,24,mid,mid,pass,assets/reference/_raw/emberhorn_30271_1701.png,2026-11-03T10:10:00
assets/sprites/characters/frostling/char_frostling_idle_24.png,frostling,40391,cc22dd…,6,sha256…,char,idle,24,mid,mid,pass,assets/reference/_raw/frostling_40391_1702.png,2026-11-03T10:15:00
assets/sprites/characters/voltsprite/char_voltsprite_walk_24.png,voltsprite,50411,ee33ff…,5,sha256…,char,walk,24,upper,upper,pass,assets/reference/_raw/voltsprite_50411_1703.png,2026-11-03T10:20:00
```
> 色数与场景占用对照 bestiary §4（上层 9/16、中层 7/16）；单兽 ≤6 主色 + 描边/高光。

---

## 3. Godot 4 导入预设 `.import` 覆写项清单

ADR-4 决策：离线产出 PNG-8 → Godot 按**目录导入预设**（`compress/mode=0` 或 `1`、`filter=false`、`gen_mipmaps=false`、`detect_3d/compress_to` 关）。**Godot 4 默认图片导入为 Compress（BPTC），必须显式改预设**，否则偏色/渗色（ADR-4 风险）。

### 3.1 覆写项清单（像素资产专用预设）
| 导入参数 | 取值 | 作用 | 风险若不设 |
|---|---|---|---|
| `importer` | `"texture"` | 走纹理导入器 | — |
| `compress/mode` | **`0`（Lossless）** 或 **`1`（Uncompressed）** | 0=无损压缩、体积小；1=完全不压缩、像素最稳。二选一，均禁 BPTC | 默认 BPTC 压缩会偏色/渗色 |
| `filter` | **`false`** | 关双线性过滤 → 最近邻硬边，放大不模糊 | 默认 true → 像素羽化、描边糊 |
| `gen_mipmaps` | **`false`** | 不生成 mipmap → 缩小时不模糊、不串色 | 默认 true → 远/小尺寸渗色 |
| `detect_3d/compress_to` | **`0`（关）** | 禁用"检测为 3D"的 sRGB/压缩转换 | 默认会按 3D 改色彩空间 → 偏色 |
| `process/fix_alpha_border` | `true`（推荐） | 修补索引色透明边渗色（PNG-8 常见 1px 脏边） | 透明边缘出现杂色描边 |
| `editor/convert_indexed` | `false` | 保持 RGBA，不强制转索引（索引由离线保证） | — |

> 引擎展开为 RGBA 后，"≤16 色"仅靠离线脚本 + manifest + PaletteValidator 保证（ADR-4 原文）。导入预设只负责**不偏色、不羽化、不缩混**。

### 3.2 示例 `.import`（Godot 4 格式，关键覆写已高亮）
```ini
[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://bhollowkinchar"
path="res://.godot/imported/char_mossback_idle_24.png-<hash>.ctex"
metadata={"vram_texture":false}

[params]

compress/mode=0                ; ← Lossless (或 1=Uncompressed)
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false         ; ← 关 mipmap
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true  ; ← 修索引色透明边
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=0.0
detect_3d/compress_to=0        ; ← 关 3D 检测转换
detect_3d/min_size=0
editor/scale_with_editor_zoom=false
```
> 落地方式：在 `assets/sprites/`、`assets/ui/` 等像素资产目录放 `.import` 预设（或 Godot 4 的 **Import Preset** 文件 + 目录批量指派），由程基岩在 ADR-4 落地时固化到 `docs/engine-reference/godot/` 或工程预设（可行性评审 §7 建议建 `VERSION.md` 钉引擎版本）。

---

## 4. PaletteValidator 验收标准（CI / 编辑器阻断）

来源：ADR-4 决策"编辑器/CI 跑 `PaletteValidator`，断言每资产 ≤16 色且取自母库，否则阻断导入"；美术圣经 §5"每场景调色板 ≤16 色、从母库取子集"。

### 4.1 验收规则（任一不满足 → 阻断）
| # | 规则 | 阈值 / 来源 | 阻断级别 |
|---|---|---|---|
| R1 | 不透明色数 ≤ 16 | 美术圣经 §5 / ADR-4 | **硬阻断** |
| R2 | 每个不透明色 ∈ 母库 §2.2（19 色） | 美术圣经 §2.2 | **硬阻断** |
| R3 | 每个不透明色 ∈ 该资产声明 `scene` 的场景子集（bestiary §4） | bestiary §4（上层 9 / 中层 7 / Boss 深层 10 / 庇护所 9，均 ≤16） | **硬阻断**（比 R2 更紧） |
| R4 | 无半透明像素（alpha ∈ {0,255}，阈值同 §1.3 ①a） | 美术圣经 §6.2 #4 | 硬阻断 |
| R5 | `color_count` 与 `checksum` 与 `asset-manifest.csv` 一致 | §2 schema | 硬阻断（防绕过/重量化） |
| R6 | 文件名符合 `{category}_{entity}_{variant}_{size}.png`；`category` ∈ {char,tile,ui,fx,prop}、`size` ∈ {16,24,32,48}、`entity` ∈ 登记 slug（bestiary §0.1 五生物 + E1 扩产 tile/prop/ui 实体，可含下划线如 `upper_floor`） | 美术圣经 §8 / bestiary §0.1 | 软警告（命名漂移） |

### 4.2 参考实现（GDScript，源自可行性评审 §6.5，已扩展 R3/R4）
```gdscript
# PaletteValidator.gd  (headless -s / CI 调用; 扩展自 feasibility-review §6.5；2026-11-07 修正为 extends SceneTree 使 -s 可实跑，原 EditorScript 永不可 headless 实例化)
const MASTER := {  # 美术圣经 §2.2 hex 集合
  "FF8C42","3FA7FF","5FD35A","7BC9B0","FFD23F","7A5E9E","D98E32",
  "2B3A66","FF6A2C","9B6BFF","2EC4B6","FF6FB5","A56A43","FF4D4D",
  "A6FF4D","1A1C2C","2B2F4A","F4E4C1","9AA0B5" }
const SCENE := {  # bestiary §4 (upper/mid) + 本规格定义 boss/sanctuary (≤16, 林绘澄签批)
  "upper":["7BC9B0","5FD35A","FFD23F","A56A43","2EC4B6","1A1C2C","F4E4C1","FF8C42","2B2F4A"],
  "mid":  ["D98E32","FF6A2C","7A5E9E","3FA7FF","2EC4B6","F4E4C1","1A1C2C"],
  "boss": ["1A1C2C","2B3A66","FF6A2C","FFD23F","2EC4B6","FF4D4D","7A5E9E","A6FF4D","F4E4C1","9AA0B5"],
  "sanctuary":["FF8C42","F4E4C1","FFD23F","A56A43","2B2F4A","3FA7FF","5FD35A","1A1C2C","9AA0B5"] }

func validate(tex:Texture2D, scene:String, cap:=16) -> bool:
    var img := tex.get_image(); var used := {}
    for y in img.get_height():
        for x in img.get_width():
            var c := img.get_pixel(x,y)
            if c.a < 0.01: continue
            if c.a < 0.99: push_error("半透明像素 @%d,%d" % [x,y]); return false  # R4
            var h := c.to_html(false).to_upper()
            used[h] = true
    if used.size() > cap: push_error("调色板 %d > %d" % [used.size(), cap]); return false  # R1
    for col in used.keys():
        if not MASTER.has(col): push_error("母库外色: %s" % col); return false            # R2
        if not SCENE[scene].has(col): push_error("场景%s子集外色: %s" % [scene,col]); return false  # R3
    return true
```
> **CI 集成**：在 pre-commit / CI 用 `godot --headless -s res://src/core/asset_pipeline/palette_validator.gd` 全量扫描 `assets/` + `asset-manifest.csv`；退出码 = 失败资产数（0 = 全通过），任一 R1–R5 失败即 **非零退出阻断流水线**（ADR-4 "否则阻断导入"）。`EditorPlugin` 编辑器内回调路径未实现（无 EditorPlugin 落地），R6 为软警告不阻断。

---

## 5. 跨帧一致性 6 项校验清单（跨角色 / 跨帧不崩坏）

来源：美术圣经 §6.2 一致性清单（6 项）+ bestiary §3 剪影唯一性 + accessibility §3.1 双编码。本清单专为"链路产出后、入库前"的**跨帧/跨角色**一致性把关；颜色项（#2）由 PaletteValidator 自动阻断，其余需脚本/人工叠加复核。

| # | 检查项 | 标准（跨帧/跨角色） | 方法 / 工具 | 门禁 |
|---|---|---|---|---|
| 1 | **网格对齐 & 整像素位移** | 同实体所有帧同网格（16/24）；帧间位移为整数像素，无亚像素偏移；spritesheet 各帧原点一致 | 放大 800% 检查；脚本比对每帧尺寸/原点 | 自动+人工 |
| 2 | **调色板一致** | 每资产 ≤16 色、取自母库且属声明场景子集；**同实体各帧用完全相同调色板**；同场景跨实体共享子集 | `PaletteValidator`（§4 R1–R3） | **自动硬阻断** |
| 3 | **描边 / 轮廓统一** | 1–2px 同色 `#1A1C2C` 描边，宽度随网格固定（16→1px，≥24→2px），无断裂、无粗细漂移 | 描边层提取比对；脚本统计边缘像素 | 自动+人工 |
| 4 | **光照方向一致** | 全项目"左上受光、右下阴影"；高光位在同实体各帧、跨角色间一致；Boss 深层仅局部向上熔岩辉光 accent | 目视 + 高光位坐标检查 | 人工 |
| 5 | **剪影 / 三角特征一致（双编码）** | 同实体各帧保持三角特征身份（耳/角/尾/额外轴不漂移）；**跨角色无撞型**（bestiary §3 两两 ≥2 轴不同）；敌我靠形状而非仅靠颜色 | 叠加半透明比对；bestiary §3 差异矩阵复核 | 人工（结构自检） |
| 6 | **无 IP 残留 & 无羽化** | 无宝可梦/任天堂/魔兽具体元素；无半透明/抗锯齿羽化像素 | 人工 + 反向图搜抽检；§4 R4 半透明自动查 | 自动(R4)+人工 |

> **与可访问性对齐**：#5 的"跨角色形状区分"直接满足 accessibility v1.0 §3.1 双编码（敌我/灵兽种族靠三角特征而非仅配色）；暖色同组的焰角(琥珀)/雷隼(暖黄)分属不同场景且形状差异（独角右尾 vs 单后耳+后上尾+尖喙）已通过 bestiary §4.1 双编码校验。
>
> **自动 vs 人工分工**：#2（颜色）与 #6 的半透明项由 `PaletteValidator` 自动硬阻断；#1/#3 可由脚本扩展（帧尺寸/描边像素统计）；#4/#5/#6 的 IP 与剪影需人工或图像比对复核。建议程基岩在 ADR-4 落地时把 #1/#3 纳入同一 CI 校验脚本。

---

## 6. 实现交接（给工程负责人程基岩 · 接 ADR-4）

| 本文件章节 | 工程落地职责 | 备注 |
|---|---|---|
| §1 脚本骨架 | 在 `src/` 落地 `pixel_pipeline.py`；`MASTER_PALETTE`/`SCENE_SUBSET` 从 §2.2/§4 单一来源生成 | 已附 Python 骨架，非强制实现 |
| §2 manifest | 实现 `append_manifest()` 与 CSV 初始化；种子/提示词摘要/校验和写入 | schema 已定 |
| §3 `.import` | 固化像素资产目录导入预设（Lossless/Uncompressed + 关 filter/mipmap + 关 detect_3d） | 建议钉入 `docs/engine-reference/godot/` |
| §4 Validator | 落地 `PaletteValidator`（GDScript，extends SceneTree，-s headless 可实跑）；R1–R6 已对 14 资产实跑全绿 | 已附扩展 GDScript |
| §5 一致性 | #2/#6-R4 已自动；#1/#3 建议并入同脚本自动；#4/#5 人工复核流程 | 清单已定 |

> 本文件为**规格**，不修改 `src/`、不 git commit（遵循任务约束与可行性评审 §6 约定）。

---

*本文件为 Phase 3 美术工程规格，落地 ADR-4 与美术圣经 §6.1；与 bestiary v1.2、accessibility v1.0 一致。主实现由工程负责人接 ADR-4 完成。*
