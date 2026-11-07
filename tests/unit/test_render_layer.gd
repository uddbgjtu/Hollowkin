extends GutTest

# Wave 3b 渲染层回归（headless Godot 4.3 + GUT 9.3.0 真跑）。
# 覆盖：逻辑网格 → 瓦片格映射的确定性、L 形走廊、屏外剔除、相机锚点、
#       同屏实体 ≤12 上限、TileMapLayer 真实 set_cell、MultiMesh 实例数、
#       粒子低档降密度，以及【DEBUG_PLACEHOLDER 资产纪律标记】。
#
# 【性质声明】本文件是结构 / 记账级断言，**不含任何性能测量数字**，
#   不把 cell 数或实例数换算成 ms，也不得据此关闭 architecture-doc.md §6 的 R1/R3。
#   debug 占位纹理不是 ADR-4 E1 资产；正式渲染基线仍待 E1 原图 + Wave 4 窗口实测。
# ADR-5：本文件不含任何全局随机调用。

const FloorGrid := preload("res://src/gameplay/render/floor_grid.gd")
const FloorTilemap := preload("res://src/gameplay/render/floor_tilemap.gd")
const EntityLayer := preload("res://src/gameplay/render/entity_layer.gd")
const BattleParticles := preload("res://src/gameplay/render/battle_particles.gd")


func _sample_layout() -> Dictionary:
    var spawns: Array = []
    for i in range(15):
        spawns.append({"x": 0, "y": 0, "tier": "mob"})
    return {
        "run_seed": 12345,
        "floor": 1,
        "rooms": [{"x": 5, "y": 5, "w": 4, "h": 3, "idx": 0}],
        "corridors": [{"ax": 6, "ay": 6, "bx": 10, "by": 9, "bend": 0}],
        "enemy_spawns": spawns,
        "loot": []
    }


func test_build_tiles_is_deterministic_and_counts_expected_cells() -> void:
    var layout: Dictionary = _sample_layout()
    var a: Dictionary = FloorGrid.build_tiles(layout)
    var b: Dictionary = FloorGrid.build_tiles(layout)
    assert_eq(a.size(), b.size(), "同 layout 两次构建格数一致")
    # 房间 12 格 + 走廊 8 格 - 交集 3 格 = 17 格
    assert_eq(a.size(), 17, "房间 4x3 + L 形走廊去重后应为 17 格")
    assert_eq(a.keys(), b.keys(), "格坐标集合逐项一致（确定性）")
    assert_eq(int(a[Vector2i(5, 5)]), FloorGrid.KIND_WALL, "房间边界为墙")
    assert_eq(int(a[Vector2i(6, 6)]), FloorGrid.KIND_CORRIDOR, "走廊覆盖房间内部格")
    assert_eq(int(a[Vector2i(9, 6)]), FloorGrid.KIND_CORRIDOR, "走廊横向延伸格")


func test_l_corridor_bend_variants() -> void:
    var tiles0: Dictionary = {}
    var tiles1: Dictionary = {}
    var c0: Dictionary = {"ax": 2, "ay": 2, "bx": 6, "by": 5, "bend": 0}
    var c1: Dictionary = {"ax": 2, "ay": 2, "bx": 6, "by": 5, "bend": 1}
    FloorGrid._carve_l_corridor(tiles0, c0)
    FloorGrid._carve_l_corridor(tiles1, c1)
    assert_true(tiles0.has(Vector2i(4, 2)), "bend=0 先横后竖：横段在 y=ay")
    assert_true(tiles0.has(Vector2i(6, 4)), "bend=0 竖段在 x=bx")
    assert_true(tiles1.has(Vector2i(2, 4)), "bend=1 先竖后横：竖段在 x=ax")
    assert_true(tiles1.has(Vector2i(4, 5)), "bend=1 横段在 y=by")
    assert_false(tiles0.has(Vector2i(2, 4)), "bend=0 不应出现 bend=1 的竖段位置")


func test_cull_tiles_drops_cells_outside_view() -> void:
    var layout: Dictionary = _sample_layout()
    var all_tiles: Dictionary = FloorGrid.build_tiles(layout)
    var view := Rect2i(0, 0, 9, 9)
    var vis: Dictionary = FloorGrid.cull_tiles(all_tiles, view)
    assert_eq(vis.size(), 12, "x>=9 的走廊格应被剔除，剩 12 格")
    for cell in vis.keys():
        var v: Vector2i = cell
        assert_true(view.has_point(v), "保留格必须落在视口内")


func test_view_rect_anchors_on_first_room_and_clamps_to_grid() -> void:
    var near: Dictionary = {"rooms": [{"x": 5, "y": 5, "w": 4, "h": 3}]}
    var far: Dictionary = {"rooms": [{"x": 52, "y": 17, "w": 6, "h": 7}]}
    assert_eq(FloorGrid.view_rect_for_layout(near), Rect2i(0, 0, 40, 16),
        "靠近左上时应钳到 (0,0)")
    assert_eq(FloorGrid.view_rect_for_layout(far), Rect2i(24, 9, 40, 16),
        "远端房间应把相机窗口平移到网格边界内")
    assert_eq(FloorGrid.default_view_rect().size, Vector2i(40, 16),
        "PC 横屏默认可见 40x16 格")


func test_visible_entities_capped_at_12_and_inside_view() -> void:
    var layout: Dictionary = _sample_layout()
    var view := Rect2i(0, 0, 9, 9)
    var ents: Array = FloorGrid.visible_entities(layout, view, FloorGrid.MAX_VISIBLE_ENTITIES)
    assert_eq(ents.size(), 12, "15 个 spawn 应按 R3 上限截为 12")
    assert_eq(FloorGrid.MAX_VISIBLE_ENTITIES, 12, "同屏敌人上限常量")
    for cell in ents:
        var v: Vector2i = cell
        assert_true(view.has_point(v), "可见实体必须在视口内")
    var none: Array = FloorGrid.visible_entities(layout, Rect2i(50, 50, 5, 5))
    assert_eq(none.size(), 0, "视口外应全部剔除")


func test_asset_discipline_marks_debug_placeholder() -> void:
    assert_eq(FloorGrid.ASSET_SOURCE, "DEBUG_PLACEHOLDER", "逻辑层显式标记非 E1 资产")
    assert_eq(FloorTilemap.ASSET_SOURCE, "DEBUG_PLACEHOLDER", "瓦片视图显式标记")
    assert_eq(EntityLayer.ASSET_SOURCE, "DEBUG_PLACEHOLDER", "实体视图显式标记")
    assert_eq(BattleParticles.ASSET_SOURCE, "DEBUG_PLACEHOLDER", "粒子层显式标记")


func test_tilemap_writes_only_visible_cells() -> void:
    var layout: Dictionary = _sample_layout()
    var view := Rect2i(0, 0, 9, 9)
    var tm = FloorTilemap.new()
    var written: int = tm.build_from_layout(layout, view)
    assert_eq(written, 12, "写入数应等于剔除后的可见格数")
    assert_eq(tm.get_used_cells().size(), 12, "TileMapLayer 真实 set_cell 12 格")
    assert_eq(tm.last_total_cells, 17, "剔除前总格数 17")
    assert_eq(tm.last_visible_cells, 12, "剔除后 12 格")
    assert_eq(tm.asset_source(), "DEBUG_PLACEHOLDER", "不冒充 E1 TileSet")
    var ts: TileSet = tm.tile_set
    assert_eq(ts.tile_size, Vector2i(16, 16), "美术圣经 16x16 瓦片")
    assert_eq(ts.get_source_count(), 1, "单一 atlas source")
    tm.free()


func test_multimesh_instance_count_matches_visible_entities() -> void:
    var layout: Dictionary = _sample_layout()
    var view := Rect2i(0, 0, 9, 9)
    var el = EntityLayer.new()
    var n: int = el.update_from_layout(layout, view)
    assert_eq(n, 12, "可见实体 12")
    assert_eq(el.last_visible, 12, "记录可见数")
    assert_eq(el.multimesh.visible_instance_count, 12, "MultiMesh 只提交 12 个实例")
    assert_eq(el.asset_source(), "DEBUG_PLACEHOLDER", "不冒充 E1 敌人贴图")
    el.free()


func test_particles_low_tier_halves_density() -> void:
    var p = BattleParticles.new()
    p.configure(false)
    assert_eq(p.amount, BattleParticles.BASE_AMOUNT, "常规档 24 粒子")
    assert_true(p.emitting, "Wave 3b 起粒子层真实启用")
    p.configure(true)
    assert_eq(p.amount, BattleParticles.LOW_AMOUNT, "低档降密度到 12")
    assert_eq(p.asset_source(), "DEBUG_PLACEHOLDER", "不冒充 E1 特效贴图")
    p.free()
