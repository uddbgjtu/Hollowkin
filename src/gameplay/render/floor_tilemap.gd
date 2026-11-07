# floor_tilemap.gd — TileMapLayer 真实接入（Wave 3b 视图层）
# =====================================================================
# 职责：运行时构建 TileSet（3 个 atlas tile），把 FloorGrid 的格坐标经
#       TileMapLayer.set_cell() 写入；写入范围已由 cull_tiles() 屏外剔除，
#       对应 R1「批量 set_cell 渲染尖峰」与 R3「离屏剔除」缓解。
#
# 【资产纪律 · a 阶段已接 E1】这里用的 48×16 atlas 由 3 张 ADR-4 E1 真实
#   像素原图（upper_floor / upper_wall / mid_floor）在运行时合成，经
#   asset_manifest.csv + asset_registry.gd 加载，ASSET_SOURCE = E1_PNG8：
#     - 已跑 pixel_pipeline.py、已登记 asset_manifest.csv（14 列）、已生成 PNG-8
#       并提交 f1c79c2；纹理来自已固化真源，非程序化占位；
#     - 仍属「结构/记账级」视图：正式 GPU 帧预算基线须 (a)+ 带 GPU 的 PC 窗口
#       实测（G1），本层不持有、也不冒充任何性能测量数字。
#   FloorGrid 的格映射与剔除逻辑未改动，仅视图纹理来源由占位切换为 E1。
#
# 刻意不加 class_name（保持全局类缓存 40 类）；调用方 const preload。
# ADR-5：无全局随机。
# =====================================================================

extends TileMapLayer

const FloorGrid := preload("res://src/gameplay/render/floor_grid.gd")
const AssetRegistry := preload("res://src/core/asset_pipeline/asset_registry.gd")

const ASSET_SOURCE := "E1_PNG8"
const ATLAS_W := 3
const TILE_PX_I := 16

# 格 kind -> E1 资产 slug 映射（atlas 第 kind 列）。corridor 暂复用 mid_floor
# 作视觉区分；逐 tile 美术细化待美术圣经终稿（ADR-4）。
const KIND_SLUG := ["upper_floor", "upper_wall", "mid_floor"]

var last_total_cells: int = 0
var last_visible_cells: int = 0
var _atlas_source: TileSetAtlasSource = null


func _init() -> void:
    _build_e1_tileset()


func _build_e1_tileset() -> void:
    var img := Image.create_empty(
        ATLAS_W * TILE_PX_I, TILE_PX_I, false, Image.FORMAT_RGBA8)
    for kind in range(KIND_SLUG.size()):
        var slug: String = KIND_SLUG[kind]
        var tex: Texture2D = AssetRegistry.texture(slug)
        var tile_img: Image = _tile_image(tex)
        img.blit_rect(tile_img, Rect2i(0, 0, TILE_PX_I, TILE_PX_I),
            Vector2i(kind * TILE_PX_I, 0))
    var tex_atlas := ImageTexture.create_from_image(img)

    var atlas := TileSetAtlasSource.new()
    atlas.texture = tex_atlas
    atlas.texture_region_size = Vector2i(TILE_PX_I, TILE_PX_I)
    atlas.create_tile(Vector2i(0, 0))
    atlas.create_tile(Vector2i(1, 0))
    atlas.create_tile(Vector2i(2, 0))

    var ts := TileSet.new()
    ts.tile_size = Vector2i(TILE_PX_I, TILE_PX_I)
    ts.add_source(atlas, 0)
    tile_set = ts
    _atlas_source = atlas
    # ADR-4 filter=false 的等价：E1 像素原图按最近邻采样，禁止插值糊边。
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# 把任意 E1 纹理规整成 TILE_PX_I×TILE_PX_I 的 Image，供 atlas 合成。
# 瓦片源为 16×16 时直接使用；非 16×16（含缺件回退 1×1）时最近邻缩放，
# 避免 blit_rect 源矩形越界导致合成失败。
static func _tile_image(tex: Texture2D) -> Image:
    var src: Image = tex.get_image()
    if src == null:
        var blank := Image.create_empty(TILE_PX_I, TILE_PX_I, false, Image.FORMAT_RGBA8)
        blank.fill(Color(0.5, 0.5, 0.5, 1.0))
        return blank
    if src.get_size() != Vector2i(TILE_PX_I, TILE_PX_I):
        src = src.duplicate()
        src.resize(TILE_PX_I, TILE_PX_I, Image.INTERPOLATE_NEAREST)
    return src


# 由 main.gd 在切到地图屏时调用；返回写入的可见格数。
func build_from_layout(layout: Dictionary, view: Rect2i) -> int:
    clear()
    var all_tiles: Dictionary = FloorGrid.build_tiles(layout)
    var visible: Dictionary = FloorGrid.cull_tiles(all_tiles, view)
    for cell in visible.keys():
        var v: Vector2i = cell
        var kind: int = int(visible[v])
        set_cell(v, 0, Vector2i(kind, 0))
    last_total_cells = all_tiles.size()
    last_visible_cells = visible.size()
    return last_visible_cells


func asset_source() -> String:
    return ASSET_SOURCE
