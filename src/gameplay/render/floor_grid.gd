# floor_grid.gd — 逻辑网格 → 瓦片格 / 实体可见集（Wave 3b 纯逻辑层）
# =====================================================================
# 职责：把 DungeonGenerator.generate_sync() 产出的 rooms / corridors /
#       enemy_spawns 逻辑网格，映射成 TileMapLayer 可写的格坐标，并按视口
#       做屏外剔除（R3 缓解②）。本文件不含渲染节点、不持有纹理、不调用随机。
#
# 【资产纪律 · a 阶段】本层只处理「格坐标」，不产出任何美术资产，也不持有纹理，
#   故 ASSET_SOURCE 标记为 LOGIC_LAYER（区别于视图层的 E1_PNG8 / 旧占位 DEBUG_PLACEHOLDER）。
#   视图层 floor_tilemap.gd / entity_layer.gd / battle_particles.gd 现已接 E1 真实像素原图
#   （asset_manifest.csv + asset_registry.gd）；本层格映射与剔除逻辑无需改动。
#
# 刻意不加 class_name：保持 .godot/global_script_class_cache.cfg 仍为 40 类，
# 调用方一律 const preload。ADR-5：无全局随机。
# =====================================================================

extends RefCounted

const GRID_W := 64
const GRID_H := 64
const TILE_PX := 16.0                 # 美术圣经 §5：瓦片 16×16 整数倍拼接
const MAX_VISIBLE_ENTITIES := 12      # R3：同屏敌人 ≤12
const ASSET_SOURCE := "LOGIC_LAYER"   # 显式标记：纯逻辑层，不持纹理

const KIND_FLOOR := 0
const KIND_WALL := 1
const KIND_CORRIDOR := 2


static func _clamp_cell(x: int, y: int) -> Vector2i:
    return Vector2i(clampi(x, 0, GRID_W - 1), clampi(y, 0, GRID_H - 1))


# 返回 { Vector2i -> int(tile_kind) }；同格被后写者覆盖（走廊可穿墙形成门口）。
static func build_tiles(layout: Dictionary) -> Dictionary:
    var tiles: Dictionary = {}
    var rooms: Array = layout.get("rooms", [])
    for r in rooms:
        var room: Dictionary = r
        var rx: int = int(room["x"])
        var ry: int = int(room["y"])
        var rw: int = int(room["w"])
        var rh: int = int(room["h"])
        for yy in range(ry, ry + rh):
            for xx in range(rx, rx + rw):
                var border: bool = (xx == rx or xx == rx + rw - 1
                    or yy == ry or yy == ry + rh - 1)
                var kind: int = KIND_WALL if border else KIND_FLOOR
                tiles[_clamp_cell(xx, yy)] = kind
    var corridors: Array = layout.get("corridors", [])
    for c in corridors:
        _carve_l_corridor(tiles, c)
    return tiles


# L 形走廊：bend=0 先横后竖，bend=1 先竖后横（镜像 RoomStitcher 的 bend 语义）。
static func _carve_l_corridor(tiles: Dictionary, c: Dictionary) -> void:
    var ax: int = int(c["ax"])
    var ay: int = int(c["ay"])
    var bx: int = int(c["bx"])
    var by: int = int(c["by"])
    var x0: int = mini(ax, bx)
    var x1: int = maxi(ax, bx)
    var y0: int = mini(ay, by)
    var y1: int = maxi(ay, by)
    if int(c["bend"]) == 0:
        for xx in range(x0, x1 + 1):
            tiles[_clamp_cell(xx, ay)] = KIND_CORRIDOR
        for yy in range(y0, y1 + 1):
            tiles[_clamp_cell(bx, yy)] = KIND_CORRIDOR
    else:
        for yy in range(y0, y1 + 1):
            tiles[_clamp_cell(ax, yy)] = KIND_CORRIDOR
        for xx in range(x0, x1 + 1):
            tiles[_clamp_cell(xx, by)] = KIND_CORRIDOR


# 屏外剔除：只保留视口格矩形内的瓦片。
static func cull_tiles(tiles: Dictionary, view: Rect2i) -> Dictionary:
    var out: Dictionary = {}
    for cell in tiles.keys():
        var v: Vector2i = cell
        if view.has_point(v):
            out[v] = int(tiles[v])
    return out


# 可见实体：spawn 的 (x,y) 是房间内局部偏移，需叠加房间原点；按 R3 上限截断。
static func visible_entities(layout: Dictionary, view: Rect2i, limit: int = MAX_VISIBLE_ENTITIES) -> Array:
    var rooms: Array = layout.get("rooms", [])
    var spawns: Array = layout.get("enemy_spawns", [])
    var out: Array = []
    if rooms.is_empty():
        return out
    for i in range(spawns.size()):
        if out.size() >= limit:
            break
        var s: Dictionary = spawns[i]
        var room: Dictionary = rooms[i % rooms.size()]
        var cell: Vector2i = _clamp_cell(
            int(room["x"]) + int(s["x"]),
            int(room["y"]) + int(s["y"]))
        if view.has_point(cell):
            out.append(cell)
    return out


static func grid_to_px(cell: Vector2i) -> Vector2:
    return Vector2(float(cell.x) * TILE_PX, float(cell.y) * TILE_PX)


# 默认 PC 横屏视口可见格数：1280/32=40 列，内容区下部留给瓦片区。
static func default_view_rect() -> Rect2i:
    return Rect2i(0, 0, 40, 16)


# 相机锚点：以布局的首个房间为中心取可见窗口，并钳制在 64×64 网格内。
# 房间是随机散布的，固定看 (0,0) 会漏掉整层；真实游戏里相机跟随玩家/起点。
static func view_rect_for_layout(layout: Dictionary) -> Rect2i:
    var base: Rect2i = default_view_rect()
    var w: int = base.size.x
    var h: int = base.size.y
    var rooms: Array = layout.get("rooms", [])
    var anchor: Vector2i = Vector2i.ZERO
    if not rooms.is_empty():
        var r0: Dictionary = rooms[0]
        anchor = Vector2i(int(r0["x"]), int(r0["y"]))
    var ox: int = clampi(anchor.x - int(w / 2), 0, GRID_W - w)
    var oy: int = clampi(anchor.y - int(h / 2), 0, GRID_H - h)
    return Rect2i(ox, oy, w, h)
