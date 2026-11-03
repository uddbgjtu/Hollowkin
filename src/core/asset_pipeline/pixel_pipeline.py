#!/usr/bin/env python3
# =============================================================================
# ADR-4 · 像素资产后处理链路（pixel_pipeline.py）
# =============================================================================
# 落地自 docs/art-bible/pixel-asset-pipeline.md §1/§2（art-director 规格）。
# 强制链路（art-bible §6.1 / ADR-4）：
#   raw(HR) → ① 最近邻降采样 + alpha 硬切
#          → ② 固定调色板索引（有序 2×2 抖动）
#          → ③ 补 1–2px 描边 (#1A1C2C)
#          → ④ PNG-8 输出 + asset-manifest.csv 登记 (sha256)
#
# 单一来源纪律：调色板只从 palette_source.json 读取（art-bible §2.2 + bestiary §4），
#   禁止在代码内硬编码颜色（防止漂移）。脚本骨架非强制，本实现为重写（纯 Pillow，去 numpy 依赖）。
# 运行依赖：Pillow>=10。可选：--selftest 跑真实自检（生成合成图→出 PNG-8→校验通过）。
# =============================================================================

import os
import sys
import csv
import json
import hashlib
import argparse
from datetime import datetime, timezone

from PIL import Image, ImageFilter

# ---- 路径约定 ---------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
PALETTE_JSON = os.path.join(HERE, "palette_source.json")
MANIFEST_CSV = os.path.join(HERE, "asset_manifest.csv")  # 默认 manifest（可被参数覆盖）

# manifest 列顺序（pixel-asset-pipeline.md §2 全 14 列；* 为必含 5~6 列）
MANIFEST_COLUMNS = [
    "asset_path", "entity_slug", "seed", "prompt_digest", "color_count", "checksum",
    "category", "variant", "size", "scene", "palette_subset",
    "validator_result", "source_raw", "generated_at",
]

# 网格基准（art-bible §5）：瓦片/杂兵 16、主角/灵兽 24、BOSS 32~48（16 整数倍）
VALID_SIZES = (16, 24, 32, 48)

# 有序 2×2 Bayer 抖动矩阵（art-bible §5 / pipeline §1.3 ②d）
BAYER2 = [[0, 2], [3, 1]]


# ---------------------------------------------------------------------------
# 调色板加载（单一来源）
# ---------------------------------------------------------------------------
def load_palette_source(path: str = PALETTE_JSON) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def scene_rgb(subset_key: str, src: dict) -> list:
    """返回场景子集的 RGB 列表（顺序即索引）。未登记场景返回空列表（process_one 回退母库全集 R2）。"""
    if subset_key not in src["scene_subset"]:
        return []
    return [tuple(src["master_palette"][name]["rgb"])
            for name in src["scene_subset"][subset_key]["colors"]]


def master_rgb_set(src: dict) -> set:
    return {tuple(v["rgb"]) for v in src["master_palette"].values()}


def outline_rgb(src: dict) -> tuple:
    h = src["_meta"]["outline_color_hex"]
    for v in src["master_palette"].values():
        if v["hex"].upper() == h.upper():
            return tuple(v["rgb"])
    raise KeyError("outline_color not found in master_palette")


# ---------------------------------------------------------------------------
# ① 最近邻降采样 + alpha 硬切（防亚像素，art-bible §5 / §6.2 #4）
# ---------------------------------------------------------------------------
def downscale_nearest(src_img: Image.Image, target: int, alpha_cutoff: int = 128) -> Image.Image:
    if target not in VALID_SIZES:
        raise ValueError(f"target size {target} 不在 {VALID_SIZES}（art-bible §5 整数倍）")
    # 最近邻硬边，禁 LANCZOS/BILINEAR（会抗锯齿羽化）
    img = src_img.resize((target, target), Image.NEAREST)
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    r, g, b, a = img.split()
    # alpha 阈值硬切：≥cutoff → 255，否则 0
    a = a.point(lambda v: 255 if v >= alpha_cutoff else 0)
    return Image.merge("RGBA", (r, g, b, a))


# ---------------------------------------------------------------------------
# ② 固定调色板索引 + 2×2 有序抖动
# ---------------------------------------------------------------------------
def quantize_fixed(rgba: Image.Image, palette: list, dither: bool = True, alpha_cutoff: int = 128):
    """
    返回 (indices: list[list[int]], palette: list[tuple])。
    - 不透明像素：最近色(k0)；若 dither 且存在次近色(k1)，按 Bayer 2×2 在两色间抖。
    - 透明像素：指向透明槽（palette 末尾）。
    - 不新增颜色：palette = 场景子集 + 透明槽；描边色(#1A1C2C)已在场景子集内。
    """
    w, h = rgba.size
    px = rgba.load()
    pal = list(palette)  # 场景子集 RGB
    transparent_index = len(pal)
    full_palette = pal + [(0, 0, 0)]  # 透明槽（alpha 由 transparency 标记）

    n = len(pal)
    indices = [[transparent_index] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < alpha_cutoff:
                continue  # 透明 → transparent_index
            # 平方距离到各调色板色，维护最近(k0)与次近(k1)
            best_k0, best_d0 = 0, None
            best_k1, best_d1 = -1, None
            for k in range(n):
                pr, pg, pb = pal[k]
                d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2
                if best_d0 is None or d < best_d0:
                    best_k1, best_d1 = best_k0, best_d0
                    best_k0, best_d0 = k, d
                elif best_d1 is None or d < best_d1:
                    best_k1, best_d1 = k, d
            if dither and best_k1 >= 0 and (best_d0 + best_d1) > 0:
                frac = best_d0 / (best_d0 + best_d1)  # 误差偏向 k1 的比例
                if BAYER2[y % 2][x % 2] / 4.0 < frac:
                    indices[y][x] = best_k1
                else:
                    indices[y][x] = best_k0
            else:
                indices[y][x] = best_k0
    return indices, full_palette


# ---------------------------------------------------------------------------
# ③ 补 1–2px 描边（紧贴不透明轮廓的外扩暗边，#1A1C2C）
#   实现见 _add_outline_indexed（在 process_one 内调用，直接操作索引数组，
#   避免回量化导致抖动重算）。描边色(#1A1C2C=night_indigo)已在场景子集内，不增色数。
# ---------------------------------------------------------------------------
def build_palette_image(indices: list, full_palette: list, transparent_index: int) -> Image.Image:
    h = len(indices)
    w = len(indices[0])
    flat = []
    for (r, g, b) in full_palette:
        flat += [r, g, b]
    flat += [0] * (768 - len(flat))  # pad 到 256*3
    img = Image.new("P", (w, h))
    img.putpalette(flat)
    img.putdata([indices[y][x] for y in range(h) for x in range(w)])
    img.info["transparency"] = transparent_index
    return img


# ---------------------------------------------------------------------------
# 计数 / 校验和 / manifest
# ---------------------------------------------------------------------------
def count_colors(img: Image.Image, alpha_cutoff: int = 128) -> int:
    rgba = img.convert("RGBA")
    px = rgba.load()
    seen = set()
    for y in range(rgba.height):
        for x in range(rgba.width):
            if px[x, y][3] >= alpha_cutoff:
                seen.add(px[x, y][:3])
    return len(seen)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def init_manifest(path: str = MANIFEST_CSV) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        csv.DictWriter(f, fieldnames=MANIFEST_COLUMNS).writeheader()


def append_manifest(row: dict, path: str = MANIFEST_CSV) -> None:
    write_header = not os.path.exists(path) or os.path.getsize(path) == 0
    with open(path, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=MANIFEST_COLUMNS)
        if write_header:
            w.writeheader()
        w.writerow({k: row.get(k, "") for k in MANIFEST_COLUMNS})


# ---------------------------------------------------------------------------
# ④ 单资产处理
# ---------------------------------------------------------------------------
def process_one(raw_path: str, entity_slug: str, scene: str, size: int, variant: str,
                prompt_digest: str, seed: int, src: dict, category: str = "char",
                out_dir: str = "assets", dither: bool = True,
                manifest_path: str = MANIFEST_CSV) -> dict:
    alpha_cutoff = src["_meta"].get("alpha_cutoff", 128)
    pal = scene_rgb(scene, src)
    if not pal:
        # 未登记场景（bestiary §4 无子集）：回退母库全集（R2），不执行 R3 子集断言
        pal = [tuple(v["rgb"]) for v in src["master_palette"].values()]
        print(f"  [warn] scene='{scene}' 无文档定义子集 → 使用母库全集(R2)")
    outline = outline_rgb(src)
    outline_index = pal.index(outline)  # 描边色必在场景子集内

    img = downscale_nearest(Image.open(raw_path), size, alpha_cutoff)
    indices, full_palette = quantize_fixed(img, pal, dither, alpha_cutoff)
    # 描边宽度：16→1px，≥24→2px（art-bible §5）
    width = 1 if size == 16 else 2
    indices = _add_outline_indexed(indices, img, outline_index, width, alpha_cutoff)

    pimg = build_palette_image(indices, full_palette, len(pal))  # transparent_index=len(pal)

    out_rel = os.path.join(out_dir, f"{category}s", entity_slug,
                           f"{category}_{entity_slug}_{variant}_{size}.png")
    os.makedirs(os.path.dirname(out_rel), exist_ok=True)
    pimg.save(out_rel, optimize=True)  # PNG-8 索引

    color_count = count_colors(pimg, alpha_cutoff)
    row = {
        "asset_path": out_rel, "entity_slug": entity_slug, "seed": seed,
        "prompt_digest": prompt_digest, "color_count": color_count,
        "checksum": sha256_file(out_rel), "category": category, "variant": variant,
        "size": size, "scene": scene, "palette_subset": scene,
        "validator_result": "pending", "source_raw": raw_path,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    append_manifest(row, manifest_path)
    return row


def _add_outline_indexed(indices, rgba, outline_index, width, alpha_cutoff):
    w, h = rgba.size
    a = rgba.split()[3]
    dilated = a.filter(ImageFilter.MaxFilter(2 * width + 1))
    da = dilated.load()
    aa = a.load()
    out = [row[:] for row in indices]
    for y in range(h):
        for x in range(w):
            if da[x, y] >= alpha_cutoff and aa[x, y] < alpha_cutoff:
                out[y][x] = outline_index
    return out


# ---------------------------------------------------------------------------
# Python 侧轻量校验（供 selftest / CI 复用，与 GDScript PaletteValidator 同规则）
# ---------------------------------------------------------------------------
def validate_python(img: Image.Image, scene: str, src: dict, cap: int = 16) -> tuple:
    alpha_cutoff = src["_meta"].get("alpha_cutoff", 128)
    master = master_rgb_set(src)
    subset = set(scene_rgb(scene, src))
    rgba = img.convert("RGBA")
    px = rgba.load()
    seen = set()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = px[x, y]
            if a < alpha_cutoff:
                continue
            if a < 255:
                # R4：半透明像素（(cutoff,255) 开区间）→ 阻断（美术圣经 §6.2 #4）
                return (False, f"R4 半透明像素 @({x},{y}) alpha={a}")
            col = (r, g, b)
            seen.add(col)
            if col not in master:
                return (False, f"R2 母库外色 {col}")
            if subset and col not in subset:
                return (False, f"R3 场景{scene}子集外色 {col}")
    if len(seen) > cap:
        return (False, f"R1 色数 {len(seen)} > {cap}")
    return (True, f"pass: {len(seen)} 色, scene={scene}")


# ---------------------------------------------------------------------------
# selftest：合成高分辨率图 → 跑全链路 → 校验通过
# ---------------------------------------------------------------------------
def selftest() -> int:
    import tempfile
    src = load_palette_source()
    print("== ADR-4 pixel_pipeline selftest ==")
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "raw_hr.png")
        # 合成一张 200×200 伪像素图：随机插值色（含母库内外色），加半透明边缘
        import random
        random.seed(7)
        c = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
        cp = c.load()
        pal = [tuple(v["rgb"]) for v in src["master_palette"].values()]
        for y in range(200):
            for x in range(200):
                if (x - 100) ** 2 + (y - 100) ** 2 < 90 ** 2:
                    cp[x, y] = pal[random.randrange(len(pal))] + (255,)
                else:
                    cp[x, y] = (0, 0, 0, 0)
        c.save(raw)

        # 硬化：selftest 写入临时 manifest，绝不污染 src 下真实 asset_manifest.csv
        tmp_manifest = os.path.join(tmp, "selftest_manifest.csv")
        init_manifest(tmp_manifest)

        for scene, size in [("upper", 24), ("mid", 24), ("upper", 16), ("boss", 32), ("sanctuary", 24)]:
            out = os.path.join(tmp, f"out_{scene}_{size}.png")
            row = process_one(raw, "mossback", scene, size, "idle", "digestABC", 20131,
                              src, category="char", out_dir=tmp, manifest_path=tmp_manifest)
            img = Image.open(row["asset_path"])
            passed, msg = validate_python(img, scene, src)
            print(f"  scene={scene} size={size}: color_count={row['color_count']} "
                  f"validate={passed} ({msg})")
            if not passed or row["color_count"] > 16:
                ok = False
    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="ADR-4 像素资产后处理链路")
    sub = p.add_subparsers(dest="cmd")

    sp = sub.add_parser("process-one", help="处理单张原始图")
    sp.add_argument("--raw", required=True)
    sp.add_argument("--slug", required=True)
    sp.add_argument("--scene", required=True, choices=["upper", "mid", "boss", "sanctuary"])
    sp.add_argument("--size", type=int, required=True, choices=VALID_SIZES)
    sp.add_argument("--variant", required=True)
    sp.add_argument("--digest", required=True)
    sp.add_argument("--seed", type=int, required=True)
    sp.add_argument("--category", default="char")
    sp.add_argument("--out-dir", default="assets")
    sp.add_argument("--no-dither", action="store_true")

    sub.add_parser("init-manifest", help="初始化 asset-manifest.csv 表头")
    sub.add_parser("selftest", help="跑内置自检（生成合成图→出 PNG-8→校验）")

    args = p.parse_args(argv)
    src = load_palette_source()

    if args.cmd == "selftest":
        return selftest()
    if args.cmd == "init-manifest":
        init_manifest()
        print(f"manifest 表头已写入 {MANIFEST_CSV}")
        return 0
    if args.cmd == "process-one":
        row = process_one(args.raw, args.slug, args.scene, args.size, args.variant,
                          args.digest, args.seed, src, args.category, args.out_dir,
                          dither=not args.no_dither)
        print(f"written: {row['asset_path']}  colors={row['color_count']}  sha256={row['checksum'][:12]}…")
        return 0
    p.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
