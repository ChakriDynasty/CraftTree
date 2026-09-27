#!/usr/bin/env python3
"""Regenerate CraftTree recipe data from the installed Atlas-CFM addon.

Reads Atlas-CFM/CFMLoot/Data/Tables/Spells.lua and Crafting.lua next to this
addon (the Turtle/Octo loot database). Turtle-tagged crafting rows override an
untagged vanilla row for the same spell. Reagents prefer reagents_TURTLE1,
then reagents_TURTLE, then reagents. An omitted reagent count means 1.

Rows whose servers are only AtlasCFM.Server.NOT_TURTLE / NOT_TURTLE1 are
skipped when those constants resolve to a real non-turtle value ("!Turtle WoW"
and "!Turtle WoW 1.17.2"). Vanilla Plus-only rows are skipped. Untagged
vanilla recipes and Turtle recipes are included.

Enchant-only spells (no item, or a name starting with "Enchant ") are omitted.
Item-creating entries that Atlas stores in SpellDB.enchants (wands, rods,
oils) are included when a profession table lists them.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDONS = ROOT.parent
ATLAS = ADDONS / "Atlas-CFM"
SPELLS = ATLAS / "CFMLoot" / "Data" / "Tables" / "Spells.lua"
CRAFTING = ATLAS / "CFMLoot" / "Data" / "Tables" / "Crafting.lua"
OUT = ROOT / "Data" / "Recipes.lua"
SOURCES_OUT = ROOT / "Data" / "Sources.lua"
EMBED_MARKER = "-- Enchant data (from LibCrafts; also Data/Enchants.lua)"

# Longer prefixes first, matching aux-VendorCraft/discover.lua PROFESSION_PREFIXES.
PREFIXES = (
    ("Dragonscale", "Dragonscale Leatherworking"),
    ("Elemental", "Elemental Leatherworking"),
    ("Tribal", "Tribal Leatherworking"),
    ("Leather", "Leatherworking"),
    ("Armorsmith", "Blacksmithing: Armorsmith"),
    ("Weaponsmith", "Blacksmithing: Weaponsmith"),
    ("Axesmith", "Blacksmithing: Master Axesmith"),
    ("Hammersmith", "Blacksmithing: Master Hammersmith"),
    ("Swordsmith", "Blacksmithing: Master Swordsmith"),
    ("Smithing", "Blacksmithing"),
    ("Goblin", "Goblin Engineering"),
    ("Gnomish", "Gnomish Engineering"),
    ("Engineering", "Engineering"),
    ("Goldsmith", "Jewelcrafting: Goldsmithing"),
    ("Gemology", "Jewelcrafting: Gemology"),
    ("Jewelcrafting", "Jewelcrafting"),
    ("FirstAid", "First Aid"),
    ("Smelting", "Smelting"),
    ("Mining", "Mining"),
    ("Tailoring", "Tailoring"),
    ("Alchemy", "Alchemy"),
    ("Enchanting", "Enchanting"),
    ("Cooking", "Cooking"),
    ("Survival", "Survival"),
    ("Poison", "Poisons"),
)

# AtlasCFM.Server values from CFMAtlas/AtlasServer.lua, including the NOT_* metatable.
SERVERS = {
    "TURTLE": "Turtle WoW",
    "TURTLE1": "Turtle WoW 1.17.2",
    "VANILLA_PLUS": "Vanilla Plus",
    "CLASSIC": "Classic",
    "STRICT_TURTLE": "=Turtle WoW",
    "STRICT_TURTLE1": "=Turtle WoW 1.17.2",
}
for _base, _name in list(SERVERS.items()):
    if not _base.startswith("STRICT_"):
        SERVERS["NOT_" + _base] = "!" + _name

TURTLE_VALUES = {
    "Turtle WoW",
    "Turtle WoW 1.17.2",
    "=Turtle WoW",
    "=Turtle WoW 1.17.2",
}
# Real non-turtle exclusions. If a NOT_TURTLE constant did not resolve, it is absent.
NOT_TURTLE_VALUES = set()
for _key in ("NOT_TURTLE", "NOT_TURTLE1"):
    _value = SERVERS.get(_key)
    if isinstance(_value, str) and _value.startswith("!") and "Turtle" in _value:
        NOT_TURTLE_VALUES.add(_value)


def profession_of(table_key):
    for prefix, name in PREFIXES:
        if table_key.startswith(prefix):
            return name


def strip_lua_comments(src):
    out = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == '"' or ch == "'":
            j = i + 1
            while j < n and src[j] != ch:
                if src[j] == "\\":
                    j += 2
                else:
                    j += 1
            out.append(src[i : j + 1])
            i = j + 1
        elif src.startswith("--", i):
            j = src.find("\n", i)
            if j < 0:
                break
            i = j
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def brace_slice(text, open_at):
    depth = 0
    for j in range(open_at, len(text)):
        ch = text[j]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[open_at : j + 1]
    raise ValueError("unbalanced braces at %d" % open_at)


def extract_named_table(text, key):
    match = re.search(r"\b%s\s*=\s*\{" % re.escape(key), text)
    if not match:
        raise SystemExit("could not find %s" % key)
    return brace_slice(text, match.end() - 1)


def lua_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def clean_name(text):
    if not text:
        return ""
    return text.replace("\r", "").strip()


def parse_reagent_block(body, key):
    if key == "reagents":
        pattern = r"(?<![A-Za-z0-9_])reagents\s*=\s*\{"
    else:
        pattern = r"\b%s\s*=\s*\{" % re.escape(key)
    match = re.search(pattern, body)
    if not match:
        return None
    block = brace_slice(body, match.end() - 1)
    pairs = []
    for reagent in re.finditer(r"\{\s*(\d+)\s*(?:,\s*(\d+))?\s*\}", block):
        count = int(reagent.group(2) or 1)
        pairs.append((int(reagent.group(1)), count))
    return pairs


def header_comment(line):
    match = re.search(r"\]\s*=\s*\{[ \t]*--(.*)$", line)
    if match:
        return clean_name(match.group(1))
    return ""


def parse_spell_table(chunk):
    spells = {}
    for match in re.finditer(r"\[(\d+)\]\s*=\s*\{", chunk):
        spell = int(match.group(1))
        line_start = chunk.rfind("\n", 0, match.start()) + 1
        line_end = chunk.find("\n", match.start())
        line = chunk[line_start:line_end if line_end >= 0 else len(chunk)]
        body = brace_slice(chunk, match.end() - 1)
        item = re.search(r"\bitem\s*=\s*(\d+)", body)
        name_field = re.search(r'\bname\s*=\s*LS\["([^"]*)"\]', body) or re.search(
            r'\bname\s*=\s*"([^"]*)"', body
        )
        spells[spell] = {
            "item": int(item.group(1)) if item else None,
            "comment": header_comment(line),
            "name_field": clean_name(name_field.group(1)) if name_field else "",
            "reagents_TURTLE1": parse_reagent_block(body, "reagents_TURTLE1"),
            "reagents_TURTLE": parse_reagent_block(body, "reagents_TURTLE"),
            "reagents": parse_reagent_block(body, "reagents"),
        }
    return spells


def resolve_server_list(expr):
    servers = []
    for part in expr.split(","):
        part = part.strip()
        if not part:
            continue
        match = re.match(r"AtlasCFM\.Server\.([A-Z0-9_]+)", part)
        if match:
            servers.append(SERVERS.get(match.group(1)))
            continue
        literal = re.match(r'"([^"]*)"', part)
        if literal:
            servers.append(literal.group(1))
            continue
        servers.append(None)
    return servers


def classify_servers(servers):
    """Return 'turtle', 'vanilla', or 'skip'."""
    if not servers:
        return "vanilla"
    real = [server for server in servers if server]
    if not real:
        # Constants were present but did not resolve to a real non-turtle value.
        return "vanilla"
    if all(server in NOT_TURTLE_VALUES for server in real):
        return "skip"
    if any(server in TURTLE_VALUES for server in real):
        return "turtle"
    allows = [server for server in real if not server.startswith("!")]
    if allows and not any(server in TURTLE_VALUES for server in allows):
        return "skip"
    return "vanilla"


def parse_number(text):
    if text is None:
        return None
    text = text.strip()
    if text.startswith("{"):
        first = re.search(r"(\d+)", text)
        return int(first.group(1)) if first else None
    if re.match(r"^\d+$", text):
        return int(text)
    return None


def parse_crafting(text):
    rows = []
    current = None
    profession = None
    for line in text.splitlines():
        key = re.match(r"^\t([A-Za-z0-9]+) = \{$", line)
        if key:
            current = key.group(1)
            profession = profession_of(current)
            continue
        if current and re.match(r"^\t\},?$", line.rstrip()):
            current = None
            profession = None
            continue
        if not profession:
            continue
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        ident = re.search(r"\bid\s*=\s*(\d+)", line)
        if not ident:
            continue
        skill = re.search(r"\bskill\s*=\s*(\{[^}]*\}|\d+)", line)
        quantity = re.search(r"\bquantity\s*=\s*(\{[^}]*\}|\d+)", line)
        servers = re.search(r"\bservers\s*=\s*\{([^}]*)\}", line)
        comment = ""
        comment_match = re.search(r"--(.*)$", line)
        if comment_match:
            comment = clean_name(comment_match.group(1))
        resolved = resolve_server_list(servers.group(1)) if servers else []
        rows.append(
            {
                "spell": int(ident.group(1)),
                "profession": profession,
                "skill": parse_number(skill.group(1)) if skill else 0,
                "yield": parse_number(quantity.group(1)) if quantity else None,
                "kind": classify_servers(resolved),
                "comment": comment,
                "servers": [server for server in resolved if server],
                "table": current,
            }
        )
    return rows


def choose_rows(rows):
    chosen = {}
    for row in rows:
        if row["kind"] == "skip":
            continue
        spell = row["spell"]
        if row["kind"] == "turtle":
            chosen[spell] = row
        elif spell not in chosen:
            chosen[spell] = row
    return chosen


def preferred_reagents(spell):
    for key in ("reagents_TURTLE1", "reagents_TURTLE", "reagents"):
        reagents = spell.get(key)
        if reagents:
            return reagents
    return None


def build_recipes():
    if not SPELLS.is_file() or not CRAFTING.is_file():
        raise SystemExit("installed Atlas-CFM not found at %s" % ATLAS)
    spell_text = SPELLS.read_text(encoding="utf-8", errors="replace")
    crafting_text = CRAFTING.read_text(encoding="utf-8", errors="replace")
    spells = {}
    spells.update(parse_spell_table(extract_named_table(spell_text, "craftspells")))
    spells.update(parse_spell_table(extract_named_table(spell_text, "enchants")))
    chosen = choose_rows(parse_crafting(crafting_text))
    recipes = []
    for spell_id, row in chosen.items():
        spell = spells.get(spell_id)
        if not spell or not spell["item"]:
            continue
        name = clean_name(spell["comment"] or row["comment"] or spell["name_field"])
        if not name or name.startswith("Enchant "):
            continue
        reagents = preferred_reagents(spell)
        if not reagents:
            continue
        recipes.append(
            {
                "spell": spell_id,
                "item": spell["item"],
                "name": name,
                "yield": row["yield"] or 1,
                "reagents": reagents,
                "profession": row["profession"],
                "skill": row["skill"] if row["skill"] is not None else 0,
                "servers": row["servers"],
                "kind": row["kind"],
                "table": row["table"],
                "raw": spell,
            }
        )
    recipes.sort(key=lambda recipe: (recipe["item"], recipe["spell"]))
    return recipes


def write_recipes(recipes):
    by_item = defaultdict(list)
    for recipe in recipes:
        by_item[recipe["item"]].append(recipe)
    lines = [
        "-- Auto-generated from the installed Atlas-CFM Turtle craft data",
        "-- Do not edit by hand; regenerate with tools/extract_atlasloot.py",
        "CraftTreeDB = {",
    ]
    for item in sorted(by_item):
        lines.append("  [%d] = {" % item)
        for recipe in by_item[item]:
            reagents = ", ".join("{%d,%d}" % pair for pair in recipe["reagents"])
            lines.append(
                '    {spell=%d, yield=%d, name="%s", reagents={%s}},'
                % (recipe["spell"], recipe["yield"], lua_escape(recipe["name"]), reagents)
            )
        lines.append("  },")
    lines.append("}")
    lines.append("-- crafts: %d, unique items: %d" % (len(recipes), len(by_item)))
    body = "\n".join(lines) + "\n"
    if OUT.is_file():
        previous = OUT.read_text(encoding="utf-8")
        if EMBED_MARKER in previous:
            embed = previous[previous.find(EMBED_MARKER) :].rstrip() + "\n"
            body = body.rstrip() + "\n\n" + embed
    OUT.write_text(body, encoding="utf-8")
    print("Wrote %s (%d crafts, %d items)" % (OUT, len(recipes), len(by_item)))


def write_sources(recipes):
    by_item = {}
    for recipe in recipes:
        current = by_item.get(recipe["item"])
        if current is None or (recipe["skill"], recipe["spell"]) < (current["skill"], current["spell"]):
            by_item[recipe["item"]] = recipe
    lines = [
        "-- Auto-generated from the installed Atlas-CFM crafting tables",
        "-- Do not edit by hand; regenerate with tools/extract_atlasloot.py",
        '-- CraftTreeSources[itemId] = { profession="Tailoring", skill="300+", text="Tailoring (Skill: 300+)" }',
        "CraftTreeSources = {",
    ]
    for item in sorted(by_item):
        recipe = by_item[item]
        skill = "%d+" % (recipe["skill"] or 0)
        profession = recipe["profession"]
        text = "%s (Skill: %s)" % (profession, skill)
        lines.append(
            '  [%d] = {profession="%s", skill="%s", text="%s"},'
            % (item, lua_escape(profession), skill, lua_escape(text))
        )
    lines.append("}")
    lines.append("-- entries: %d" % len(by_item))
    SOURCES_OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Wrote %s (%d sources)" % (SOURCES_OUT, len(by_item)))


def lua_reagent_list(pairs):
    if not pairs:
        return None
    return "{" + ", ".join("{%d, %d}" % pair for pair in pairs) + "}"


def write_stub(recipes, path):
    """AtlasCFM stub for the VendorCraft discovery test. Not part of the addon."""
    by_table = defaultdict(list)
    spells = {}
    for recipe in recipes:
        spells[recipe["spell"]] = recipe
        by_table[recipe["table"]].append(recipe)
    lines = [
        "-- Generated Atlas-CFM stub for VendorCraft tests. Not loaded by the game.",
        "AtlasCFM = {SpellDB = {craftspells = {",
    ]
    for spell in sorted(spells):
        recipe = spells[spell]
        raw = recipe["raw"]
        parts = ["item = %d" % recipe["item"], 'name = "%s"' % lua_escape(recipe["name"])]
        for key in ("reagents", "reagents_TURTLE", "reagents_TURTLE1"):
            block = lua_reagent_list(raw.get(key))
            if block:
                parts.append("%s = %s" % (key, block))
        lines.append("\t[%d] = {%s}," % (spell, ", ".join(parts)))
    lines.append("}}}")
    lines.append("AtlasCFMLoot_Data = {")
    for table in sorted(by_table):
        lines.append("\t%s = {" % table)
        for recipe in by_table[table]:
            servers = ""
            if recipe["servers"]:
                quoted = ", ".join('"%s"' % lua_escape(server) for server in recipe["servers"])
                servers = ", servers = {%s}" % quoted
            quantity = ""
            if recipe["yield"] and recipe["yield"] != 1:
                quantity = ", quantity = %d" % recipe["yield"]
            lines.append(
                "\t\t{id = %d, skill = {%d, %d, %d, %d}%s%s},"
                % (recipe["spell"], recipe["skill"] or 0, recipe["skill"] or 0, recipe["skill"] or 0, recipe["skill"] or 0, quantity, servers)
            )
        lines.append("\t},")
    lines.append("}")
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Wrote %s (%d spells)" % (path, len(spells)))


def main():
    recipes = build_recipes()
    write_recipes(recipes)
    write_sources(recipes)
    if len(sys.argv) > 2 and sys.argv[1] == "--stub":
        write_stub(recipes, sys.argv[2])
    robe = [recipe for recipe in recipes if recipe["spell"] == 36913]
    if not robe:
        raise SystemExit("spell 36913 was not written")
    robe = robe[0]
    print(
        "Astronomer Raiments item %d reagents %s"
        % (robe["item"], robe["reagents"])
    )


if __name__ == "__main__":
    main()
