-- CraftTree: recursive craft materials -> base mat shopping list
-- Data sourced from AtlasLoot craftspells (see Data/Recipes.lua)
-- Owned counts: Bagshui catalog when available, else local bags/bank

CraftTree = CraftTree or {}
CraftTreeDBPC = CraftTreeDBPC or {}

local MAX_DEPTH = 25

local function ItemName(itemId)
	local name = GetItemInfo(itemId)
	if name then
		return name
	end
	local recipes = CraftTreeDB and CraftTreeDB[itemId]
	if recipes and recipes[1] and recipes[1].name and recipes[1].name ~= "" then
		return recipes[1].name
	end
	return "Unknown Item"
end

local function StripColors(text)
	if not text then
		return ""
	end
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	text = string.gsub(text, "|H.-|h", "")
	text = string.gsub(text, "|h", "")
	return text
end

local function NormalizeName(text)
	text = StripColors(text or "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	-- [Item Name] from links / chat
	local _, _, bracketed = string.find(text, "%[(.-)%]")
	if bracketed and bracketed ~= "" then
		text = bracketed
	end
	-- curly apostrophes -> straight
	text = string.gsub(text, "’", "'")
	text = string.gsub(text, "‘", "'")
	return text
end

local function FindCraftByName(query)
	if not CraftTreeDB or not query or query == "" then
		return nil
	end
	local lower = string.lower(query)
	local exactId, startsId, containsId
	local itemId, recipes
	for itemId, recipes in pairs(CraftTreeDB) do
		local n = recipes[1] and recipes[1].name
		if n and n ~= "" then
			local nl = string.lower(string.gsub(n, "’", "'"))
			if nl == lower then
				exactId = itemId
				break
			elseif not startsId and string.sub(nl, 1, string.len(lower)) == lower then
				startsId = itemId
			elseif not containsId and string.find(nl, lower, 1, true) then
				containsId = itemId
			end
		end
	end
	return exactId or startsId or containsId
end

local function SuggestCraftNames(query, limit)
	limit = limit or 10
	local out = {}
	if not CraftTreeDB or not query then
		return out
	end
	query = string.gsub(query, "^%s+", "")
	query = string.gsub(query, "%s+$", "")
	if query == "" or string.len(query) < 1 then
		return out
	end
	-- Skip raw item links / pure IDs for suggest UI
	if string.find(query, "item:") or string.find(query, "^%d+$") then
		return out
	end
	local lower = string.lower(string.gsub(query, "’", "'"))
	local starts, contains = {}, {}
	local itemId, recipes
	for itemId, recipes in pairs(CraftTreeDB) do
		local n = recipes[1] and recipes[1].name
		if n and n ~= "" then
			local nl = string.lower(string.gsub(n, "’", "'"))
			if string.sub(nl, 1, string.len(lower)) == lower then
				table.insert(starts, { id = itemId, name = n })
			elseif string.find(nl, lower, 1, true) then
				table.insert(contains, { id = itemId, name = n })
			end
		end
	end
	local function byName(a, b)
		return a.name < b.name
	end
	table.sort(starts, byName)
	table.sort(contains, byName)
	local i
	for i = 1, table.getn(starts) do
		table.insert(out, starts[i])
		if table.getn(out) >= limit then
			return out
		end
	end
	for i = 1, table.getn(contains) do
		table.insert(out, contains[i])
		if table.getn(out) >= limit then
			return out
		end
	end
	return out
end

function CraftTree_GetSuggestions(query, limit)
	return SuggestCraftNames(query, limit)
end

function CraftTree_ParseItemId(text)
	if not text then
		return nil
	end
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then
		return nil
	end

	-- Full item link / any "item:12345" fragment (links can be long)
	local _, _, linkId = string.find(text, "item:(%d+)")
	if linkId then
		return tonumber(linkId)
	end

	-- Bare number
	local _, _, bare = string.find(text, "^(%d+)$")
	if bare then
		return tonumber(bare)
	end

	-- Display name from link leftovers or typed craft name
	local name = NormalizeName(text)
	if name ~= "" and name ~= text then
		local _, _, again = string.find(name, "item:(%d+)")
		if again then
			return tonumber(again)
		end
	end
	return FindCraftByName(name)
end

-- Back-compat alias
local function ParseItemId(text)
	return CraftTree_ParseItemId(text)
end

------------------------------------------------------------------------
-- Ownership (Bagshui / local bags)
------------------------------------------------------------------------

local function SumTotalsForItem(totalsTable, itemId)
	if type(totalsTable) ~= "table" or not itemId then
		return 0
	end
	local prefix = "item:" .. tostring(itemId) .. ":"
	local sum = 0
	local itemString, count
	for itemString, count in pairs(totalsTable) do
		if type(itemString) == "string" and type(count) == "number" then
			if string.sub(itemString, 1, string.len(prefix)) == prefix then
				sum = sum + count
			end
		end
	end
	return sum
end

local function GetBagshuiCatalog()
	if not Bagshui or not Bagshui.components then
		return nil
	end
	return Bagshui.components.Catalog
end

-- Scan Bagshui SavedVariables directly (works even before Catalog:Init finishes).
local function CountFromBagshuiData(itemId)
	if type(BagshuiData) ~= "table" or type(BagshuiData.characters) ~= "table" then
		return nil
	end
	local total, current, other = 0, 0, 0
	local myName = UnitName("player")
	local myRealm = GetRealmName and GetRealmName() or nil
	local charId, data
	for charId, data in pairs(BagshuiData.characters) do
		if type(data) == "table" and type(data.info) == "table" then
			local charTotal = 0
			local invKey, invData
			for invKey, invData in pairs(data) do
				if type(invData) == "table" and type(invData.inventory) == "table" then
					local bagNum, contents
					for bagNum, contents in pairs(invData.inventory) do
						if type(contents) == "table" then
							local i, item
							for i, item in ipairs(contents) do
								if type(item) == "table" and item.id == itemId and item.emptySlot ~= 1 then
									charTotal = charTotal + (item.count or 0)
								end
							end
						end
					end
				end
			end
			-- equipped
			if type(data.info.equipped) == "table" then
				local slot, item
				for slot, item in pairs(data.info.equipped) do
					if type(item) == "table" and item.id == itemId then
						charTotal = charTotal + (item.count or 1)
					end
				end
			end
			total = total + charTotal
			local sameChar = data.info.name == myName and ((not myRealm) or data.info.realm == myRealm)
			if sameChar then
				current = current + charTotal
			else
				other = other + charTotal
			end
		end
	end
	return total, current, other, "bagshui-data"
end

local function CountLocalBags(itemId)
	local total = 0
	local function scanBag(bag)
		local slots = GetContainerNumSlots(bag)
		if not slots or slots == 0 then
			return
		end
		local slot
		for slot = 1, slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local _, _, id = string.find(link, "item:(%d+)")
				if tonumber(id) == itemId then
					local _, count = GetContainerItemInfo(bag, slot)
					total = total + (count or 1)
				end
			end
		end
	end
	local bag
	for bag = 0, 4 do
		scanBag(bag)
	end
	-- Bank (only accurate while bank is open / cached by client)
	if BankFrame and BankFrame:IsShown() then
		scanBag(-1)
		for bag = 5, 10 do
			scanBag(bag)
		end
	end
	return total, total, 0, "local"
end

-- Returns: total, currentChar, otherChars, source
-- source: "bagshui" | "bagshui-data" | "local" | "none"
function CraftTree_GetOwned(itemId)
	local catalog = GetBagshuiCatalog()
	if catalog and catalog.totals and catalog.initialized then
		local totals = catalog.totals
		local total = SumTotalsForItem(totals["==Total"], itemId)
		local current = SumTotalsForItem(totals["==TotalCurrent"], itemId)
		local other = SumTotalsForItem(totals["==TotalOther"], itemId)
		-- If catalog exists but is empty for this item, still trust it (0 owned).
		return total, current, other, "bagshui"
	end

	local t, c, o, src = CountFromBagshuiData(itemId)
	if t ~= nil then
		return t, c, o, src
	end

	local lt, lc, lo, lsrc = CountLocalBags(itemId)
	return lt, lc, lo, lsrc
end

local function OwnershipSourceLabel(source)
	if source == "bagshui" then
		return "Bagshui (all chars)"
	elseif source == "bagshui-data" then
		return "Bagshui data"
	elseif source == "local" then
		return "local bags" .. ((BankFrame and BankFrame:IsShown()) and "+bank" or " (bank closed)")
	end
	return "none"
end

local function FormatOwnLine(need, ownedTotal, ownedCurrent, ownedOther, source)
	local short = need - ownedTotal
	if short < 0 then
		short = 0
	end
	local status
	if ownedTotal >= need then
		status = "OK"
	else
		status = "NEED " .. short
	end
	local detail = string.format("own %d", ownedTotal)
	if source == "bagshui" or source == "bagshui-data" then
		if ownedOther > 0 or ownedCurrent > 0 then
			detail = string.format("own %d (here %d / alts %d)", ownedTotal, ownedCurrent, ownedOther)
		end
	end
	return detail .. " [" .. status .. "]"
end

------------------------------------------------------------------------
-- Resolver
------------------------------------------------------------------------

--[[
  Alchemy transmutes (Vanilla / Turtle) — from wowhead / warcraft.wiki:

  LOOP (never expand — farmed base mats):
    Essence of Earth / Fire / Water / Air
    Living Essence / Essence of Undeath

  ONE-WAY (still expand):
    Iron→Gold, Mithril→Truesilver, Thorium+Arcane Crystal→Arcanite
    Core of Earth→3× Elemental Earth, Heart of Fire→3× Elemental Fire,
    Globe of Water→3× Elemental Water

  Gold/Truesilver also have Smelt recipes — we prefer Smelt over Transmute.
  Arcanite Bar has NO smithing recipe; only alchemy transmute (BS consumes it).
]]
local TRANSMUTE_LOOP = {
	[7076] = true, -- Essence of Earth
	[7078] = true, -- Essence of Fire
	[7080] = true, -- Essence of Water
	[7082] = true, -- Essence of Air
	[12803] = true, -- Living Essence
	[12808] = true, -- Essence of Undeath
}

local function IsTransmuteRecipe(recipe)
	if not recipe or not recipe.name then
		return false
	end
	return string.sub(recipe.name, 1, 10) == "Transmute:"
end

-- Prefer smelt/craft over transmute. Nil = treat as base mat.
local function SelectRecipe(recipes, itemId, stack)
	if not recipes or table.getn(recipes) == 0 then
		return nil
	end

	if TRANSMUTE_LOOP[itemId] then
		return nil
	end

	local i, recipe
	for i = 1, table.getn(recipes) do
		recipe = recipes[i]
		if recipe.reagents and table.getn(recipe.reagents) > 0 and not IsTransmuteRecipe(recipe) then
			return recipe
		end
	end

	for i = 1, table.getn(recipes) do
		recipe = recipes[i]
		if recipe.reagents and table.getn(recipe.reagents) > 0 then
			local ok = true
			local j
			for j = 1, table.getn(recipe.reagents) do
				local rid = recipe.reagents[j][1]
				if stack and stack[rid] then
					ok = false
					break
				end
			end
			if ok then
				return recipe
			end
		end
	end

	return nil
end

function CraftTree_Resolve(itemId, need, shopping, depth, stack)
	need = need or 1
	shopping = shopping or {}
	depth = depth or 0
	stack = stack or {}

	local owned, cur, oth, src = CraftTree_GetOwned(itemId)
	owned = owned or 0

	local node = {
		id = itemId,
		need = need,
		name = ItemName(itemId),
		children = {},
		leaf = false,
		crafts = 0,
		yield = 1,
		blocked = false,
		owned = owned,
		ownedCurrent = cur or 0,
		ownedOther = oth or 0,
		ownSrc = src,
		applied = 0,
		short = need,
	}

	-- Intermediate crafts/mats: use what you already own before expanding further.
	-- Goal item (depth 0) always resolves the full requested quantity.
	local produce = need
	if depth > 0 then
		local used = math.min(need, owned)
		node.applied = used
		produce = need - used
	end
	node.short = produce

	if depth > MAX_DEPTH then
		node.leaf = true
		node.blocked = true
		shopping[itemId] = (shopping[itemId] or 0) + need
		return node, shopping
	end

	if stack[itemId] then
		-- Generic loop break (any craft cycle, not only essences)
		node.leaf = true
		node.blocked = true
		node.loop = true
		shopping[itemId] = (shopping[itemId] or 0) + need
		return node, shopping
	end

	local recipes = CraftTreeDB and CraftTreeDB[itemId]
	local recipe = SelectRecipe(recipes, itemId, stack)
	if not recipe then
		node.leaf = true
		if TRANSMUTE_LOOP[itemId] then
			node.transmuteBase = true
		end
		shopping[itemId] = (shopping[itemId] or 0) + need
		return node, shopping
	end

	local yield = recipe.yield or 1
	if yield < 1 then
		yield = 1
	end
	local crafts = 0
	if produce > 0 then
		crafts = math.ceil(produce / yield)
	end
	node.crafts = crafts
	node.yield = yield
	node.name = recipe.name ~= "" and recipe.name or node.name
	node.spell = recipe.spell
	if IsTransmuteRecipe(recipe) then
		node.transmute = true
	end
	if recipes and table.getn(recipes) > 1 then
		node.altRecipes = table.getn(recipes)
	end

	-- Fully covered by bags: still attach one craft's reagents so click-to-expand
	-- can show the recipe, but dump that branch into a throwaway shopping list.
	local childShopping = shopping
	local childCrafts = crafts
	if crafts == 0 then
		childCrafts = 1
		childShopping = {}
		node.preview = true
	end

	stack[itemId] = true
	local i
	for i = 1, table.getn(recipe.reagents) do
		local reag = recipe.reagents[i]
		local rid = reag[1]
		local rcnt = reag[2] or 1
		local childNeed = rcnt * childCrafts
		local child = CraftTree_Resolve(rid, childNeed, childShopping, depth + 1, stack)
		table.insert(node.children, child)
	end
	stack[itemId] = nil

	return node, shopping
end

local function FormatTree(node, indent, lines)
	indent = indent or ""
	lines = lines or {}
	local mark = node.leaf and "*" or "+"
	local extra = ""
	if not node.leaf and node.crafts and node.crafts > 0 then
		extra = string.format("  [craft x%d]", node.crafts)
	end
	if node.altRecipes then
		extra = extra .. string.format(" (%d recipes)", node.altRecipes)
	end
	if node.blocked then
		extra = extra .. " [cycle/depth]"
	end
	if node.leaf then
		local owned, cur, oth, src = CraftTree_GetOwned(node.id)
		extra = extra .. "  (" .. FormatOwnLine(node.need, owned, cur, oth, src) .. ")"
	end
	table.insert(lines, string.format("%s%s %dx %s%s", indent, mark, node.need, node.name, extra))
	local i
	for i = 1, table.getn(node.children) do
		FormatTree(node.children[i], indent .. "  ", lines)
	end
	return lines
end

local function SortedShopping(shopping)
	local list = {}
	local id, count
	for id, count in pairs(shopping) do
		local owned, cur, oth, src = CraftTree_GetOwned(id)
		table.insert(list, {
			id = id,
			count = count,
			name = ItemName(id),
			owned = owned,
			ownedCurrent = cur,
			ownedOther = oth,
			source = src,
			short = math.max(0, count - owned),
		})
	end
	table.sort(list, function(a, b)
		-- Missing mats first, then name
		if (a.short > 0) ~= (b.short > 0) then
			return a.short > 0
		end
		return a.name < b.name
	end)
	return list
end

function CraftTree_BuildReport(itemId, qty)
	qty = qty or 1
	if qty < 1 then
		qty = 1
	end
	local node, shopping = CraftTree_Resolve(itemId, qty, {})
	return node, shopping
end

function CraftTree_OnShow()
	if CraftTreeFrameQty and (not CraftTreeFrameQty:GetText() or CraftTreeFrameQty:GetText() == "") then
		CraftTreeFrameQty:SetText("1")
	end
	if CraftTree_InitUI then
		CraftTree_InitUI()
	end
end

function CraftTree_ShowReport(itemId, qty)
	local node, shopping = CraftTree_BuildReport(itemId, qty)
	CraftTreeFrame:Show()
	if CraftTree_RenderResult then
		CraftTree_RenderResult(itemId, qty, node, shopping)
	end
end

function CraftTree_OnInputEnter()
	-- Prefer highlighted autocomplete entry when present
	if CraftTree_TakeSuggestion then
		local taken = CraftTree_TakeSuggestion()
		if taken then
			return
		end
	end
	if CraftTree_HideSuggestions then
		CraftTree_HideSuggestions()
	end
	local text = CraftTreeFrameInput and CraftTreeFrameInput:GetText() or ""
	local qty = tonumber(CraftTreeFrameQty and CraftTreeFrameQty:GetText()) or 1
	local itemId = ParseItemId(text)
	if not itemId then
		local msg = "Could not parse that input. Shift-click a link, type a craft name, or an item ID."
		local name = NormalizeName(text)
		local suggestions = SuggestCraftNames(name, 5)
		if table.getn(suggestions) > 0 then
			local names = {}
			local i
			for i = 1, table.getn(suggestions) do
				table.insert(names, suggestions[i].name)
			end
			msg = msg .. " Similar: " .. table.concat(names, ", ")
		end
		CraftTreeFrame:Show()
		if CraftTree_ShowMessage then
			CraftTree_ShowMessage(msg)
		end
		return
	end
	if CraftTreeFrameInput then
		local shown = GetItemInfo(itemId)
		if not shown then
			shown = ItemName(itemId)
		end
		CraftTreeFrameInput:SetText(shown)
	end
	CraftTree_ShowReport(itemId, qty)
end

function CraftTree_Toggle()
	if CraftTreeFrame:IsShown() then
		CraftTreeFrame:Hide()
	else
		CraftTreeFrame:Show()
		if CraftTreeFrameInput then
			CraftTreeFrameInput:SetFocus()
		end
	end
end

-- Insert an item link/id into CraftTree and expand it.
function CraftTree_ReceiveLink(link)
	if not link or link == "" then
		return false
	end
	if not CraftTreeFrame then
		return false
	end
	CraftTreeFrame:Show()
	if CraftTreeFrameInput then
		CraftTreeFrameInput:SetText(link)
		CraftTreeFrameInput:SetFocus()
	end
	CraftTree_OnInputEnter()
	return true
end

local function CraftTreeWantsLinks()
	return CraftTreeFrame and CraftTreeFrame:IsShown() and not IsAltKeyDown()
end

-- Resolve AtlasLoot click ids ("s123", numeric item, etc.) to an item id/link.
local function ResolveAtlasLootId(id)
	if not id or id == 0 or id == "0" then
		return nil
	end
	if type(id) == "number" then
		return id
	end
	if type(id) ~= "string" then
		return tonumber(id)
	end
	local prefix = string.sub(id, 1, 1)
	local num = tonumber(string.sub(id, 2))
	if prefix == "s" and num and GetSpellInfoAtlasLootDB and GetSpellInfoAtlasLootDB["craftspells"] then
		local spell = GetSpellInfoAtlasLootDB["craftspells"][num]
		if spell and spell["craftItem"] and spell["craftItem"] ~= 0 then
			return spell["craftItem"]
		end
		return nil
	end
	if prefix == "e" and num and GetSpellInfoAtlasLootDB and GetSpellInfoAtlasLootDB["enchants"] then
		local ench = GetSpellInfoAtlasLootDB["enchants"][num]
		if ench and ench["item"] and ench["item"] ~= 0 then
			return ench["item"]
		end
		return nil
	end
	return tonumber(id)
end

local function ReceiveItemId(itemId, name)
	if not itemId then
		return false
	end
	local link
	if name then
		link = "|Hitem:" .. tostring(itemId) .. ":0:0:0|h[" .. tostring(name) .. "]|h"
	else
		link = "item:" .. tostring(itemId) .. ":0:0:0"
	end
	return CraftTree_ReceiveLink(link)
end

local hookedClicks = {}

local function HookContainerClick(funcName)
	if hookedClicks[funcName] then
		return
	end
	local original = getglobal(funcName)
	if type(original) ~= "function" then
		return
	end
	hookedClicks[funcName] = 1
	setglobal(funcName, function(button)
		button = button or arg1 or "LeftButton"
		if CraftTreeWantsLinks() and button == "LeftButton" and IsShiftKeyDown() then
			local bag, slot
			if this and this.GetParent and this.GetID then
				local parent = this:GetParent()
				if parent and parent.GetID then
					bag = parent:GetID()
				end
				slot = this:GetID()
			end
			if bag ~= nil and slot ~= nil then
				local link = GetContainerItemLink(bag, slot)
				if link and CraftTree_ReceiveLink(link) then
					return
				end
			end
		end
		return original(button)
	end)
end

local chatInsertHooked = nil
local chatVisibleHooked = nil

local function HookChatEditBoxInsert()
	if not ChatFrameEditBox then
		return
	end
	if not chatInsertHooked then
		local original = ChatFrameEditBox.Insert
		if type(original) == "function" then
			chatInsertHooked = 1
			ChatFrameEditBox.Insert = function(self, text)
				if CraftTreeWantsLinks() and text and string.find(text, "item:") then
					CraftTree_ReceiveLink(text)
					return
				end
				return original(self, text)
			end
		end
	end
	-- Make bags/AtlasLoot take the "chat open" path (InsertLink) while CraftTree is open.
	if not chatVisibleHooked and ChatFrameEditBox.IsVisible then
		chatVisibleHooked = 1
		local origVisible = ChatFrameEditBox.IsVisible
		ChatFrameEditBox.IsVisible = function(self)
			if CraftTreeWantsLinks() then
				return 1
			end
			return origVisible(self)
		end
	end
end

local atlasLootHooked = nil
local function HookAtlasLoot()
	if atlasLootHooked then
		return
	end
	if type(AtlasLoot_SayItemReagents) ~= "function" and type(AtlasLootItem_OnClick) ~= "function" then
		return
	end
	atlasLootHooked = 1

	if type(AtlasLoot_SayItemReagents) == "function" then
		local original = AtlasLoot_SayItemReagents
		AtlasLoot_SayItemReagents = function(id, color, name, safe)
			if CraftTreeWantsLinks() then
				local itemId = ResolveAtlasLootId(id)
				if itemId and ReceiveItemId(itemId, name) then
					return
				end
			end
			return original(id, color, name, safe)
		end
	end

	if type(AtlasLootItem_OnClick) == "function" then
		local original = AtlasLootItem_OnClick
		AtlasLootItem_OnClick = function()
			if CraftTreeWantsLinks() and IsShiftKeyDown() and this and this.itemID and this.itemID ~= 0 then
				local itemId = ResolveAtlasLootId(this.itemID)
				local name
				if this.GetID then
					local fs = getglobal("AtlasLootItem_" .. this:GetID() .. "_Name")
					if fs then
						name = fs:GetText()
						name = string.gsub(name or "", "|cff%x%x%x%x%x%x", "")
						name = string.gsub(name, "|r", "")
					end
				end
				if itemId and ReceiveItemId(itemId, name) then
					return
				end
			end
			return original()
		end
	end
end

-- ChatEdit_InsertLink: used by default bags when chat is open
local Original_ChatEdit_InsertLink = ChatEdit_InsertLink
function ChatEdit_InsertLink(link)
	if CraftTreeWantsLinks() and link and string.find(link, "item:") then
		CraftTree_ReceiveLink(link)
		return true
	end
	if Original_ChatEdit_InsertLink then
		return Original_ChatEdit_InsertLink(link)
	end
end

-- SetItemRef: shift-clicking an item link in chat
local Original_SetItemRef = SetItemRef
function SetItemRef(link, text, button)
	if CraftTreeWantsLinks() and IsShiftKeyDown() and link and string.find(link, "^item:") then
		if text and string.find(text, "item:") then
			CraftTree_ReceiveLink(text)
		else
			CraftTree_ReceiveLink(link)
		end
		return
	end
	if Original_SetItemRef then
		return Original_SetItemRef(link, text, button)
	end
end

local function InstallClickHooks()
	HookContainerClick("ContainerFrameItemButton_OnClick")
	HookContainerClick("BankFrameItemButtonGeneric_OnClick")
	HookContainerClick("BankFrameItemButton_OnClick")
	HookChatEditBoxInsert()
	HookAtlasLoot()
end

SLASH_CRAFTTREE1 = "/crafttree"
SLASH_CRAFTTREE2 = "/ct"
SlashCmdList["CRAFTTREE"] = function(msg)
	msg = msg or ""
	msg = string.gsub(msg, "^%s+", "")
	msg = string.gsub(msg, "%s+$", "")
	if msg == "" or string.lower(msg) == "toggle" then
		CraftTree_Toggle()
		return
	end
	local qty = 1
	local rest = msg
	local _, _, q, r = string.find(msg, "^(%d+)%s+(.+)$")
	if q and r then
		qty = tonumber(q) or 1
		rest = r
	end
	local itemId = ParseItemId(rest)
	if not itemId then
		CraftTreeFrame:Show()
		if CraftTreeFrameInput then
			CraftTreeFrameInput:SetText(rest)
		end
		CraftTree_OnInputEnter()
		return
	end
	if CraftTreeFrameInput then
		CraftTreeFrameInput:SetText(rest)
		CraftTreeFrameQty:SetText(tostring(qty))
	end
	CraftTree_ShowReport(itemId, qty)
end

local function RefreshOpenReport()
	if not (CraftTreeFrame and CraftTreeFrame:IsShown() and CraftTreeFrameInput) then
		return
	end
	local itemId = ParseItemId(CraftTreeFrameInput:GetText())
	if itemId then
		local qty = tonumber(CraftTreeFrameQty:GetText()) or 1
		CraftTree_ShowReport(itemId, qty)
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" then
		if arg1 == "CraftTree" then
			local n = 0
			if CraftTreeDB then
				for _ in pairs(CraftTreeDB) do
					n = n + 1
				end
			end
			local bagshui = (Bagshui and "yes") or (BagshuiData and "data-only") or "no"
			DEFAULT_CHAT_FRAME:AddMessage("|cff00ff96CraftTree|r loaded (" .. n .. " crafts, Bagshui: " .. bagshui .. "). /crafttree or /ct")
			DEFAULT_CHAT_FRAME:AddMessage("|cff00ff96CraftTree:|r with window open, shift-click items from bags/chat (Alt+Shift = normal game behavior)")
			InstallClickHooks()
		elseif arg1 == "Bagshui" or arg1 == "AtlasLoot" then
			-- Re-hook after inventory/loot addons load
			InstallClickHooks()
			HookAtlasLoot()
		end
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		InstallClickHooks()
		HookAtlasLoot()
		return
	end
	RefreshOpenReport()
end)
