# ui_context.gd — UI 与领域层之间的共享上下文（Epic F）
# =====================================================================
# 持有当前 run 的领域对象引用，供各屏 bind() 消费。不持有任何随机/仿真状态，
# 仅作依赖注入容器（GDScript 无 DI 框架，借此解耦屏与具体模块构造）。
# 所有领域对象本身无随机（ADR-5）；combat 在进入地牢时由外部 setup 注入。
# =====================================================================

class_name UiContext
extends RefCounted

var pouch: Pouch = null
var bestiary: Bestiary = null
var vein_graph: VeinGraph = null
var party: PartyManager = null
var combat: CombatDirector = null
var run_seed: int = 0
var floor_index: int = 0
var ember: int = 0


func _init() -> void:
	# 构造安全的默认领域对象，外部可整体替换（如从存档恢复）。
	pouch = Pouch.new()
	bestiary = Bestiary.new()
	vein_graph = VeinGraph.new()
	party = PartyManager.new()


# 进入地牢：注入已 setup 的战斗主管（Epic C）。
func enter_dungeon(combat_director: CombatDirector) -> void:
	combat = combat_director
