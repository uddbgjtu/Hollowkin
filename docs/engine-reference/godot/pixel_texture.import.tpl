# =============================================================================
# ADR-4 · 像素资产导入预设模板（Godot 4 .import 格式）
# =============================================================================
# 来源：docs/art-bible/pixel-asset-pipeline.md §3.2 + ADR-4 决策原文。
# 用法：
#   这是单个资产 .import 文件的"目标态"模板。正式资产落入 assets/ 后由 Godot 生成
#   .import；在 Import 面板按下方高亮项设定后，提交生成的 .import 文件即可固化。
#   推荐改用"可复用 Import Preset + Apply to Folder"（见 VERSION.md §2.2），批量更稳。
#
# 关键 ADR-4 覆写（防偏色/渗色）：
#   compress/mode=0 或 1   filter=false   gen_mipmaps=false   detect_3d/compress_to=0
# + 推荐 process/fix_alpha_border=true 修补索引色透明边。
#
# 注意：本 .tpl 为模板，真实 .import 的 path/uid/<hash> 由 Godot 生成，勿手填。
# =============================================================================

[remap]

importer="texture"

; Godot 4 导入后类型（实际哈希路径由引擎生成）
type="CompressedTexture2D"
; uid="uid://bhollowkinchar"        ; ← 由 Godot 分配，提交时保留
; path="res://.godot/imported/char_mossback_idle_24.png-<hash>.ctex"  ; ← 引擎生成
metadata={"vram_texture":false}

[params]

compress/mode=0                ; ← ADR-4: 0=Lossless(体积小) 或 1=Uncompressed(像素最稳)。二选一，均禁 BPTC
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false         ; ← ADR-4: 关 mipmap，防止缩小渗色/串色
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true  ; ← 推荐: 修索引色 PNG-8 透明边 1px 脏边
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=0.0
detect_3d/compress_to=0        ; ← ADR-4: 关 3D 检测转换，防色彩空间偏色
detect_3d/min_size=0
editor/scale_with_editor_zoom=false
