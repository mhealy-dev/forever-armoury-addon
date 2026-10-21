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
local ROWS, ROW_HEIGHT = 12, 32
local STATUS_HEIGHT = 52   -- the status text's four lines of small type
local ROWS_TOP = 122      -- under the status and the buttons
local SLOT_NAMES = { head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist", hands = "Hands",
  waist = "Waist", legs = "Legs", feet = "Feet", finger1 = "Ring", finger2 = "Ring", trinket1 = "Trinket", trinket2 = "Trinket",
  mainhand = "Main hand", offhand = "Off hand", ranged = "Ranged" }
local panel, hooked, events

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
     tooltip instead. The game places them while it draws the item, before our Show(), and again as they show, so this runs
     on their OnShow and after Show(). A client that won't give a position, or errors on it, keeps the game's placement. ]]
local function overPanel(tip)
  local ok, covers = pcall(function()
    local left, edge = tip:GetLeft(), panel:GetRight()
    return type(left) == "number" and type(edge) == "number" and left < edge - 1
  end)
  return ok and covers
end

local function stackComparison()
  local first, second = ShoppingTooltip1, ShoppingTooltip2
  if not (hovered and first and first:IsShown()) and not (hovered and second and second:IsShown()) then return end
  if GameTooltip.IsOwned and not GameTooltip:IsOwned(hovered) then return end
  if not (first and first:IsShown() and overPanel(first)) and not (second and second:IsShown() and overPanel(second)) then return end
  if first then
    first:ClearAllPoints()
    first:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -4)
  end
  if first and second and second:IsShown() then
    second:ClearAllPoints()
    second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, 0)
  end
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

local function makePanel()
  local window = CharacterFrame or UIParent
  panel = CreateFrame("Frame", "ForeverArmouryGearPanel", window, TEMPLATE)
  panel:SetSize(300, ROWS_TOP + ROWS * ROW_HEIGHT + 20)
  if CharacterFrame then panel:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, -12) else panel:SetPoint("CENTER") end
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
  for i = 1, ROWS do
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
    row.from:SetPoint("BOTTOMRIGHT", -4, 2)
    row.from:SetJustifyH("LEFT")
    row.from:SetWordWrap(false)
    row.from:SetTextColor(0.7, 0.7, 0.7)
    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", hideTooltip)
    row:SetScript("OnHide", function(self) if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then hideTooltip() end end)
    row:SetScript("OnClick", clickRow)
    panel.rows[i] = row
  end
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

--[[ Hides the rows after the first n: a row that stays is not hidden and shown again, so a tooltip over it stays. ]]
local function hideRowsAfter(n)
  for i = n + 1, ROWS do panel.rows[i]:Hide() end
end

function FA.RefreshGear()
  if not panel then return end
  local window = CharacterFrame
  if not FA.PartOn("gear") or (window and not window:IsShown()) then panel:Hide(); return end
  panel:Show()
  for _, row in ipairs(panel.rows) do row.piece = false end
  local spec, how = Gear.Spec()
  if spec ~= nil then
    panel.spec:SetText((how == "chosen" and "Spec: " or "Build: ") .. Gear.SpecName(spec))
  else
    panel.spec:SetText("Pick a spec")
  end
  local route, from = Gear.Route()
  if not route then panel.status:SetText(from); hideRowsAfter(0); return end
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
  local n = 0
  for _, p in ipairs(plan.get) do
    n = n + 1
    if n > ROWS then break end
    fillRow(panel.rows[n], p, "|cffff8080get|r", false)
  end
  for _, p in ipairs(plan.coming) do
    n = n + 1
    if n > ROWS then break end
    fillRow(panel.rows[n], p, "at " .. p.level, true)
  end
  hideRowsAfter(n)
end

--[[ The panel on the character window, redrawn as it shows and hides and as the character's gear, bags and level
     change, and as the game loads the names it was asked for. ]]
function FA.HookCharacterFrame()
  if hooked then return end
  hooked = true
  makePanel()
  if CharacterFrame then
    CharacterFrame:HookScript("OnShow", FA.RefreshGear)
    CharacterFrame:HookScript("OnHide", FA.RefreshGear)
  end
  if ShoppingTooltip1 then ShoppingTooltip1:HookScript("OnShow", stackComparison) end
  if ShoppingTooltip2 then ShoppingTooltip2:HookScript("OnShow", stackComparison) end
  events = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "QUEST_DATA_LOAD_RESULT" }) do
    pcall(events.RegisterEvent, events, e)
  end
  events:SetScript("OnEvent", function() if panel and panel:IsShown() then FA.RefreshGear() end end)
  FA.RefreshGear()
end

--[[ /fa gear: the character window, with the panel beside it. ]]
function FA.ToggleGear()
  if ToggleCharacter then ToggleCharacter("PaperDollFrame") end
  FA.RefreshGear()
end
