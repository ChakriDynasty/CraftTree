# CraftTree

Turtle WoW / Vanilla 1.12 addon: expand a craft into a **visual material tree** and a **base-mat shopping strip**.

Recipe data is extracted from [Otari98/AtlasLoot](https://github.com/Otari98/AtlasLoot) `Database/Spells.lua` (`craftspells`).

## Install

1. Copy this folder to `Interface/AddOns/CraftTree` (folder name must be `CraftTree`)
2. Enable **Load out of date addons**
3. Restart the game or `/reload`

## Usage

- `/crafttree` or `/ct` — toggle window
- `/ct Linen Boots` — expand by name
- `/ct 5 [Item Link]` — expand for quantity 5
- Shift-click an item with the window open to auto-expand

### Layout

1. **Top** — goal item icon (hover for tooltip)
2. **Middle** — indented material tree with icons (`+` crafts, `•` base mats)
3. **Bottom** — base materials shopping strip (counts + OK / need)

Ownership uses Bagshui when installed (account-wide); otherwise local bags.

## Regenerate data from AtlasLoot

```bash
git clone --depth 1 https://github.com/Otari98/AtlasLoot.git _vendor/AtlasLoot
python3 tools/extract_atlasloot.py
```

## Notes / v0.3

- Uses the **first** recipe when an item has multiple
- Yield defaults to 1 when AtlasLoot has no quantity
- Icons need the client item cache (hover once if a rare ID shows a question mark)
- Bagshui only knows characters that have logged in with it enabled
