#!/usr/bin/env bash
# 本地无头跑 GUT 单测（镜像 .github/workflows/test.yml 的 gut 步骤）。
# 前提：
#   1) PATH 含 godot 4.3（或用环境变量 GODOT=/abs/path/to/godot 指定）；
#   2) 本工程 addons/gut 已安装 GUT 9.3.0（CI 用 v9.3.0 tag 归档，本地同版本即可）。
# 流程与 test.yml 对齐：先生成全局类缓存，再跑 GUT。
# 用法：bash tools/ci/run_gut_tests.sh
set -euo pipefail

cd "$(dirname "$0")/../.." || exit 1   # 切到仓库根
GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "ERROR: 未找到 godot（需 Godot 4.3）。请安装并加入 PATH，或用 GODOT=/path/to/godot 指定。" >&2
  exit 1
fi
if [ ! -d addons/gut ]; then
  echo "ERROR: 未找到 addons/gut。请先安装 GUT 9.3.0（同 CI 所用 v9.3.0 tag 归档），再运行本脚本。" >&2
  exit 1
fi

# Godot 4.3 headless -s 不扫描注册 class_name，缺缓存会让 GUT 挂住不退出。
"$GODOT" --headless --path . -s res://tools/gen_global_class_cache.gd

"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit/ -gexit
