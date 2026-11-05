#!/usr/bin/env bash
# 本地无头跑 GUT 单测（镜像 .github/workflows/test.yml 的 gut 步骤）。
# 前提：
#   1) PATH 含 godot 4.3（或用环境变量 GODOT=/abs/path/to/godot 指定）；
#   2) 本工程 addons/gut 已通过 Godot 编辑器 AssetLib 安装（GUT 9.x，Godot 4 兼容）。
# 用法：bash tools/ci/run_gut_tests.sh
set -euo pipefail

cd "$(dirname "$0")/../.." || exit 1   # 切到仓库根
GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "ERROR: 未找到 godot（需 Godot 4.3）。请安装并加入 PATH，或用 GODOT=/path/to/godot 指定。" >&2
  exit 1
fi
if [ ! -d addons/gut ]; then
  echo "ERROR: 未找到 addons/gut。请先在 Godot 编辑器经 AssetLib 安装 GUT 9.x（Godot 4 兼容），再运行本脚本。" >&2
  exit 1
fi

"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit/ -gexit
