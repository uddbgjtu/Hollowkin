#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CI lint: 禁止 GDScript 全局随机调用 (ADR-5 / CLAUDE.md §4)
============================================================

目的
----
ADR-5 规定随机性单一出口：所有随机必须经由 RNGService（src/core/rng/rng_service.gd）
派生的种子化 RandomNumberGenerator 实例。禁止在 GDScript 中直接使用全局随机函数：
    randf()  randi()  randf_range()  randi_range()  randomize()
（CLAUDE.md §4 禁止项，违者 CI 拦截）。

放行白名单
----------
- src/core/rng/rng_service.gd：RNGService 单一出口封装本身（路径包含 rng_service.gd 即跳过）。
- 路径含 /test/ /tests/ /spec/ /specs/ /addons/：测试与第三方插件目录。
- 实例方法 rng.randf() / rng.randi() 等：因前置 '.'，被负向后顾（negative lookbehind）排除。

退出码
------
- 0：未检出全局随机调用（ADR-5 纪律通过）
- 1：检出全局随机调用（阻断 CI），或无法读取文件（警告但仍 exit 1 以引起注意）

用法
----
    python tools/ci/lint_no_global_random.py --root .
"""

import os
import re
import sys
import argparse

# 全局随机入口（禁项）。实例方法 rng.randf() 等因前置 '.' 被负向后顾排除。
PATTERNS = [
    re.compile(r"(?<!\.)randf_range\("),
    re.compile(r"(?<!\.)randi_range\("),
    re.compile(r"(?<!\.)randf\("),
    re.compile(r"(?<!\.)randi\("),
    re.compile(r"(?<!\.)randomize\("),
]

# 放行白名单：路径包含以下子串的文件跳过（RNGService 单一出口 + 测试/桩）
EXCLUDE_PATH_SUBSTR = [
    "rng_service.gd",
    "/test/",
    "/tests/",
    "/spec/",
    "/specs/",
    "/addons/",
]


def is_excluded(path: str) -> bool:
    norm = path.replace("\\", "/")
    return any(sub in norm for sub in EXCLUDE_PATH_SUBSTR)


def strip_comment(line: str) -> str:
    """GDScript 行注释以 # 起；字符串内一般不含裸 #，简单截断即可。"""
    return line.split("#", 1)[0]


def scan_file(path: str):
    hits = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for i, raw in enumerate(f, 1):
                code = strip_comment(raw)
                for pat in PATTERNS:
                    if pat.search(code):
                        hits.append((i, pat.pattern))
    except Exception as e:  # noqa: BLE001
        print("WARN cannot read %s: %s" % (path, e))
        # 读取失败也视为异常，交由调用方决定是否阻断（这里返回 hits 不变，但 caller 会标记）
        raise
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ban global random calls in GDScript (ADR-5)."
    )
    parser.add_argument(
        "--root",
        default=".",
        help="project root to scan for *.gd files (default: cwd)",
    )
    args = parser.parse_args()
    root = args.root

    found_any = False
    scanned = 0
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if not fn.endswith(".gd"):
                continue
            full = os.path.join(dirpath, fn)
            if is_excluded(full):
                continue
            scanned += 1
            try:
                hits = scan_file(full)
            except Exception:  # noqa: BLE001
                found_any = True
                print("%s:0: ERROR cannot read file" % full)
                continue
            for ln, pat in hits:
                found_any = True
                print("%s:%d: 命中全局随机禁项 %s" % (full, ln, pat))

    if found_any:
        print(
            "FAIL: 发现 GDScript 全局随机调用（应改走 "
            "RNGService.new_floor_rng() 的种子化实例）"
        )
        return 1

    print(
        "OK: 扫描 %d 个 .gd 文件，未检出全局随机调用（ADR-5 纪律通过）"
        % scanned
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
