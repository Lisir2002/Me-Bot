#!/usr/bin/env python3
"""l10n 护栏（check_l10n）：arb 一致性 / 元数据完备性 / 死键检测。

规则矩阵（error=CI 咬死，warn=可见不阻塞）：
  R1  三份 arb（en 模板 + zh + zh_Hant）键集与 en 完全一致            error
  R2  值含 {param} ⇒ 必有 @key 且 placeholders 名单与值匹配          error
  R3  @placeholders 中的名字必须出现在值里（死占位符）               error
  R4  键名驼峰规范（^_?[a-z]+([A-Z][a-zA-Z0-9]*)+$）                warn
  R5  死键：lib/（排除 lib/l10n/）代码零引用 → 清单                  warn
  R6  无空翻译值（空串/空白 = 未翻译）                              error

用法：python3 tools/check_l10n.py [--l10n-dir lib/l10n] [--lib-dir lib]
退出码：有 error 时 1，否则 0。
"""
import argparse
import glob
import json
import os
import re
import sys

PARAM_RE = re.compile(r"\{([a-zA-Z_][a-zA-Z0-9_]*)\}")
CAMEL_RE = re.compile(r"^_?[a-z]+([A-Z][a-zA-Z0-9]*)+$")
REF_RE_CACHE: dict = {}


def load(l10n_dir: str, name: str):
    p = os.path.join(l10n_dir, name)
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def split_keys(d: dict):
    keys = {k for k in d if not k.startswith("@")}
    metas = {k[1:] for k in d if k.startswith("@")}
    return keys, metas


def build_ref_index(lib_dir: str) -> str:
    """把 lib/ 下全部 dart 源码（排除 gen 产物）拼成一个大字符串用于引用检测。"""
    chunks = []
    for p in glob.glob(os.path.join(lib_dir, "**", "*.dart"), recursive=True):
        norm = p.replace(os.sep, "/")
        if "/l10n/" in norm:
            continue
        with open(p, encoding="utf-8", errors="ignore") as f:
            chunks.append(f.read())
    return "\n".join(chunks)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--l10n-dir", default="lib/l10n")
    ap.add_argument("--lib-dir", default="lib")
    args = ap.parse_args()

    errors: list = []
    warns: list = []

    en = load(args.l10n_dir, "app_en.arb")
    zh = load(args.l10n_dir, "app_zh.arb")
    hant = load(args.l10n_dir, "app_zh_Hant.arb")
    if en is None:
        print("[FATAL] 缺少模板 app_en.arb")
        return 1
    en_keys, en_meta = split_keys(en)
    others = {"zh": zh, "zh_Hant": hant}

    # R1 键集一致
    for name, d in others.items():
        if d is None:
            errors.append(f"R1: 缺少 {name} 的 arb 文件")
            continue
        keys, _ = split_keys(d)
        missing = en_keys - keys
        extra = keys - en_keys
        for k in sorted(missing):
            errors.append(f"R1: {name} 缺键 {k}")
        for k in sorted(extra):
            errors.append(f"R1: {name} 多出键 {k}（en 模板中不存在）")

    # R2/R3 占位符与元数据
    for k in sorted(en_keys):
        params = set(PARAM_RE.findall(en[k]))
        if params:
            if k not in en_meta:
                errors.append(f"R2: {k} 带 {sorted(params)} 但缺 @key/placeholders 元数据")
            else:
                ph = set(en["@" + k].get("placeholders", {}))
                miss = params - ph
                if miss:
                    errors.append(f"R2: {k} 值含 {sorted(miss)} 但 placeholders 未声明")
        meta = en.get("@" + k, {}).get("placeholders", {})
        dead = set(meta) - set(PARAM_RE.findall(en[k]))
        if dead:
            errors.append(f"R3: {k} placeholders {sorted(dead)} 未出现在值中")

    # R4 命名规范（warn）
    for k in sorted(en_keys):
        if not CAMEL_RE.match(k):
            warns.append(f"R4: 键名不符合驼峰规范：{k}")

    # R5 死键（warn）
    corpus = build_ref_index(args.lib_dir)
    dead_keys = []
    for k in sorted(en_keys):
        if not re.search(r"\." + re.escape(k) + r"\b", corpus):
            dead_keys.append(k)
    for k in dead_keys:
        warns.append(f"R5: 死键（代码零引用）：{k}")

    # R6 空翻译
    for name, d in [("en", en)] + [(n, d) for n, d in others.items() if d]:
        keys, _ = split_keys(d)
        for k in sorted(keys):
            v = d[k]
            if not isinstance(v, str) or not v.strip():
                errors.append(f"R6: {name} 键 {k} 为空翻译")

    # 汇总
    print(f"[check_l10n] keys={len(en_keys)} (en 模板)")
    if warns:
        print(f"\n===== WARN ({len(warns)}) =====")
        for w in warns:
            print("  " + w)
    if errors:
        print(f"\n===== ERROR ({len(errors)}) =====")
        for e in errors:
            print("  " + e)
        print("\n结果：FAIL（error 级问题必须修复）")
        return 1
    print("\n结果：PASS" + (f"（{len(warns)} 条 warn 待治理）" if warns else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
