--[[ The leveling gear part's panel: beside the character window, the pieces of the route to go and get at this level,
     then the ones coming, each as the game's item link with where it comes from under it. Gear.lua says which pieces
     those are; the game names the items from their ids (GetItemInfo), so the addon carries no item text, and hovering a
     piece shows the game's own tooltip. ]]

local _, FA = ...
local Gear = FA.Gear

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ROWS, ROW_HEIGHT = 12, 32
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

local function makePanel()
  local window = CharacterFrame or UIParent
  panel = CreateFrame("Frame", "ForeverArmouryGearPanel", window, TEMPLATE)
  panel:SetSize(300, 110 + ROWS * ROW_HEIGHT + 20)
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
  panel.status:SetHeight(40)
  panel.status:SetWordWrap(true)

  --[[ the spec: the build's, or one chosen here; each press moves it on, and back to the build's ]]
  panel.spec = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.spec:SetSize(130, 22)
  panel.spec:SetPoint("TOPLEFT", 14, -80)
  panel.spec:SetScript("OnClick", FA.CycleGearSpec)
  panel.spec:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("The route's spec: the heaviest tree of the build you follow. Press to pick another; after the third it goes back to the build's.", 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  panel.spec:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local import = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  import:SetSize(84, 22)
  import:SetPoint("TOPRIGHT", -14, -80)
  import:SetText("Import")
  import:SetScript("OnClick", function() FA.OpenImport() end)

  panel.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(268, ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", 16, -110 - (i - 1) * ROW_HEIGHT)
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
    row:SetScript("OnEnter", function(self)
      if not self.piece then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.piece.id) else GameTooltip:SetHyperlink("item:" .. self.piece.id) end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(self.fromText or "", 0.7, 0.7, 0.7, true)
      GameTooltip:AddLine("On the route at level " .. self.piece.level .. ".", 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
      if not (self.link and IsModifiedClick and IsModifiedClick("CHATLINK")) then return end
      if ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
    end)
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
  row.link = loaded and link or nil
  row.slot:SetText(SLOT_NAMES[piece.slot] or piece.slot)
  row.item:SetText(link)
  row.item:SetAlpha(dim and 0.6 or 1)
  row.state:SetText(state)
  row.fromText = Gear.SourceText(piece)
  row.from:SetText(row.fromText)
  row:Show()
end

function FA.RefreshGear()
  if not panel then return end
  local window = CharacterFrame
  if not FA.PartOn("gear") or (window and not window:IsShown()) then panel:Hide(); return end
  panel:Show()
  for _, row in ipairs(panel.rows) do row:Hide(); row.piece = nil end
  local spec, how = Gear.Spec()
  if spec ~= nil then
    panel.spec:SetText((how == "chosen" and "Spec: " or "Build: ") .. Gear.SpecName(spec))
  else
    panel.spec:SetText("Pick a spec")
  end
  local route, why = Gear.Route()
  if not route then panel.status:SetText(why); return end
  local level = UnitLevel("player") or 1
  local plan = Gear.Plan(route, level)
  local side = route.side:sub(1, 1):upper() .. route.side:sub(2)
  local lines = { Gear.SpecName(route.spec) .. ", " .. side .. ", level " .. level .. ": " .. plan.had .. " of " .. plan.worn ..
    (plan.worn == 1 and " piece" or " pieces") .. " of your level had." }
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
