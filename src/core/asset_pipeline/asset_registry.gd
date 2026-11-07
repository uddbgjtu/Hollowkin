# asset_registry.gd — manifest 驱动的 E1 纹理加载（a 阶段渲染集成）
# =====================================================================
# 职责：唯一读取 asset_manifest.csv 真源，把 entity_slug 解析为已导入的
#       Texture2D，向 4 个渲染视图层（floor_tilemap / entity_layer /
#       battle_particles）提供真实 ADR-4 E1 PNG-8 资产，替换 DEBUG_PLACEHOLDER。
#
# 设计要点：
#   - 不加 class_name：保持 .godot/global_script_class_cache.cfg 仍为 40 类；
#     调用方一律 const preload 后调静态方法（与 floor_grid / floor_tilemap 等一致）。
#   - 静态惰性加载：首次 texture()/has() 才解析 CSV 并 load() 纹理，避免无谓 I/O；
#   - 缺件回退：slug 未登记 / 文件缺失 / load 失败 → 1×1 半透明白纹理 + push_warning，
#     绝不让调用方因缺件崩溃（headless 首次运行未导入时也能安全降级）；
#   - source() 统一返回 "E1_PNG8"，作为「已接真实资产」的纪律标记（区别于
#     DEBUG_PLACEHOLDER / LOGIC_LAYER），供 main.gd 闸门与 probe_runner 守卫读取。
#
# ADR-5：无全局随机。ADR-4：纹理来自已固化并提交 f1c79c2 的 E1 像素原图。
# =====================================================================

extends RefCounted

const MANIFEST_PATH := "res://src/core/asset_pipeline/asset_manifest.csv"

# CSV 列索引（asset_manifest.csv 表头顺序；以逗号分隔，值内无逗号）。
const COL_ASSET_PATH := 0
const COL_ENTITY_SLUG := 1

static var _map: Dictionary = {}        # slug -> res:// 相对路径（不含 res:// 前缀）
static var _loaded: bool = false
static var _warnings: Array = []         # 供冒烟测试回读缺件告警
static var _fallback: Texture2D = null   # 缺件回退纹理（惰性构造）


# 解析 CSV（跳过表头），建立 slug -> 资产路径 的映射。幂等。
static func _ensure_loaded() -> void:
    if _loaded:
        return
    _loaded = true
    var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    if f == null:
        _warn("manifest 缺失，无法登记 E1 资产: " + MANIFEST_PATH)
        return
    var header_skipped := false
    while not f.eof_reached():
        var line := f.get_line()
        if line.strip_edges() == "":
            continue
        if not header_skipped:
            header_skipped = true
            continue
        var cols := line.split(",")
        if cols.size() <= COL_ENTITY_SLUG:
            continue
        var slug: String = cols[COL_ENTITY_SLUG].strip_edges()
        var path: String = cols[COL_ASSET_PATH].strip_edges()
        if slug == "" or path == "":
            continue
        _map[slug] = path
    f.close()


# slug 是否已登记（无论文件是否真实可加载）。
static func has(slug: String) -> bool:
    _ensure_loaded()
    return _map.has(slug)


# 解析为 Texture2D；任意缺件环节回退并告警，绝不返回 null 导致调用方崩溃。
static func texture(slug: String) -> Texture2D:
    _ensure_loaded()
    if not _map.has(slug):
        _warn("E1 资产缺件（slug 未登记 manifest）: " + slug)
        return _fallback_texture()
    var res_path := "res://" + str(_map[slug])
    if not ResourceLoader.exists(res_path):
        _warn("E1 资产文件缺失（未导入？）: " + res_path)
        return _fallback_texture()
    var tex: Texture2D = load(res_path) as Texture2D
    if tex == null:
        _warn("E1 资产加载失败: " + res_path)
        return _fallback_texture()
    return tex


# 纪律标记：本注册表供给的是 ADR-4 E1 真实像素原图（已提交 f1c79c2）。
static func source() -> String:
    return "E1_PNG8"


# 回读缺件告警（供 headless 冒烟测试断言与人工巡检）。
static func warnings() -> Array:
    return _warnings


static func _fallback_texture() -> Texture2D:
    if _fallback == null:
        var img := Image.create_empty(1, 1, true, Image.FORMAT_RGBA8)
        img.fill(Color(1.0, 1.0, 1.0, 0.5))
        _fallback = ImageTexture.create_from_image(img)
    return _fallback


static func _warn(msg: String) -> void:
    _warnings.append(msg)
    push_warning("[AssetRegistry] " + msg)
