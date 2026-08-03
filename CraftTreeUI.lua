-- CraftTree visual UI: icon tree + base-mat shopping strip

local ROW_HEIGHT = 28
local ICON_SIZE = 24
local GOAL_ICON = 40
local SHOP_ICON = 36
local MAX_TREE_ROWS = 120
local MAX_SHOP_SLOTS = 64
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Used when client item cache has no texture yet (common for some bars/ores).
local ICON_FALLBACK = {
	[12359] = "Interface\\Icons\\INV_Ingot_07",        -- Thorium Bar
	[10620] = "Interface\\Icons\\INV_Ore_Thorium_02",  -- Thorium Ore
	[12360] = "Interface\\Icons\\INV_Ingot_Thorium",   -- Arcanite Bar
	[12655] = "Interface\\Icons\\INV_Ingot_Thorium",   -- Enchanted Thorium Bar
	[11371] = "Interface\\Icons\\INV_Ingot_Mithril01", -- Dark Iron Bar
	[3577] = "Interface\\Icons\\INV_Ingot_03",         -- Gold Bar
	[3575] = "Interface\\Icons\\INV_Ingot_Iron",       -- Iron Bar
	[2842] = "Interface\\Icons\\INV_Ingot_01",         -- Silver Bar
	[2841] = "Interface\\Icons\\INV_Ingot_Bronze",     -- Bronze Bar
	[2840] = "Interface\\Icons\\INV_Ingot_02",         -- Copper Bar
	[3576] = "Interface\\Icons\\INV_Ingot_Tin",        -- Tin Bar
	[3859] = "Interface\\Icons\\INV_Ingot_Steel",      -- Steel Bar
	[3860] = "Interface\\Icons\\INV_Ingot_06",         -- Mithril Bar
	[6037] = "Interface\\Icons\\INV_Ingot_08",         -- Truesilver Bar
	[2770] = "Interface\\Icons\\INV_Ore_Copper_01",
	[2771] = "Interface\\Icons\\INV_Ore_Tin_01",
	[2772] = "Interface\\Icons\\INV_Ore_Iron_01",
	[2775] = "Interface\\Icons\\INV_Ore_Silver_01",
	[2776] = "Interface\\Icons\\INV_Ore_Gold_01",
	[3858] = "Interface\\Icons\\INV_Ore_Mithril_02",
	[7911] = "Interface\\Icons\\INV_Ore_Truesilver",
}

local treeRows = {}
local shopSlots = {}
local uiReady = false
local lastRender = nil

local function NormalizeTexture(tex)
	if type(tex) ~= "string" or tex == "" then
		return nil
	end
	if not string.find(tex, "\\") and not string.find(tex, "/") then
		tex = "Interface\\Icons\\" .. tex
	end
	return tex
end

local function QualityColor(quality)
	if quality and GetItemQualityColor then
		local r, g, b = GetItemQualityColor(quality)
		return r, g, b
	end
	return 1, 0.82, 0
end

-- Vanilla 1.12: name, link, quality, minLevel, type, subtype, stack, equipLoc, texture (9 values)
local function ItemInfo(itemId)
	local name, link, quality, _, _, _, _, _, texture = GetItemInfo(itemId)

	if not name then
		if GameTooltip and GameTooltip.SetHyperlink then
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			GameTooltip:SetHyperlink("item:" .. tostring(itemId) .. ":0:0:0")
			GameTooltip:Hide()
		end
		name, link, quality, _, _, _, _, _, texture = GetItemInfo(itemId)
	end

	texture = NormalizeTexture(texture)

	if not texture then
		local info = { GetItemInfo(itemId) }
		local i
		for i = 1, table.getn(info) do
			local v = NormalizeTexture(info[i])
			if v and (
				string.find(v, "Icons")
				or string.find(v, "INV_")
				or string.find(v, "Spell_")
				or string.find(v, "Trade_")
			) then
				texture = v
				break
			end
		end
	end

	if not texture and ICON_FALLBACK[itemId] then
		texture = ICON_FALLBACK[itemId]
	end
	if not texture then
		texture = QUESTION
	end

	if not name then
		local recipes = CraftTreeDB and CraftTreeDB[itemId]
		if recipes and recipes[1] and recipes[1].name ~= "" then
			name = recipes[1].name
		else
			name = "Unknown Item"
		end
	end

	return name, texture, quality or 1, link
end

local function ShowItemTooltip(owner, itemId)
	if not itemId then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. tostring(itemId) .. ":0:0:0")
	local src = CraftTreeSources and CraftTreeSources[itemId]
	if src and src.text then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(src.text, 1.0, 0.82, 0.3)
	end
	local owned, cur, oth, ownSrc = CraftTree_GetOwned(itemId)
	if owned then
		GameTooltip:AddLine(" ")
		if ownSrc == "bagshui" or ownSrc == "bagshui-data" then
			GameTooltip:AddLine(string.format("Owned: %d  (here %d / alts %d)", owned, cur or 0, oth or 0), 0.6, 0.9, 1)
		else
			GameTooltip:AddLine(string.format("Owned: %d (%s)", owned, ownSrc or "?"), 0.6, 0.9, 1)
		end
	end
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function SetupMouseWheel(scrollFrame)
	if not scrollFrame or scrollFrame.CraftTreeWheel then
		return
	end
	scrollFrame.CraftTreeWheel = 1
	scrollFrame:EnableMouse(1)
	scrollFrame:EnableMouseWheel(1)
	scrollFrame:SetScript("OnMouseWheel", function()
		local step = ROW_HEIGHT * 3
		local cur = this:GetVerticalScroll() or 0
		local max = 0
		if this.GetVerticalScrollRange then
			max = this:GetVerticalScrollRange() or 0
		end
		local bar = getglobal(this:GetName() .. "ScrollBar")
		if bar and bar.GetMinMaxValues then
			local _, barMax = bar:GetMinMaxValues()
			if barMax and barMax > max then
				max = barMax
			end
		end
		local new = cur - ((arg1 or 0) * step)
		if new < 0 then
			new = 0
		elseif max > 0 and new > max then
			new = max
		end
		this:SetVerticalScroll(new)
		if bar then
			bar:SetValue(new)
		end
	end)
end

local function ForwardWheelTo(scrollFrame, frame)
	if not frame or not scrollFrame then
		return
	end
	frame:EnableMouseWheel(1)
	frame:SetScript("OnMouseWheel", function()
		local step = ROW_HEIGHT * 3
		local cur = scrollFrame:GetVerticalScroll() or 0
		local max = 0
		if scrollFrame.GetVerticalScrollRange then
			max = scrollFrame:GetVerticalScrollRange() or 0
		end
		local bar = getglobal(scrollFrame:GetName() .. "ScrollBar")
		if bar and bar.GetMinMaxValues then
			local _, barMax = bar:GetMinMaxValues()
			if barMax and barMax > max then
				max = barMax
			end
		end
		local new = cur - ((arg1 or 0) * step)
		if new < 0 then
			new = 0
		elseif max > 0 and new > max then
			new = max
		end
		scrollFrame:SetVerticalScroll(new)
		if bar then
			bar:SetValue(new)
		end
	end)
end

local function UpdateScroll(scrollFrame, child, height)
	if not scrollFrame or not child then
		return
	end
	local view = scrollFrame:GetHeight() or 0
	if height < view then
		height = view
	end
	child:SetHeight(height)
	if scrollFrame.UpdateScrollChildRect then
		scrollFrame:UpdateScrollChildRect()
	end
	local max = height - view
	if max < 0 then
		max = 0
	end
	local bar = getglobal(scrollFrame:GetName() .. "ScrollBar")
	if bar then
		bar:SetMinMaxValues(0, max)
		bar:SetValue(0)
	end
	scrollFrame:SetVerticalScroll(0)
end

local function MakeIconButton(parent, size, name)
	local btn = CreateFrame("Button", name, parent)
	btn:SetWidth(size)
	btn:SetHeight(size)
	local tex = btn:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	btn.icon = tex
	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	border:SetBlendMode("ADD")
	border:SetAlpha(0.5)
	border:SetWidth(size * 1.6)
	border:SetHeight(size * 1.6)
	border:SetPoint("CENTER", btn, "CENTER", 0, 0)
	btn.border = border
	local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
	btn.count = count
	btn:SetScript("OnLeave", HideTooltip)
	btn:SetScript("OnEnter", function()
		ShowItemTooltip(this, this.itemId)
	end)
	return btn
end

function CraftTree_InitGoal(frame)
	if frame.icon then
		return
	end
	frame.icon = MakeIconButton(frame, GOAL_ICON, "CraftTreeGoalIcon")
	frame.icon:SetPoint("LEFT", frame, "LEFT", 8, 0)
	frame.name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	frame.name:SetPoint("LEFT", frame.icon, "RIGHT", 10, 6)
	frame.name:SetJustifyH("LEFT")
	frame.name:SetWidth(420)
	frame.sub = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
	frame.sub:SetJustifyH("LEFT")
	frame.sub:SetWidth(420)
	frame.name:SetText("No item selected")
	frame.sub:SetText("Expand a craft to see its material tree")
	frame.icon.icon:SetTexture(QUESTION)
end

local function CreateTreeRow(index)
	local row = CreateFrame("Frame", "CraftTreeTreeRow" .. index, CraftTreeTreeChild)
	row:SetWidth(500)
	row:SetHeight(ROW_HEIGHT)
	row:EnableMouse(1)
	row.icon = MakeIconButton(row, ICON_SIZE, "CraftTreeTreeRow" .. index .. "Icon")
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWidth(300)
	row.status = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.status:SetJustifyH("RIGHT")
	row.status:SetWidth(180)
	ForwardWheelTo(CraftTreeTreeScroll, row)
	ForwardWheelTo(CraftTreeTreeScroll, row.icon)
	row:Hide()
	return row
end

local function CreateShopSlot(index)
	local slot = CreateFrame("Frame", "CraftTreeShopSlot" .. index, CraftTreeShopChild)
	slot:SetWidth(SHOP_ICON + 8)
	slot:SetHeight(SHOP_ICON + 22)
	slot.icon = MakeIconButton(slot, SHOP_ICON, "CraftTreeShopSlot" .. index .. "Icon")
	slot.icon:SetPoint("TOP", slot, "TOP", 0, 0)
	slot.need = slot:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	slot.need:SetPoint("TOP", slot.icon, "BOTTOM", 0, -1)
	slot.need:SetJustifyH("CENTER")
	ForwardWheelTo(CraftTreeShopScroll, slot)
	ForwardWheelTo(CraftTreeShopScroll, slot.icon)
	slot:Hide()
	return slot
end

function CraftTree_InitUI()
	if uiReady then
		return
	end
	if CraftTreeGoal and not CraftTreeGoal.icon then
		CraftTree_InitGoal(CraftTreeGoal)
	end
	SetupMouseWheel(CraftTreeTreeScroll)
	SetupMouseWheel(CraftTreeShopScroll)
	ForwardWheelTo(CraftTreeTreeScroll, CraftTreeTreeChild)
	ForwardWheelTo(CraftTreeShopScroll, CraftTreeShopChild)
	local i
	for i = 1, MAX_TREE_ROWS do
		treeRows[i] = CreateTreeRow(i)
	end
	for i = 1, MAX_SHOP_SLOTS do
		shopSlots[i] = CreateShopSlot(i)
	end
	CraftTree_InitSuggestions()
	uiReady = true
end

local function FlattenTree(node, depth, out)
	table.insert(out, { node = node, depth = depth })
	local i
	for i = 1, table.getn(node.children) do
		FlattenTree(node.children[i], depth + 1, out)
	end
end

local function SkillLabel(itemId)
	local src = CraftTreeSources and CraftTreeSources[itemId]
	if not src then
		return nil
	end
	if src.profession and src.skill then
		return src.profession .. " " .. src.skill
	end
	return src.text
end

local function SetGoal(itemId, qty, node)
	if not CraftTreeGoal or not CraftTreeGoal.icon then
		CraftTree_InitGoal(CraftTreeGoal)
	end
	local name, texture, quality = ItemInfo(itemId)
	CraftTreeGoal.icon.itemId = itemId
	CraftTreeGoal.icon.icon:SetTexture(texture)
	local r, g, b = QualityColor(quality)
	CraftTreeGoal.name:SetText(string.format("%dx %s", qty, name))
	CraftTreeGoal.name:SetTextColor(r, g, b)
	local extra = ""
	if node and not node.leaf and node.crafts then
		extra = string.format("Crafts needed: %d", node.crafts)
	end
	local _, _, _, src = CraftTree_GetOwned(itemId)
	local srcLabel = src or "?"
	if src == "bagshui" then
		srcLabel = "Bagshui (all chars)"
	elseif src == "bagshui-data" then
		srcLabel = "Bagshui data"
	elseif src == "local" then
		srcLabel = "local bags"
	end
	local skill = SkillLabel(itemId)
	local bits = {}
	if skill then
		table.insert(bits, skill)
	end
	if extra ~= "" then
		table.insert(bits, extra)
	end
	table.insert(bits, "Ownership: " .. srcLabel)
	CraftTreeGoal.sub:SetText(table.concat(bits, "  ·  "))
end

local function RenderTree(node)
	local flat = {}
	FlattenTree(node, 0, flat)
	local display = {}
	local i
	for i = 1, table.getn(flat) do
		if flat[i].depth > 0 then
			table.insert(display, flat[i])
		elseif table.getn(flat) == 1 then
			table.insert(display, flat[i])
		end
	end

	local count = table.getn(display)
	local height = count * ROW_HEIGHT + 12
	UpdateScroll(CraftTreeTreeScroll, CraftTreeTreeChild, height)

	for i = 1, MAX_TREE_ROWS do
		local row = treeRows[i]
		local entry = display[i]
		if entry then
			local n = entry.node
			local depth = entry.depth
			local name, texture, quality = ItemInfo(n.id)
			local indent = 8 + (depth - 1) * 18
			if depth == 0 then
				indent = 8
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", CraftTreeTreeChild, "TOPLEFT", indent, -((i - 1) * ROW_HEIGHT) - 2)
			row.icon.itemId = n.id
			row.icon.icon:SetTexture(texture)
			row.icon.count:SetText(n.need > 1 and tostring(n.need) or "")
			local prefix = n.leaf and "•" or "+"
			local label = string.format("%s %s", prefix, name)
			if not n.leaf and n.crafts and n.crafts > 0 then
				label = label .. string.format("  (x%d)", n.crafts)
			end
			row.label:SetText(label)
			local r, g, b = QualityColor(quality)
			row.label:SetTextColor(r, g, b)

			-- Right side: profession + skill (fallback to owned status for unknown base mats)
			local skill = SkillLabel(n.id)
			if skill then
				row.status:SetText(skill)
				if n.leaf then
					row.status:SetTextColor(0.55, 0.85, 1.0)
				else
					row.status:SetTextColor(1.0, 0.82, 0.3)
				end
			elseif n.leaf then
				local owned = CraftTree_GetOwned(n.id)
				local short = math.max(0, n.need - owned)
				if short == 0 then
					row.status:SetText("OK")
					row.status:SetTextColor(0.3, 0.9, 0.3)
				else
					row.status:SetText(string.format("need %d", short))
					row.status:SetTextColor(1, 0.35, 0.35)
				end
			else
				row.status:SetText("")
			end
			row:Show()
		else
			row:Hide()
		end
	end
end

local function RenderShop(shopping)
	local list = {}
	local id, count
	for id, count in pairs(shopping) do
		local owned = CraftTree_GetOwned(id)
		table.insert(list, {
			id = id,
			count = count,
			owned = owned,
			short = math.max(0, count - owned),
			name = ItemInfo(id),
		})
	end
	table.sort(list, function(a, b)
		if (a.short > 0) ~= (b.short > 0) then
			return a.short > 0
		end
		return a.name < b.name
	end)

	local missing, covered = 0, 0
	local i
	for i = 1, table.getn(list) do
		if list[i].short > 0 then
			missing = missing + 1
		else
			covered = covered + 1
		end
	end
	if CraftTreeFrameShopSummary then
		CraftTreeFrameShopSummary:SetText(string.format("(%d unique · %d needed · %d covered)", table.getn(list), missing, covered))
	end

	local cols = 11
	local total = table.getn(list)
	local rows = math.max(1, math.ceil(total / cols))
	local height = rows * (SHOP_ICON + 24) + 8
	UpdateScroll(CraftTreeShopScroll, CraftTreeShopChild, height)
	CraftTreeShopChild:SetWidth(math.max(500, cols * (SHOP_ICON + 8)))

	for i = 1, MAX_SHOP_SLOTS do
		local slot = shopSlots[i]
		local row = list[i]
		if row then
			local name, texture = ItemInfo(row.id)
			local col = math.mod(i - 1, cols)
			local r = math.floor((i - 1) / cols)
			slot:ClearAllPoints()
			slot:SetPoint("TOPLEFT", CraftTreeShopChild, "TOPLEFT", col * (SHOP_ICON + 8), -(r * (SHOP_ICON + 24)))
			slot.icon.itemId = row.id
			slot.icon.icon:SetTexture(texture)
			slot.icon.count:SetText(tostring(row.count))
			if row.short == 0 then
				slot.need:SetText("OK")
				slot.need:SetTextColor(0.3, 0.9, 0.3)
			else
				slot.need:SetText("need " .. row.short)
				slot.need:SetTextColor(1, 0.4, 0.4)
			end
			slot:Show()
		else
			slot:Hide()
		end
	end
end

local function ClearVisual()
	if CraftTreeGoal and CraftTreeGoal.name then
		CraftTreeGoal.name:SetText("No item selected")
		CraftTreeGoal.sub:SetText("Expand a craft to see its material tree")
		if CraftTreeGoal.icon then
			CraftTreeGoal.icon.itemId = nil
			CraftTreeGoal.icon.icon:SetTexture(QUESTION)
			CraftTreeGoal.icon.count:SetText("")
		end
	end
	local i
	for i = 1, table.getn(treeRows) do
		treeRows[i]:Hide()
	end
	for i = 1, table.getn(shopSlots) do
		shopSlots[i]:Hide()
	end
	if CraftTreeFrameShopSummary then
		CraftTreeFrameShopSummary:SetText("")
	end
end

function CraftTree_ShowMessage(text)
	CraftTree_InitUI()
	ClearVisual()
	if CraftTreeGoal and CraftTreeGoal.sub then
		CraftTreeGoal.name:SetText("CraftTree")
		CraftTreeGoal.sub:SetText(text)
	end
end

function CraftTree_RenderResult(itemId, qty, node, shopping)
	CraftTree_InitUI()
	CraftTree_HideSuggestions()
	lastRender = { itemId = itemId, qty = qty, node = node, shopping = shopping }
	SetGoal(itemId, qty, node)
	RenderTree(node)
	RenderShop(shopping or {})
end

------------------------------------------------------------------------
-- Autocomplete suggestions
------------------------------------------------------------------------

local MAX_SUGGEST = 10
local SUGGEST_ROW = 20
local suggestFrame = nil
local suggestButtons = {}
local suggestList = {}
local suggestIndex = 0
local suggestIgnore = nil
local hideSuggestAt = nil

local function HighlightSuggest(index)
	suggestIndex = index or 0
	local i
	for i = 1, table.getn(suggestButtons) do
		local btn = suggestButtons[i]
		if btn.hl then
			if i == suggestIndex then
				btn.hl:SetAlpha(0.6)
				if btn.label then
					btn.label:SetTextColor(1, 1, 1)
				end
			else
				btn.hl:SetAlpha(0)
				if btn.label then
					btn.label:SetTextColor(1, 0.82, 0)
				end
			end
		end
	end
end

function CraftTree_HideSuggestions()
	if suggestFrame then
		suggestFrame:Hide()
	end
	suggestList = {}
	suggestIndex = 0
	hideSuggestAt = nil
end

function CraftTree_SuggestionsVisible()
	return suggestFrame and suggestFrame:IsShown()
end

function CraftTree_HideSuggestionsDelayed()
	-- Allow click on a suggestion before focus-loss hides the list
	hideSuggestAt = GetTime() + 0.2
	if not suggestFrame then
		return
	end
	suggestFrame:SetScript("OnUpdate", function()
		if hideSuggestAt and GetTime() >= hideSuggestAt then
			this:SetScript("OnUpdate", nil)
			CraftTree_HideSuggestions()
		end
	end)
end

local function ApplySuggestion(entry)
	if not entry then
		return false
	end
	suggestIgnore = entry.name
	CraftTree_HideSuggestions()
	if CraftTreeFrameInput then
		CraftTreeFrameInput:SetText(entry.name)
		CraftTreeFrameInput:ClearFocus()
	end
	local qty = tonumber(CraftTreeFrameQty and CraftTreeFrameQty:GetText()) or 1
	CraftTree_ShowReport(entry.id, qty)
	return true
end

function CraftTree_TakeSuggestion()
	if not CraftTree_SuggestionsVisible() then
		return false
	end
	if suggestIndex < 1 or suggestIndex > table.getn(suggestList) then
		if table.getn(suggestList) >= 1 then
			return ApplySuggestion(suggestList[1])
		end
		return false
	end
	return ApplySuggestion(suggestList[suggestIndex])
end

function CraftTree_SuggestTab()
	if not CraftTree_SuggestionsVisible() or table.getn(suggestList) == 0 then
		return
	end
	local nextIndex = suggestIndex + 1
	if nextIndex > table.getn(suggestList) then
		nextIndex = 1
	end
	HighlightSuggest(nextIndex)
	suggestIgnore = suggestList[nextIndex].name
	if CraftTreeFrameInput then
		CraftTreeFrameInput:SetText(suggestList[nextIndex].name)
	end
end

function CraftTree_InitSuggestions()
	if suggestFrame then
		return
	end
	suggestFrame = CreateFrame("Frame", "CraftTreeSuggestFrame", CraftTreeFrame)
	suggestFrame:SetFrameStrata("FULLSCREEN_DIALOG")
	suggestFrame:SetWidth(380)
	suggestFrame:SetHeight(MAX_SUGGEST * SUGGEST_ROW + 8)
	suggestFrame:SetPoint("TOPLEFT", CraftTreeFrameInputBox, "BOTTOMLEFT", 0, -2)
	suggestFrame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 12,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	suggestFrame:SetBackdropColor(0, 0, 0, 0.95)
	suggestFrame:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
	suggestFrame:EnableMouse(1)
	suggestFrame:Hide()

	local i
	for i = 1, MAX_SUGGEST do
		local btn = CreateFrame("Button", "CraftTreeSuggestBtn" .. i, suggestFrame)
		btn:SetWidth(370)
		btn:SetHeight(SUGGEST_ROW)
		btn:SetPoint("TOPLEFT", suggestFrame, "TOPLEFT", 5, -4 - ((i - 1) * SUGGEST_ROW))
		local label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetPoint("LEFT", btn, "LEFT", 4, 0)
		label:SetJustifyH("LEFT")
		label:SetWidth(360)
		btn.label = label
		local hl = btn:CreateTexture(nil, "BACKGROUND")
		hl:SetAllPoints()
		hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		hl:SetBlendMode("ADD")
		hl:SetAlpha(0)
		btn.hl = hl
		btn:SetScript("OnClick", function()
			ApplySuggestion(this.entry)
		end)
		btn:SetScript("OnEnter", function()
			HighlightSuggest(this.index)
		end)
		btn:Hide()
		suggestButtons[i] = btn
	end
end

function CraftTree_UpdateSuggestions()
	if not CraftTreeFrameInput then
		return
	end
	CraftTree_InitSuggestions()
	local text = CraftTreeFrameInput:GetText() or ""
	if suggestIgnore and text == suggestIgnore then
		return
	end
	suggestIgnore = nil

	if not CraftTreeFrameInput:HasFocus() then
		CraftTree_HideSuggestions()
		return
	end

	local list = {}
	if CraftTree_GetSuggestions then
		list = CraftTree_GetSuggestions(text, MAX_SUGGEST) or {}
	end
	suggestList = list

	if table.getn(list) == 0 then
		CraftTree_HideSuggestions()
		return
	end

	local i
	for i = 1, MAX_SUGGEST do
		local btn = suggestButtons[i]
		local entry = list[i]
		if entry then
			btn.entry = entry
			btn.index = i
			btn.label:SetText(entry.name)
			btn:Show()
		else
			btn.entry = nil
			btn:Hide()
		end
	end

	local shown = table.getn(list)
	suggestFrame:SetHeight(shown * SUGGEST_ROW + 8)
	suggestFrame:Show()
	HighlightSuggest(1)
end

-- After tooltips load item data, refresh icons once.
local refreshFrame = CreateFrame("Frame")
refreshFrame.elapsed = 0
refreshFrame:SetScript("OnUpdate", function()
	if not lastRender then
		return
	end
	this.elapsed = this.elapsed + (arg1 or 0)
	if this.elapsed < 0.5 then
		return
	end
	this.elapsed = 0
	-- Only re-render a couple times after expand to pick up newly cached icons
	if not this.passes then
		this.passes = 0
	end
	this.passes = this.passes + 1
	if this.passes <= 4 then
		CraftTree_RenderResult(lastRender.itemId, lastRender.qty, lastRender.node, lastRender.shopping)
	else
		this.passes = 0
		lastRender = nil
	end
end)
