# entity_layer.gd — MultiMeshInstance2D 批绘制 + 屏外剔除（Wave 3b 视图层）
# =====================================================================
# 职责：按 FloorGrid.visible_entities() 的可见集，用 MultiMesh 一次 draw call
#       批绘制同屏敌人；实例数硬上限 12（R3 缓解②）。
#
# 【资产纪律】16×16 纯色 debug 占位纹理（DEBUG_PLACEHOLDER），不是 E1 敌人贴图；
#   未跑 pixel_pipeline.py、未登记 manifest、未生成 PNG 文件，不得充当正式渲染基线。
#
# 刻意不加 class_name（保持全局类缓存 40 类）；调用方 const preload。
# ADR-5：无全局随机。
# =====================================================================

extends MultiMeshInstance2D

const FloorGrid := preload("res://src/gameplay/render/floor_grid.gd")

const ASSET_SOURCE := "DEBUG_PLACEHOLDER"
const MAX_VISIBLE := 12
const SPRITE_PX := 16.0
const C_ENTITY := Color(0.78, 0.36, 0.52, 1.0)

var last_visible: int = 0


func _init() -> void:
    var img: Image = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
    img.fill(C_ENTITY)
    var tex: ImageTexture = ImageTexture.create_from_image(img)

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
