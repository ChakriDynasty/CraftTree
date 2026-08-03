#!/usr/bin/env python3
"""Extract CraftTreeEnchantDB from LibCrafts Enchanting.lua (+ AtlasLoot icons)."""
import re
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LC = ROOT / "_vendor" / "LibCrafts" / "Enchanting.lua"
SPELLS = ROOT / "_vendor" / "AtlasLoot" / "Database" / "Spells.lua"
OUT = ROOT / "Data" / "Enchants.lua"
RECIPES = ROOT / "Data" / "Recipes.lua"

EMBED_MARKER = "-- Enchant data (from LibCrafts; also Data/Enchants.lua)"


def atlas_enchants(text: str):
    start = text.find('["enchants"]')
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
    al = {}
    for m in re.finditer(r"\[(\d+)\]\s*=\s*\{", chunk):
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
        name_m = re.search(r'\["name"\]\s*=\s*"([^"]+)"', body)
        icon_m = re.search(r'\["icon"\]\s*=\s*"([^"]+)"', body)
        item_m = re.search(r'\["item"\]\s*=\s*(\d+)', body)
        al[spell] = {
            "name": name_m.group(1) if name_m else "",
            "icon": icon_m.group(1) if icon_m else "",
            "item": int(item_m.group(1)) if item_m else None,
        }
    return al


def parse_libcrafts(text: str, al: dict):
    by_spell = OrderedDict()
    for m in re.finditer(r'module:NewCraft\((\d+)\s*,\s*"([^"]+)"\s*,\s*(\d+)\s*,', text):
        spell = int(m.group(1))
        name = m.group(2)
        skill = int(m.group(3))
        rest = text[m.end() :]
        end = rest.find(":Save()")
        body = rest[:end]
        result_m = re.search(r":SetResult\((\d+)\)", body)
        reagents = [
            (int(a), int(b))
            for a, b in re.findall(r":AddReagent\((\d+)\s*,\s*(\d+)\)", body)
        ]
        formulas = [int(a) for a in re.findall(r":AddRecipe\((\d+)\s*,", body)]
        icon = al.get(spell, {}).get("icon") or "Interface\\Icons\\Spell_Holy_GreaterHeal"
        icon = icon.replace("\\\\", "\\")
        by_spell[spell] = {
            "spell": spell,
            "name": name,
            "skill": skill,
            "item": int(result_m.group(1)) if result_m else None,
            "reagents": reagents,
            "formulas": formulas,
            "icon": icon,
        }
    return list(by_spell.values())


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def render_tables(enchants, crafts, items):
    lines = [
        EMBED_MARKER,
        "CraftTreeEnchantDB = {",
    ]
    for c in sorted(enchants, key=lambda x: x["spell"]):
        reag = ", ".join("{%d,%d}" % (rid, cnt) for rid, cnt in c["reagents"])
        lines.append("  [%d] = {" % c["spell"])
        lines.append(
            '    {spell=%d, yield=1, name="%s", icon="%s", reagents={%s}},'
            % (c["spell"], esc(c["name"]), esc(c["icon"]), reag)
        )
        lines.append("  },")
    lines.append("}")
    lines.append("")
    lines.append("-- Formula/scroll item id -> enchant spell id")
    lines.append("CraftTreeEnchantFormulas = {")
    seen = set()
    for c in sorted(crafts, key=lambda x: x["spell"]):
        for fid in c["formulas"]:
            if fid in seen:
                continue
            seen.add(fid)
            lines.append("  [%d] = %d," % (fid, c["spell"]))
    lines.append("}")
    lines.append(
        "-- enchants: %d, formulas: %d, item-crafts: %d"
        % (len(enchants), len(seen), len(items))
    )
    return "\n".join(lines) + "\n"


def main():
    al = atlas_enchants(SPELLS.read_text(encoding="utf-8", errors="replace"))
    crafts = parse_libcrafts(LC.read_text(encoding="utf-8"), al)
    if 36942 not in {c["spell"] for c in crafts}:
        crafts.append(
            {
                "spell": 36942,
                "name": al.get(36942, {}).get("name") or "Enchant Weapon - Rift Tear",
                "skill": 300,
                "item": None,
                "reagents": [],
                "formulas": [33144],
                "icon": (
                    al.get(36942, {}).get("icon") or "Interface\\Icons\\Spell_Holy_GreaterHeal"
                ).replace("\\\\", "\\"),
            }
        )

    enchants = [c for c in crafts if not c["item"]]
    items = [c for c in crafts if c["item"]]
    body = render_tables(enchants, crafts, items)

    OUT.write_text(
        "-- Auto-generated from refaim/LibCrafts-1.0 Professions/Enchanting.lua\n"
        "-- (+ AtlasLoot enchants names/icons). Regenerate with tools/extract_enchants.py\n"
        + body,
        encoding="utf-8",
    )
    print("Wrote %s (%d enchants)" % (OUT, len(enchants)))

    recipes = RECIPES.read_text(encoding="utf-8")
    # Drop any previously embedded enchant block
    if EMBED_MARKER in recipes:
        recipes = recipes[: recipes.find(EMBED_MARKER)].rstrip() + "\n"
    recipes = re.sub(r"\nCraftTreeEnchantDB = \{.*", "", recipes, flags=re.S)
    recipes = recipes.rstrip() + "\n"

    existing = set(int(x) for x in re.findall(r"^  \[(\d+)\] = \{", recipes, re.M))
    to_add = [c for c in items if c["item"] not in existing]
    if to_add:
        insert_lines = []
        for c in sorted(to_add, key=lambda x: x["item"]):
            reag = ", ".join("{%d,%d}" % (rid, cnt) for rid, cnt in c["reagents"])
            insert_lines.append("  [%d] = {" % c["item"])
            insert_lines.append(
                '    {spell=%d, yield=1, name="%s", reagents={%s}},'
                % (c["spell"], esc(c["name"]), reag)
            )
            insert_lines.append("  },")
        m = re.search(r"\n\}\s*\n-- crafts:", recipes)
        if m:
            recipes = (
                recipes[: m.start()] + "\n" + "\n".join(insert_lines) + recipes[m.start() :]
            )
            print("Merged %d enchanting item crafts into Recipes.lua" % len(to_add))

    recipes = recipes.rstrip() + "\n\n" + body
    RECIPES.write_text(recipes, encoding="utf-8")
    print("Embedded enchant tables into Recipes.lua")


if __name__ == "__main__":
    main()
