#!/usr/bin/env python3
"""Extract CraftTreeDB from AtlasLoot Database/Spells.lua"""
import re, json, sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPELLS = ROOT / "_vendor" / "AtlasLoot" / "Database" / "Spells.lua"
OUT = ROOT / "Data" / "Recipes.lua"
SOURCES_IN = ROOT / "_vendor" / "AtlasLoot" / "Database" / "TooltipStrings.lua"
SOURCES_OUT = ROOT / "Data" / "Sources.lua"

def extract_sources():
    src = SOURCES_IN.read_text(encoding="utf-8", errors="replace")
    def resolve_expr(expr):
        def repl(m):
            return m.group(1)
        s = re.sub(r'AL\["([^"]+)"\]', repl, expr)
        parts = re.split(r"\s*\.\.\s*", s)
        out = []
        for p in parts:
            p = p.strip().rstrip(",")
            if (p.startswith('"') and p.endswith('"')) or (p.startswith("'") and p.endswith("'")):
                out.append(p[1:-1])
            else:
                out.append(p)
        return "".join(out)

    skill_re = re.compile(
        r"^(?P<prof>.+?)\s*\(\s*(?:Skill:\s*)?(?P<skill>\d+\+?)\s*\)\s*$",
        re.I,
    )
    parsed = {}
    for m in re.finditer(r"\[(\d+)\]\s*=\s*(.+)", src):
        iid = int(m.group(1))
        text = resolve_expr(m.group(2)).strip()
        sm = skill_re.match(text)
        if sm:
            parsed[iid] = {
                "profession": sm.group("prof").strip(),
                "skill": sm.group("skill"),
                "text": text,
            }

    lines = [
        "-- Auto-generated from AtlasLoot Database/TooltipStrings.lua",
        "-- Do not edit by hand; regenerate with tools/extract_atlasloot.py",
        "CraftTreeSources = {",
    ]
    for iid in sorted(parsed):
        p = parsed[iid]
        prof = p["profession"].replace("\\", "\\\\").replace('"', '\\"')
        skill = p["skill"].replace("\\", "\\\\").replace('"', '\\"')
        text = p["text"].replace("\\", "\\\\").replace('"', '\\"')
        lines.append(
            f'  [{iid}] = {{profession="{prof}", skill="{skill}", text="{text}"}},'
        )
    lines.append("}")
    lines.append(f"-- entries: {len(parsed)}")
    SOURCES_OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {SOURCES_OUT} ({len(parsed)} sources)")


def main():
    text = SPELLS.read_text(encoding="utf-8", errors="replace")
    start = text.find('["craftspells"]')
    i = text.find("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                chunk = text[i : j + 1]
                break
    entry_re = re.compile(r"\[(\d+)\]\s*=\s*\{", re.M)
    entries = []
    for m in entry_re.finditer(chunk):
        spell = int(m.group(1))
        k = m.end() - 1
        d = 0
        for j in range(k, len(chunk)):
            if chunk[j] == "{":
                d += 1
            elif chunk[j] == "}":
                d -= 1
                if d == 0:
                    body = chunk[k : j + 1]
                    break
        item_m = re.search(r'\["craftItem"\]\s*=\s*(\d+)', body)
        if not item_m:
            continue
        item = int(item_m.group(1))
        qmin = re.search(r'\["craftQuantityMin"\]\s*=\s*(\d+)', body)
        name_m = re.search(r'\["name"\]\s*=\s*AL\["([^"]+)"\]', body) or re.search(
            r'\["name"\]\s*=\s*"([^"]+)"', body
        )
        reagents = []
        rm = re.search(r'\["reagents"\]\s*=\s*\{(.*?)\n\s*\}', body, re.S)
        if rm:
            for r in re.finditer(r"\{\s*(\d+)\s*(?:,\s*(\d+))?\s*\}", rm.group(1)):
                reagents.append((int(r.group(1)), int(r.group(2) or 1)))
        entries.append(
            {
                "spell": spell,
                "item": item,
                "name": name_m.group(1) if name_m else "",
                "yield": int(qmin.group(1)) if qmin else 1,
                "reagents": reagents,
            }
        )
    by_item = defaultdict(list)
    for e in entries:
        by_item[e["item"]].append(e)
    lines = [
        "-- Auto-generated from Otari98/AtlasLoot Database/Spells.lua craftspells",
        "-- Do not edit by hand; regenerate with tools/extract_atlasloot.py",
        "CraftTreeDB = {",
    ]
    for item in sorted(by_item):
        lines.append(f"  [{item}] = {{")
        for e in by_item[item]:
            name = e["name"].replace("\\", "\\\\").replace('"', '\\"')
            reag = ", ".join(f"{{{rid},{cnt}}}" for rid, cnt in e["reagents"])
            lines.append(
                f'    {{spell={e["spell"]}, yield={e["yield"]}, name="{name}", reagents={{{reag}}}},'
            )
        lines.append("  },")
    lines.append("}")
    lines.append(f"-- crafts: {len(entries)}, unique items: {len(by_item)}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT} ({len(entries)} crafts)")
    extract_sources()


if __name__ == "__main__":
    main()
