# map_screen.gd — 地图屏（Epic F1 第 4 tab / ux-spec §2）
# =====================================================================
# 底部 Tab 第四槽（总览/灵囊/灵脉/地图）。完整地图渲染属 Epic B（DungeonGen）范围，
# 本屏仅以文字标签呈现当前层/种子等 run 状态（政务式清晰、弱图标），不臆造地图几何。
# 导航由底部 Tab 栏承担，本屏无独立交互热区。
# 无随机（ADR-5）。
# =====================================================================

class_name MapScreen
extends UiScreen

var view: Dictionary = {}


func _init() -> void:
	super._init("map")


func _build() -> void:
	_refresh()


func _refresh() -> void:
	if ctx == null:
		return
	view = {
		"floor": ctx.floor_index,
		"seed": ctx.run_seed,
		"ember": ctx.ember,
	}


func on_enter() -> void:
	active = true
	_refresh()
