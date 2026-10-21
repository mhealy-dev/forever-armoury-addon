--[[ The leveling gear part's panel: beside the character window, the pieces of the route to go and get at this level,
     then the ones coming, each as the game's item link with where it comes from under it. Gear.lua says which pieces
     those are; the game names the items from their ids (GetItemInfo), so the addon carries no item text. Each row is a
     button: hovering it shows the game's own tooltip for the item to the right of the panel, with where it comes from
     and the level the route has it at (the game's comparison with what's worn goes under it when it would cover the panel),
     and shift-click links the item in chat. ]]

local _, FA = ...
local Gear = FA.Gear

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ROWS, ROW_HEIGHT = 12, 32   -- ROWS: the rows the fixed height holds, when there is no character window to follow
local STATUS_HEIGHT = 52   -- the status text's four lines of small type
local ROWS_TOP = 122      -- under the status and the buttons
local SLOT_NAMES = { head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist", hands = "Hands",
  waist = "Waist", legs = "Legs", feet = "Feet", finger1 = "Ring", finger2 = "Ring", trinket1 = "Trinket", trinket2 = "Trinket",
  mainhand = "Main hand", offhand = "Off hand", ranged = "Ranged" }
local ROWS_BOTTOM = 20      -- the margin under the last row
local TOP_INSET = 12        -- how far under the window's top the panel hangs
local MORE = "\226\139\174"   -- the vertical ellipsis, as UTF-8 bytes
local panel, hooked, events
local entries, offset = {}, 0   -- the route's pieces in order: { piece, state, dim }; how many are scrolled off the top

--[[ The game's link for an item, or grey "item <id>" while the game hasn't loaded it (asked to; GET_ITEM_INFO_RECEIVED
     redraws). The link comes with its quality's colour. ]]
local function itemLink(id)
  local info = C_Item and C_Item.GetItemInfo or GetItemInfo
  local name, link = nil, nil
  if info then name, link = info(id) end
  if link then return link, true end
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return "|cff808080item " .. id .. "|r", false
end

--[[ The row whose tooltip is up, so a comparison the game shows can be told from one shown for another tooltip. ]]
local hovered

--[[ The game's comparison with what's worn (ShoppingTooltip1, and 2 for a second piece) goes beside the tooltip, on the
     left of it when the screen has no room on the right, which is over the panel's list. Then they stack under the
     tooltip instead. The game places them in TooltipComparisonManager:AnchorShoppingTooltips, which shows them and then sets
     their points, each time it builds or rebuilds the comparison (a rebuild, when an item's data arrives, shows nothing
     anew), so this runs after that call, and once more after our Show() in case the position wasn't there yet. A client
     that won't give a position, or errors on it, keeps the game's placement.
     Each comparison tooltip carries a CompareHeader ("Equipped", "If equipped together"), a frame that hangs above the
     tooltip's top edge (22 tall in the game's template, anchored to the tooltip's top left). Stacked flush under the one
     above, the tooltip would sit right over the header and cut the label off, so each hangs the header's height plus a
     small gap below the one above it. ]]
local function overPanel(tip)
  local ok, covers = pcall(function()
    local left, edge = tip:GetLeft(), panel:GetRight()
    return type(left) == "number" and type(edge) == "number" and left < edge - 1
  end)
  return ok and covers
end

local HEADER_HEIGHT, HEADER_GAP = 22, 4   -- the game's CompareHeader height, when the frame can't say; the space under what's above

local function headerHeight(tip)
  local ok, height = pcall(function()
    local header = tip.CompareHeader
    if type(header) == "table" and header:IsShown() then return header:GetHeight() end
  end)
  return ok and type(height) == "number" and height > 0 and height or HEADER_HEIGHT
end

local function stackComparison()
  if not hovered or (GameTooltip.IsOwned and not GameTooltip:IsOwned(hovered)) then return end
  local shown, over = {}, false
  for _, tip in ipairs({ ShoppingTooltip1 or false, ShoppingTooltip2 or false }) do
    if tip and tip:IsShown() then
      shown[#shown + 1] = tip
      over = over or overPanel(tip)
    end
  end
  if not over then return end
  local above = GameTooltip
  for _, tip in ipairs(shown) do
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -(headerHeight(tip) + HEADER_GAP))
    above = tip
  end
end

local comparisonHooked
local function hookComparison()
  if comparisonHooked or not (hooksecurefunc and TooltipComparisonManager and TooltipComparisonManager.AnchorShoppingTooltips) then return end
  comparisonHooked = true
  hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", function(self)
    if self.tooltip == GameTooltip then stackComparison() end
  end)
end

local function hideTooltip()
  hovered = nil
  GameTooltip:Hide()
end

--[[ The hover: the game's tooltip for the item, to the right of the panel, then where the piece comes from and the level
     the route has it at. SetItemByID, else the item's link, else its name and id, so the hover shows something whatever
     the client has. ]]
local function showTooltip(row)
  local piece = row.piece
  if not piece then return end
  hookComparison()   -- if the game's manager wasn't there when the character window hooked
  GameTooltip:SetOwner(row, "ANCHOR_NONE")
  hovered = row
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("TOPLEFT", panel, "TOPRIGHT", 0, 0)
  local drawn = GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, piece.id)
  if not drawn then drawn = pcall(GameTooltip.SetHyperlink, GameTooltip, row.link or ("item:" .. piece.id)) end
  if not drawn then GameTooltip:SetText((itemLink(piece.id))) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(Gear.SourceText(piece), 0.7, 0.7, 0.7, true)
  GameTooltip:AddLine("On the route at level " .. piece.level .. ".", 0.7, 0.7, 0.7, true)
  GameTooltip:Show()
  stackComparison()
end

--[[ Shift-click (the game's chat-link click) puts the item's link in the chat box. ]]
local function clickRow(row)
  if not (row.link and IsModifiedClick and IsModifiedClick()) then return end
  if HandleModifiedItemClick and HandleModifiedItemClick(row.link) then return end
  if IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(row.link) end
end

--[[ Row i, made when the panel first has room for it: the panel makes only as many as fit its height. ]]
local function makeRow(i)
  local row = CreateFrame("Button", nil, panel)
  row:SetSize(268, ROW_HEIGHT - 2)
  row:SetPoint("TOPLEFT", 16, -ROWS_TOP - (i - 1) * ROW_HEIGHT)
  row:EnableMouse(true)
  row:RegisterForClicks("LeftButtonUp")
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  row:GetHighlightTexture():SetBlendMode("ADD")
  row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.slot:SetPoint("TOPLEFT", 4, -2)
  row.slot:SetWidth(62)
  row.slot:SetJustifyH("LEFT")
  row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.item:SetPoint("TOPLEFT", 68, -1)
  row.item:SetPoint("TOPRIGHT", -46, -1)
  row.item:SetJustifyH("LEFT")
  row.item:SetWordWrap(false)
  row.state = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.state:SetPoint("TOPRIGHT", -4, -2)
  row.state:SetWidth(44)
  row.state:SetJustifyH("RIGHT")
  row.from = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.from:SetPoint("BOTTOMLEFT", 68, 2)
  row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")   -- the vertical ellipsis, with "N more" when pieces lie below
  row.mark:SetPoint("BOTTOMRIGHT", -4, 2)
  row.mark:SetJustifyH("RIGHT")
  row.from:SetPoint("BOTTOMRIGHT", row.mark, "BOTTOMLEFT", -4, 0)
  row.from:SetJustifyH("LEFT")
  row.from:SetWordWrap(false)
  row.from:SetTextColor(0.7, 0.7, 0.7)
  row:SetScript("OnEnter", showTooltip)
  row:SetScript("OnLeave", hideTooltip)
  row:SetScript("OnHide", function(self) if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then hideTooltip() end end)
  row:SetScript("OnClick", clickRow)
  return row
end

--[[ The panel's height: the character window's less the gap at its top, which the two anchors give it, and the fixed height
     when there is no window or it gives none. The window's height is read with a guard (the live client has thrown). ]]
local FIXED_HEIGHT = ROWS_TOP + ROWS * ROW_HEIGHT + ROWS_BOTTOM

local function heightOf()
  if not CharacterFrame then return FIXED_HEIGHT end
  local ok, height = pcall(function() return CharacterFrame:GetHeight() end)
  height = ok and type(height) == "number" and height - TOP_INSET or 0
  return height > 0 and height or FIXED_HEIGHT
end

--[[ How many rows fit between ROWS_TOP and the bottom margin, one at least. ]]
local function rowsFit(height)
  return math.max(1, math.floor((height - ROWS_TOP - ROWS_BOTTOM) / ROW_HEIGHT))
end

local function makePanel()
  local window = CharacterFrame or UIParent
  panel = CreateFrame("Frame", "ForeverArmouryGearPanel", window, TEMPLATE)
  panel:SetSize(300, heightOf())
  if CharacterFrame then
    panel:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, -TOP_INSET)
    panel:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", -2, 0)
  else
    panel:SetPoint("CENTER")
  end
  panel:SetBackdrop(BACKDROP)
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Forever Armoury: leveling gear")

  panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", 16, -36)
  panel.status:SetPoint("TOPRIGHT", -16, -36)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetJustifyV("TOP")
  panel.status:SetHeight(STATUS_HEIGHT)
  panel.status:SetWordWrap(true)

  --[[ the spec: the build's, or one chosen here; each press moves it on, and back to the build's ]]
  panel.spec = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.spec:SetSize(130, 22)
  panel.spec:SetPoint("TOPLEFT", 14, -36 - STATUS_HEIGHT - 4)
  panel.spec:SetScript("OnClick", FA.CycleGearSpec)
  panel.spec:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("The route's spec: the heaviest tree of the build you follow. Press to pick another; after the third it goes back to the build's.", 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  panel.spec:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local import = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  import:SetSize(84, 22)
  import:SetPoint("TOPRIGHT", -14, -36 - STATUS_HEIGHT - 4)
  import:SetText("Import")
  import:SetScript("OnClick", function() FA.OpenImport() end)

  panel.rows = {}
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) FA.ScrollGear(delta > 0 and -1 or 1) end)
  panel:SetScript("OnSizeChanged", function(_, _, height)
    if type(height) ~= "number" then height = heightOf() end
    if rowsFit(height) ~= panel.fit then panel.fit = rowsFit(height); FA.DrawGear() end
  end)
  panel.fit = rowsFit(heightOf())
end

--[[ The spec button: from the build's spec to the first tree, then the next, and after the third back to the build's. ]]
function FA.CycleGearSpec()
  local spec, how = Gear.Spec()
  if how == "chosen" then Gear.SetSpec(spec < 2 and spec + 1 or nil) else Gear.SetSpec(0) end
  FA.RefreshGear()
end

--[[ A row for a piece: its slot, the game's link, what to do about it, and where it's from. ]]
local function fillRow(row, piece, state, dim)
  row.piece = piece
  local link, loaded = itemLink(piece.id)
  row.link = loaded and link or false
  row.slot:SetText(SLOT_NAMES[piece.slot] or piece.slot)
  row.item:SetText(link)
  row.item:SetAlpha(dim and 0.6 or 1)
  row.state:SetText(state)
  row.from:SetText(Gear.SourceText(piece))
  row:Show()
end

--[[ The pieces from offset on, in the rows that fit; the first row says (with the ellipsis) that pieces lie above it, and the
     last that N lie below. The offset is kept in range. A row that stays is not hidden and shown again, so a tooltip over it
     stays; the rows past the fit are hidden, and rows are made as the fit first needs them. ]]
function FA.DrawGear()
  if not panel then return end
  local fit = panel.fit
  offset = math.max(0, math.min(offset, #entries - fit))
  for i = 1, math.min(fit, #entries - offset) do
    local e = entries[offset + i]
    if e then
      panel.rows[i] = panel.rows[i] or makeRow(i)
      local row = panel.rows[i]
      fillRow(row, e[1], e[2], e[3])
      local below = #entries - (offset + fit)
      row.mark:SetText(i == fit and below > 0 and (MORE .. " " .. below .. " more") or (i == 1 and offset > 0 and MORE or ""))
    end
  end
  for i = (math.min(#entries - offset, fit)) + 1, #panel.rows do
    local row = panel.rows[i]
    row.piece = false
    row:Hide()
  end
end

--[[ The list moved by some pieces, up (negative) or down, as far as it goes. ]]
function FA.ScrollGear(by)
  if not panel then return end
  local before = offset
  offset = math.max(0, math.min(offset + by, #entries - panel.fit))
  if offset == before then return end
  FA.DrawGear()
  if hovered and hovered:IsShown() then showTooltip(hovered) end   -- the cursor is over another piece now
end

function FA.RefreshGear()
  if not panel then return end
  local window = CharacterFrame
  FA.SyncWindowButton("gear")
  if not FA.PanelWanted("gear") or (window and not window:IsShown()) then panel:Hide(); return end
  panel:Show()
  panel:SetHeight(heightOf())   -- the anchors decide it in the game; this is for a client that hasn't laid them out yet
  local ok, own = pcall(function() return panel:GetHeight() end)
  panel.fit = rowsFit(ok and type(own) == "number" and own > 0 and own or heightOf())   -- the panel's own height first: what the anchors made of it
  entries = {}
  local spec, how = Gear.Spec()
  if spec ~= nil then
    panel.spec:SetText((how == "chosen" and "Spec: " or "Build: ") .. Gear.SpecName(spec))
  else
    panel.spec:SetText("Pick a spec")
  end
  local route, from = Gear.Route()
  if not route then panel.status:SetText(from); FA.DrawGear(); return end
  local level = UnitLevel("player") or 1
  local plan = Gear.Plan(route, level)
  local side = route.side:sub(1, 1):upper() .. route.side:sub(2)
  local lines = { Gear.SpecName(route.spec) .. ", " .. side .. ", level " .. level .. ": " .. plan.had .. " of " .. plan.worn ..
    (plan.worn == 1 and " piece" or " pieces") .. " of your level had.",
    from == "pasted" and "Route from the site." or "Route shipped with the addon." }
  if #plan.get == 0 and #plan.coming == 0 then lines[#lines + 1] = "Every piece of the route is yours."
  elseif #plan.get == 0 then lines[#lines + 1] = "Nothing to get at this level. Coming next:"
  else lines[#lines + 1] = "To get now, then what's coming:" end
  panel.status:SetText(table.concat(lines, "\n"))
  for _, p in ipairs(plan.get) do entries[#entries + 1] = { p, "|cffff8080get|r", false } end
  for _, p in ipairs(plan.coming) do entries[#entries + 1] = { p, "at " .. p.level, true } end
  FA.DrawGear()
end

--[[ The panel on the character window, redrawn as it shows and hides and as the character's gear, bags and level
     change, and as the game loads the names it was asked for. ]]
function FA.HookCharacterFrame()
  if hooked then return end
  hooked = true
  makePanel()
  if CharacterFrame then
    FA.WindowButton("gear", CharacterFrame)
    CharacterFrame:HookScript("OnShow", FA.RefreshGear)
    CharacterFrame:HookScript("OnHide", FA.RefreshGear)
  end
  hookComparison()
  events = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "QUEST_DATA_LOAD_RESULT" }) do
    pcall(events.RegisterEvent, events, e)
  end
  events:SetScript("OnEvent", function() if panel and panel:IsShown() then FA.RefreshGear() end end)
  FA.RefreshGear()
end

--[[ /fa gear: the character window, with the panel beside it. A panel that was put away comes back: on the window that is
     open, or with the window as it opens. ]]
function FA.ToggleGear()
  if not FA.PanelShown("gear") then
    if CharacterFrame and CharacterFrame:IsShown() then FA.SetPanelShown("gear", true); return end
    FA.db.shown.gear = true
  end
  if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
  FA.RefreshGear()
end
