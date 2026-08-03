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
	return "item:" .. tostring(itemId)
end

local function ParseItemId(text)
	if not text then
		return nil
	end
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	local _, _, linkId = string.find(text, "item:(%d+)")
	if linkId then
		return tonumber(linkId)
	end
	local _, _, bare = string.find(text, "^(%d+)$")
	if bare then
		return tonumber(bare)
	end
	local lower = string.lower(text)
	local foundId
	if CraftTreeDB then
		for itemId, recipes in pairs(CraftTreeDB) do
			local n = recipes[1] and recipes[1].name
			if n and string.find(string.lower(n), lower, 1, true) then
				foundId = itemId
				break
			end
		end
	end
	return foundId
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
		status = "|cff66ff66OK|r"
	elseif ownedTotal > 0 then
		status = "|cffffff00need " .. short .. "|r"
	else
		status = "|cffff6666need " .. short .. "|r"
	end
	local detail = string.format("own %d", ownedTotal)
	if source == "bagshui" or source == "bagshui-data" then
		if ownedOther > 0 or ownedCurrent > 0 then
			detail = string.format("own %d (here %d / alts %d)", ownedTotal, ownedCurrent, ownedOther)
		end
	end
	return detail .. " — " .. status
end

------------------------------------------------------------------------
-- Resolver
------------------------------------------------------------------------

function CraftTree_Resolve(itemId, need, shopping, depth, stack)
	need = need or 1
	shopping = shopping or {}
	depth = depth or 0
	stack = stack or {}

	local node = {
		id = itemId,
		need = need,
		name = ItemName(itemId),
		children = {},
		leaf = false,
		crafts = 0,
		yield = 1,
		blocked = false,
	}

	if depth > MAX_DEPTH then
		node.leaf = true
		node.blocked = true
		shopping[itemId] = (shopping[itemId] or 0) + need
		return node, shopping
	end

	if stack[itemId] then
		node.leaf = true
		node.blocked = true
		shopping[itemId] = (shopping[itemId] or 0) + need
		return node, shopping
	end

	local recipes = CraftTreeDB and CraftTreeDB[itemId]
	if not recipes or not recipes[1] or not recipes[1].reagents then
		node.leaf = true
		shopping[itemId] = (shopping[itemId] or 0) + need
		return node, shopping
	end

	local recipe = recipes[1]
	local yield = recipe.yield or 1
	if yield < 1 then
		yield = 1
	end
	local crafts = math.ceil(need / yield)
	node.crafts = crafts
	node.yield = yield
	node.name = recipe.name ~= "" and recipe.name or node.name
	node.spell = recipe.spell
	if table.getn(recipes) > 1 then
		node.altRecipes = table.getn(recipes)
	end

	stack[itemId] = true
	local i
	for i = 1, table.getn(recipe.reagents) do
		local reag = recipe.reagents[i]
		local rid = reag[1]
		local rcnt = reag[2] or 1
		local childNeed = rcnt * crafts
		local child = CraftTree_Resolve(rid, childNeed, shopping, depth + 1, stack)
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
	local lines = {}
	local _, _, _, ownSource = CraftTree_GetOwned(itemId)
	table.insert(lines, string.format("=== Tree: %dx %s (%d) ===", qty, ItemName(itemId), itemId))
	table.insert(lines, "Ownership: " .. OwnershipSourceLabel(ownSource))
	if not CraftTreeDB[itemId] then
		table.insert(lines, "(Not a known craft result in DB — showing as base item)")
	end
	local treeLines = FormatTree(node)
	local i
	for i = 1, table.getn(treeLines) do
		table.insert(lines, treeLines[i])
	end
	table.insert(lines, "")
	table.insert(lines, "=== Shopping list (base mats) ===")
	local shop = SortedShopping(shopping)
	local missing = 0
	local covered = 0
	for i = 1, table.getn(shop) do
		local row = shop[i]
		local ownTxt = FormatOwnLine(row.count, row.owned, row.ownedCurrent, row.ownedOther, row.source)
		table.insert(lines, string.format("  %dx %s — %s", row.count, row.name, ownTxt))
		if row.short > 0 then
			missing = missing + 1
		else
			covered = covered + 1
		end
	end
	table.insert(lines, string.format("(%d unique — %d still needed, %d covered)", table.getn(shop), missing, covered))
	return table.concat(lines, "\n"), node, shopping
end

function CraftTree_ShowReport(itemId, qty)
	local text = CraftTree_BuildReport(itemId, qty)
	if CraftTreeOutput then
		CraftTreeOutput:SetText(text)
		local _, count = string.gsub(text, "\n", "\n")
		local height = math.max(320, (count + 4) * 12)
		CraftTreeFrameScrollChild:SetHeight(height)
		CraftTreeOutput:SetHeight(height)
	end
	CraftTreeFrame:Show()
end

function CraftTree_OnInputEnter()
	local text = CraftTreeFrameInput:GetText()
	local qty = tonumber(CraftTreeFrameQty:GetText()) or 1
	local itemId = ParseItemId(text)
	if not itemId then
		if CraftTreeOutput then
			CraftTreeOutput:SetText("Could not parse item. Shift-click an item, paste a link, enter an item ID, or a craft name.")
		end
		CraftTreeFrame:Show()
		return
	end
	CraftTree_ShowReport(itemId, qty)
end

function CraftTree_Toggle()
	if CraftTreeFrame:IsShown() then
		CraftTreeFrame:Hide()
	else
		CraftTreeFrame:Show()
		CraftTreeFrameInput:SetFocus()
	end
end

local Original_ChatEdit_InsertLink = ChatEdit_InsertLink
function ChatEdit_InsertLink(link)
	if CraftTreeFrame and CraftTreeFrame:IsShown() and CraftTreeFrameInput and CraftTreeFrameInput:HasFocus() then
		CraftTreeFrameInput:SetText(link)
		return true
	end
	if Original_ChatEdit_InsertLink then
		return Original_ChatEdit_InsertLink(link)
	end
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
		DEFAULT_CHAT_FRAME:AddMessage("|cffff5533CraftTree:|r could not parse item from: " .. msg)
		CraftTree_Toggle()
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
	if event == "ADDON_LOADED" and arg1 == "CraftTree" then
		local n = 0
		if CraftTreeDB then
			for _ in pairs(CraftTreeDB) do
				n = n + 1
			end
		end
		local bagshui = (Bagshui and "yes") or (BagshuiData and "data-only") or "no"
		DEFAULT_CHAT_FRAME:AddMessage("|cff00ff96CraftTree|r loaded (" .. n .. " crafts, Bagshui: " .. bagshui .. "). /crafttree or /ct")
		return
	end
	-- Bagshui catalog finishes a few seconds after login; bank open/close also changes local counts.
	RefreshOpenReport()
end)
