# battle_particles.gd — 浮尘粒子层参数与低档降密度（Wave 3b）
# =====================================================================
# 参数来源（均为设计规格，非测量值）：
#   - art-bible.md §视觉锚点：夜靛背景、青绿/蜜黄浮尘缓慢上浮；
#   - prototype-r1r3-report.md §3 / feasibility-review.md §5：粒子 <3ms 目标、
#     低档降密度（R3 缓解④）；
#   - battle_screen.tscn 原节点 amount=24 / lifetime=1.2。
#
# 【资产纪律 · a 阶段已接 E1】CPUParticles2D 点精灵纹理改由 asset_registry.gd 提供
#   真实 E1 像素原图（暂复用 upper_floor 瓦片作点精灵，专属特效贴图待美术圣经终稿），
#   ASSET_SOURCE = E1_PNG8。已登记 manifest 并提交 f1c79c2；正式 GPU 帧预算基线仍待 (a)+ PC 实测（G1）。
#
# 刻意不加 class_name（保持全局类缓存 40 类）；调用方 const preload。
# ADR-5：无全局随机（粒子随机由引擎内部处理，非本脚本调用全局 RNG）。
# =====================================================================

extends CPUParticles2D

const AssetRegistry := preload("res://src/core/asset_pipeline/asset_registry.gd")

const ASSET_SOURCE := "E1_PNG8"
const BASE_AMOUNT := 24
const LOW_AMOUNT := 12
const C_DUST := Color(0.45, 0.80, 0.72, 0.70)

var low_tier: bool = false


func _ready() -> void:
    configure(false)
    # a 阶段：点精灵接真实 E1 纹理（复用瓦片，专属特效贴图待后续）。
    texture = AssetRegistry.texture("upper_floor")


# 低档把粒子数减半（R3 缓解④：连续超预算时由主循环调用 configure(true)）。
func configure(p_low_tier: bool) -> void:
    low_tier = p_low_tier
    amount = LOW_AMOUNT if low_tier else BASE_AMOUNT
    lifetime = 1.2
    one_shot = false
    preprocess = 0.0
    explosiveness = 0.0
    randomness = 0.4
    direction = Vector2(0.0, -1.0)
    spread = 30.0
    gravity = Vector2(0.0, -6.0)
    initial_velocity_min = 8.0
    initial_velocity_max = 18.0
    scale_amount_min = 1.0
    scale_amount_max = 2.0
    color = C_DUST
    emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
    emission_rect_extents = Vector2(560.0, 220.0)
    emitting = true


func asset_source() -> String:
    return ASSET_SOURCE
