# CraftTree

Turtle WoW / Vanilla 1.12 addon: expand a craft into a **full material tree** and a **base-mat shopping list** (mats of mats).

Recipe data is extracted from [Otari98/AtlasLoot](https://github.com/Otari98/AtlasLoot) `Database/Spells.lua` (`craftspells`).

## Install

1. Copy this folder to `Interface/AddOns/CraftTree` (folder name must be `CraftTree`)
2. Enable **Load out of date addons**
3. Restart or `/reload`

## Usage

- `/crafttree` or `/ct` — toggle window
- `/ct 12345` — expand item ID
- `/ct 5 [Item Link]` — expand for quantity 5
- `/ct Mooncloth Boots` — name search against known crafts
- In the window: paste a link / ID / name, set qty, click **Expand**
- Shift-click an item into the input while it is focused

`*` lines are base materials (shopping list).  
`+` lines are intermediate crafts (with craft counts).

## Regenerate data from AtlasLoot

```bash
git clone --depth 1 https://github.com/Otari98/AtlasLoot.git _vendor/AtlasLoot
python3 tools/extract_atlasloot.py
```

## Bagshui ownership

If [Bagshui](https://github.com/veechs/Bagshui) is installed, the shopping list shows account-wide owned counts:

- `own N (here X / alts Y)` — total / current character / other characters
- Green **OK** when you already have enough, yellow/red **need N** when short

Without Bagshui, CraftTree falls back to local bags (and bank while the bank UI is open).

## Notes / v0.2 limits

- Uses the **first** recipe when an item has multiple
- Yield defaults to 1 when AtlasLoot has no quantity
- No AtlasLoot UI button yet (slash + window only)
- Item names for base mats use `GetItemInfo` (may show `item:ID` until cached)
- Bagshui only knows characters that have logged in with it enabled
