# floor_tilemap.gd — TileMapLayer 真实接入（Wave 3b 视图层）
# =====================================================================
# 职责：运行时构建 TileSet（3 个 atlas tile），把 FloorGrid 的格坐标经
#       TileMapLayer.set_cell() 写入；写入范围已由 cull_tiles() 屏外剔除，
#       对应 R1「批量 set_cell 渲染尖峰」与 R3「离屏剔除」缓解。
#
# 【资产纪律 · 先读】这里用的 48×16 PNG 是**运行时程序化纯色 debug 占位**，
#   显式标记 ASSET_SOURCE = DEBUG_PLACEHOLDER：
#     - 不是 ADR-4 的 E1 真实像素原图，未跑 pixel_pipeline.py，
#       未登记 asset_manifest.csv，未生成任何 PNG 文件；
#     - 颜色只作结构区分，不代表美术圣经的最终视觉；
#     - 以它为纹理测出的耗时**不能**充当正式 GPU 帧预算基线。
#   E1 原图到位后，替换 _build_debug_tileset() 的 texture 即可，
#   FloorGrid 的格映射与剔除逻辑无需改动。
#
# 刻意不加 class_name（保持全局类缓存 40 类）；调用方 const preload。
# ADR-5：无全局随机。
# =====================================================================

extends TileMapLayer

const FloorGrid := preload("res://src/gameplay/render/floor_grid.gd")

const ASSET_SOURCE := "DEBUG_PLACEHOLDER"
const ATLAS_W := 3
const TILE_PX_I := 16

# debug 占位色（仅用于区分 floor / wall / corridor，非正式美术资产）
const C_FLOOR := Color(0.169, 0.227, 0.400, 1.0)
const C_WALL := Color(0.102, 0.110, 0.173, 1.0)
const C_CORRIDOR := Color(0.290, 0.480, 0.510, 1.0)

var last_total_cells: int = 0
var last_visible_cells: int = 0
var _atlas_source: TileSetAtlasSource = null


func _init() -> void:
    _build_debug_tileset()


func _build_debug_tileset() -> void:
    var img: Image = Image.create_empty(
        ATLAS_W * TILE_PX_I, TILE_PX_I, false, Image.FORMAT_RGBA8)
    img.fill_rect(Rect2i(0, 0, TILE_PX_I, TILE_PX_I), C_FLOOR)
    img.fill_rect(Rect2i(TILE_PX_I, 0, TILE_PX_I, TILE_PX_I), C_WALL)
    img.fill_rect(Rect2i(TILE_PX_I * 2, 0, TILE_PX_I, TILE_PX_I), C_CORRIDOR)
    var tex: ImageTexture = ImageTexture.create_from_image(img)

    var atlas := TileSetAtlasSource.new()
    atlas.texture = tex
    atlas.texture_region_size = Vector2i(TILE_PX_I, TILE_PX_I)
    atlas.create_tile(Vector2i(0, 0))
    atlas.create_tile(Vector2i(1, 0))
    atlas.create_tile(Vector2i(2, 0))

    var ts := TileSet.new()
    ts.tile_size = Vector2i(TILE_PX_I, TILE_PX_I)
    ts.add_source(atlas, 0)
    tile_set = ts
    _atlas_source = atlas
    # ADR-4 filter=false 的等价：调试纹理按最近邻采样，禁止插值糊边。
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


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
