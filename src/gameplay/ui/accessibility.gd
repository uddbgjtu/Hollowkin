# accessibility.gd — 可访问性 Basic 助手（accessibility-requirements.md §3 / F5）
# =====================================================================
# 静态助手：字号钳制、CVD 安全校验、状态双编码标签（形状 + 色相）。
# 不依赖任何随机（ADR-5）。纯数据，确定可测。
# 矩阵与美术圣经 §2.2 / §3 / §4 同源，本文件为分级权威（见 accessibility-requirements.md §0）。
# =====================================================================

class_name Accessibility
extends RefCounted

const MIN_TOUCH := 48          # a11y §3.2 触控目标下限
const BODY_MIN := 14           # a11y §3.5 正文下限
const TITLE_MIN := 18          # a11y §3.5 标题下限
const DANGER_RED := "#FF4D4D"
const PURE_GREEN := "#00FF00"

# CVD 安全母库子集（美术圣经 §2.2）：危险红配形状，毒绿仅辅助（a11y §3.3）。
const CVD_PALETTE := {
	"danger": "#FF4D4D",
	"debuff": "#9B59FF",
	"trap": "#FFB000",
	"interactable": "#4DD0A1",
	"safe": "#4DA6FF",
	"lock": "#9AA0A6",
}


# 正文 ≥14px、标题 ≥18px（a11y §3.5）。
static func clamp_font(size: int, is_title: bool) -> int:
	return max(size, TITLE_MIN if is_title else BODY_MIN)


# 色盲安全：危险红必须配形状提示；禁止纯红 vs 纯绿对立（a11y §3.3）。
static func is_cvd_safe(color_hex: String, has_shape_cue: bool) -> bool:
	if color_hex == DANGER_RED and not has_shape_cue:
		return false
	if color_hex == PURE_GREEN:
		# 纯剧毒绿不得作为唯一编码（须配形状）
		return has_shape_cue
	return true


# 状态双编码标签：形状 + 色相（不依赖配色 alone，a11y §3.1）。
# 灵脉节点状态：active=星、available=高亮、locked=锁（ux-spec §3.3 形状而非亮度）。
static func dual_code(state: String) -> Dictionary:
	match state:
		"debuff":
			return {"shape": "triangle", "color": CVD_PALETTE["debuff"]}
		"trap":
			return {"shape": "zigzag", "color": CVD_PALETTE["trap"]}
		"interactable":
			return {"shape": "rounded", "color": CVD_PALETTE["interactable"]}
		"low_hp":
			return {"shape": "heart", "color": DANGER_RED, "border": true}
		"locked":
			return {"shape": "lock", "color": CVD_PALETTE["lock"]}
		"active":
			return {"shape": "star", "color": CVD_PALETTE["safe"]}
		"available":
			return {"shape": "highlight", "color": CVD_PALETTE["interactable"]}
		_:
			return {"shape": "none", "color": "#FFFFFF"}
