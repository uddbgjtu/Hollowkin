# entity_layer.gd — MultiMeshInstance2D 批绘制 + 屏外剔除（Wave 3b 视图层）
# =====================================================================
# 职责：按 FloorGrid.visible_entities() 的可见集，用 MultiMesh 一次 draw call
#       批绘制同屏敌人；实例数硬上限 12（R3 缓解②）。
#
# 【资产纪律 · a 阶段已接 E1】实体 MultiMesh 纹理改由 asset_registry.gd 提供真实
#   E1 角色像素原图（暂统一用 tamer 作代表；逐实体差异化贴图待后续），ASSET_SOURCE = E1_PNG8。
#   已登记 manifest、已生成 PNG-8 并提交 f1c79c2；正式 GPU 帧预算基线仍待 (a)+ PC 实测（G1）。
#
# 刻意不加 class_name（保持全局类缓存 40 类）；调用方 const preload。
# ADR-5：无全局随机。
# =====================================================================

extends MultiMeshInstance2D

const FloorGrid := preload("res://src/gameplay/render/floor_grid.gd")
const AssetRegistry := preload("res://src/core/asset_pipeline/asset_registry.gd")

const ASSET_SOURCE := "E1_PNG8"
const MAX_VISIBLE := 12
const SPRITE_PX := 16.0

var last_visible: int = 0


func _init() -> void:
    # a 阶段：实体纹理接真实 E1 角色像素原图（tamer 作代表，差异化待后续）。
    var tex: Texture2D = AssetRegistry.texture("tamer")

    var quad := QuadMesh.new()
    quad.size = Vector2(SPRITE_PX, SPRITE_PX)
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_2D
    mm.mesh = quad
    mm.instance_count = MAX_VISIBLE
    multimesh = mm
    texture = tex
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func update_from_layout(layout: Dictionary, view: Rect2i) -> int:
    var cells: Array = FloorGrid.visible_entities(layout, view, MAX_VISIBLE)
    var mm: MultiMesh = multimesh
    for i in range(MAX_VISIBLE):
        if i < cells.size():
            var c: Vector2i = cells[i]
            var px: Vector2 = FloorGrid.grid_to_px(c)
            mm.set_instance_transform_2d(i, Transform2D(0.0, px))
        else:
            # 零缩放 + 移出视野：不额外占 draw call，也避免残留实例闪烁。
            mm.set_instance_transform_2d(i,
                Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2(-9999.0, -9999.0)))
    mm.visible_instance_count = cells.size()
    last_visible = cells.size()
    return last_visible


func asset_source() -> String:
    return ASSET_SOURCE
