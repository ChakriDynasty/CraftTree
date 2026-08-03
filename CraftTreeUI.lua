-- CraftTree visual UI: icon tree + base-mat shopping strip

local ROW_HEIGHT = 28
local ICON_SIZE = 24
local GOAL_ICON = 40
local SHOP_ICON = 36
local MAX_TREE_ROWS = 80
local MAX_SHOP_SLOTS = 48
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local treeRows = {}
local shopSlots = {}
local uiReady = false

local function QualityColor(quality)
	if quality and GetItemQualityColor then
		local r, g, b = GetItemQualityColor(quality)
		return r, g, b
	end
	return 1, 0.82, 0
end

local function ItemInfo(itemId)
	local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemId)
	if not name then
		if GameTooltip and GameTooltip.SetHyperlink then
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			GameTooltip:SetHyperlink("item:" .. tostring(itemId) .. ":0:0:0")
			GameTooltip:Hide()
		end
		name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemId)
	end
	if not name then
		local recipes = CraftTreeDB and CraftTreeDB[itemId]
		if recipes and recipes[1] and recipes[1].name ~= "" then
			name = recipes[1].name
		else
			name = "item:" .. tostring(itemId)
		end
	end
	if type(texture) ~= "string" or texture == "" then
		-- Fallback if client return order differs
		local n2, l2, q2, a, b, c, d, e, f = GetItemInfo(itemId)
		if type(f) == "string" and string.find(f, "Interface\\Icons") then
			texture = f
		elseif type(e) == "string" and string.find(e, "Interface\\Icons") then
			texture = e
		else
			texture = QUESTION
		end
		if not quality and q2 then
			quality = q2
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
	local owned, cur, oth, src = CraftTree_GetOwned(itemId)
	if owned then
		GameTooltip:AddLine(" ")
		if src == "bagshui" or src == "bagshui-data" then
			GameTooltip:AddLine(string.format("Owned: %d  (here %d / alts %d)", owned, cur or 0, oth or 0), 0.6, 0.9, 1)
		else
			GameTooltip:AddLine(string.format("Owned: %d (%s)", owned, src or "?"), 0.6, 0.9, 1)
		end
	end
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
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
	row.icon = MakeIconButton(row, ICON_SIZE, "CraftTreeTreeRow" .. index .. "Icon")
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.branch = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.branch:SetPoint("RIGHT", row.icon, "LEFT", -2, 0)
	row.branch:SetText("")
	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWidth(280)
	row.status = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.status:SetJustifyH("RIGHT")
	row.status:SetWidth(160)
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
	local i
	for i = 1, MAX_TREE_ROWS do
		treeRows[i] = CreateTreeRow(i)
	end
	for i = 1, MAX_SHOP_SLOTS do
		shopSlots[i] = CreateShopSlot(i)
	end
	uiReady = true
end

local function FlattenTree(node, depth, out)
	table.insert(out, { node = node, depth = depth })
	local i
	for i = 1, table.getn(node.children) do
		FlattenTree(node.children[i], depth + 1, out)
	end
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
	CraftTreeGoal.sub:SetText((extra ~= "" and (extra .. "  ·  ") or "") .. "Ownership: " .. srcLabel)
end

local function RenderTree(node)
	local flat = {}
	FlattenTree(node, 0, flat)
	-- skip root in tree list (shown in goal); start from children only? User asked: top = goal, under = mats. So show root in goal AND optionally in tree. I'll skip depth 0 in scroll to avoid duplicate.
	local display = {}
	local i
	for i = 1, table.getn(flat) do
		if flat[i].depth > 0 then
			table.insert(display, flat[i])
		elseif table.getn(flat) == 1 then
			-- only root (base item, not a craft)
			table.insert(display, flat[i])
		end
	end

	local count = table.getn(display)
	local height = math.max(230, count * ROW_HEIGHT + 8)
	CraftTreeTreeChild:SetHeight(height)

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
				label = label .. string.format("  (craft x%d)", n.crafts)
			end
			row.label:SetText(label)
			local r, g, b = QualityColor(quality)
			row.label:SetTextColor(r, g, b)
			if n.leaf then
				local owned, cur, oth, src = CraftTree_GetOwned(n.id)
				local short = math.max(0, n.need - owned)
				if short == 0 then
					row.status:SetText("OK")
					row.status:SetTextColor(0.3, 0.9, 0.3)
				else
					row.status:SetText(string.format("need %d (own %d)", short, owned))
					row.status:SetTextColor(1, 0.35, 0.35)
				end
			else
				row.status:SetText("intermediate")
				row.status:SetTextColor(0.7, 0.7, 0.7)
			end
			row:Show()
		else
			row:Hide()
		end
	end
	CraftTreeTreeScroll:SetVerticalScroll(0)
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

	local cols = 12
	local total = table.getn(list)
	local rows = math.max(1, math.ceil(total / cols))
	CraftTreeShopChild:SetHeight(math.max(100, rows * (SHOP_ICON + 24)))
	CraftTreeShopChild:SetWidth(math.max(510, cols * (SHOP_ICON + 8)))

	for i = 1, MAX_SHOP_SLOTS do
		local slot = shopSlots[i]
		local row = list[i]
		if row then
			local name, texture, quality = ItemInfo(row.id)
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
	CraftTreeShopScroll:SetVerticalScroll(0)
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
	SetGoal(itemId, qty, node)
	RenderTree(node)
	RenderShop(shopping or {})
end
