#!/usr/bin/env python3
# =============================================================================
# ADR-4 · AI 原图预处理：白底转透明（prepare_raw.py）
# =============================================================================
# 背景：ImageGen 的 background="transparent" 在本机实际返回 RGB 纯白底图，
#       没有 alpha 通道。若直接喂给 pixel_pipeline.py，其 alpha 硬切
#       (downscale_nearest) 会把整张图当不透明，输出一整块方形色块而非
#       透明精灵，资产不可用。
#
# 定位：这是「AI 原图 → pixel_pipeline.py」之间的原图预处理环节，
#       只恢复透明通道，绝不修改调色板 / 描边 / 像素颜色
#       （CLAUDE.md §6 脚本唯一出口仍由 pixel_pipeline.py 承担）。
#
# 算法：① 从图像边界出发，对「近白」像素做 flood fill，只把与边界连通的
#       白色背景置为透明；角色内部封闭的白色高光保持不透明。
#       背景判定为 RGB 三通道均 >= 200；母库 19 色无一满足该条件
#       （最亮 parchment #F4E4C1 的 B=193 < 200），故不会误删资产色。
#       ② 按 alpha 包围盒裁剪，居中贴合到 768 的正方形透明画布
#       （--fit-grid）：AI 原图块大小与目标网格不整除时，NEAREST 降采样
#       会打散剪影；768 对 16/24/48 分别为 48/32/16 倍整数降采样，
#       同时留 10% 边距给 pipeline 的 1–2px 描边。此步只做裁切 / 整数倍
#       NEAREST 缩放，不改任何颜色、不补描边。
#
# 用法：python prepare_raw.py --src <gen.png> --out <rgba.png> --fit-grid 24
# =============================================================================

import argparse
import os

from PIL import Image, ImageChops, ImageDraw

CANVAS_SIDE = 768  # 对 16/24/48 分别为 48/32/16 倍，降采样均为整数倍
# 背景判定：三通道均 >= 200 的低饱和浅色。ImageGen 实际返回带渐变的灰白/米白
# 背景（角落采样 223~253），245 阈值只能抠掉约 20%。母库 19 色中没有任何一色
# 三通道都 >= 200（最亮 parchment #F4E4C1 的 B=193），故 200 不会误删资产色。
BACKGROUND_THRESHOLD = 200
EDGE_MARGIN = 0.80  # 角色最长边占画布比例；20% 余量给 pipeline 的 1–2px 描边


def near_white_mask(rgb: Image.Image, threshold: int = BACKGROUND_THRESHOLD) -> Image.Image:
    """255 = 近白（可抠），128 = 非近白（保留）。"""
    r, g, b = rgb.split()
    hit = lambda v: 255 if v >= threshold else 0
    m = ImageChops.multiply(ImageChops.multiply(r.point(hit), g.point(hit)), b.point(hit))
    return m.point(lambda v: 255 if v == 255 else 128)


def fit_to_grid(rgba: Image.Image, size: int) -> Image.Image:
    """裁到 alpha 包围盒 → 整数倍 NEAREST 缩放 → 居中贴到 size*32 正方形。"""
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("no opaque pixel after background removal")
    cropped = rgba.crop(bbox)
    side = CANVAS_SIDE
    longest = max(cropped.size)
    scale = (side * EDGE_MARGIN) / longest
    nw = max(1, int(round(cropped.width * scale)))
    nh = max(1, int(round(cropped.height * scale)))
    scaled = cropped.resize((nw, nh), Image.NEAREST)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(scaled, ((side - nw) // 2, (side - nh) // 2))
    return canvas


def remove_white_background(src_path: str, out_path: str,
                            threshold: int = BACKGROUND_THRESHOLD,
                            fit_grid: int = 0) -> dict:
    im = Image.open(src_path)
    if im.mode == "RGBA":
        a = im.getchannel("A")
        if sum(a.histogram()[:128]) > 0 and fit_grid == 0:
            # 已经带透明通道且无需网格对齐，不做二次处理
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            im.save(out_path)
            return {"mode": "kept_existing_alpha", "transparent_ratio": None}
    rgb = im.convert("RGB")
    mask = near_white_mask(rgb, threshold)
    w, h = rgb.size

    # 从四条边界的所有近白像素作为种子做 flood fill（thresh=0 → 只匹配 255）
    pts = [(x, 0) for x in range(w)]
    pts += [(x, h - 1) for x in range(w)]
    pts += [(0, y) for y in range(h)]
    pts += [(w - 1, y) for y in range(h)]
    mp = mask.load()
    for x, y in pts:
        if mp[x, y] == 255:
            ImageDraw.floodfill(mask, (x, y), 0, thresh=0)

    alpha = mask.point(lambda v: 0 if v == 0 else 255)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)

    info = {"mode": "white_background_removed", "source_size": [w, h]}
    if fit_grid:
        bbox = alpha.getbbox()
        info["alpha_bbox"] = list(bbox) if bbox else None
        out = fit_to_grid(out, fit_grid)
        info["fit_grid"] = fit_grid
        info["canvas_size"] = list(out.size)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path, optimize=True)

    hist = out.getchannel("A").histogram()
    transparent = sum(hist[:128])
    info["transparent_ratio"] = round(transparent / (out.width * out.height), 4)
    info["opaque_px"] = out.width * out.height - transparent
    return info


def main() -> int:
    p = argparse.ArgumentParser(description="ADR-4 原图预处理：白底转透明 + 网格对齐")
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--threshold", type=int, default=BACKGROUND_THRESHOLD)
    p.add_argument("--fit-grid", type=int, default=0,
                   help="目标网格尺寸 16/24/32/48；0 表示不做网格对齐")
    a = p.parse_args()
    r = remove_white_background(a.src, a.out, a.threshold, a.fit_grid)
    print("prepared:", a.out, r)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
