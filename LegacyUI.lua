--[[ The Legacy part's panel: beside the game's Legacy window (LegacySystemFrame, Blizzard_LegacySystem, which loads on
     demand), the account's Legacy plans, the plan it follows with each perk's ranks had and wanted, the points available
     against the seasonal cap, and an Apply that buys what's next. Legacy.lua says what that is and does the buying; the
     next perk of each tree is lit in the window's tree with the talent window's glow (TalentUI.lua's FA.LightButtons),
     and only when the tree shows its button: the window shows one tree at a time. The panel sits past the window's side
     tabs, which are how the person gets to the trees page. ]]

local _, FA = ...
local Legacy = FA.Legacy

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local WIDTH = 230
local PLAN_ROWS, PERK_ROWS = 5, 12   -- plans shown at once (the list scrolls past them), perks shown (the rest are counted)
local PLAN_Y, PERK_H = 160, 16
local TAB_WIDTH = 40   -- the Legacy window's side tabs, when the game won't say how wide they are
local GREEN, GOLD, GREY, RED = "|cff40ff40", "|cffffd100", "|cff909090", "|cffff6060"
local TREE_PAGE = 3   -- LegacySystemFrame.Pages: the reward track, the challenges, then the trees
local panel, hooked
local offset = 0      -- how many plans are scrolled off the top of the list
local glows = {}      -- perk button -> its highlight

local function place(frame, x, y)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
end

local function makePanel()
  local window = _G.LegacySystemFrame or UIParent
  panel = CreateFrame("Frame", "ForeverArmouryLegacyPanel", window, TEMPLATE)
  panel:SetSize(WIDTH, 460)
  --[[ the window's side tabs (the reward track, the challenges and the trees) hang off its right edge from y = -60
       down, so the panel starts past them: the width of one, read now, else about 40 ]]
  local tab = window ~= UIParent and window.LegacyRewardTrackTab
  local tabWidth = type(tab) == "table" and tab.GetWidth and tonumber(tab:GetWidth()) or 0
  if tabWidth <= 0 then tabWidth = TAB_WIDTH end
  if window == UIParent then panel:SetPoint("CENTER") else panel:SetPoint("TOPLEFT", window, "TOPRIGHT", tabWidth, -20) end
  panel:SetBackdrop(BACKDROP)
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Forever Armoury: Legacy")

  panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", 16, -36)
  panel.status:SetPoint("TOPRIGHT", -16, -36)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetJustifyV("TOP")
  panel.status:SetHeight(70)
  panel.status:SetWordWrap(true)

  panel.apply = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.apply:SetSize(WIDTH - 32, 22)
  panel.apply:SetPoint("TOP", 0, -112)
  panel.apply:SetText("Apply")
  panel.apply:SetScript("OnClick", function() FA.AskApplyLegacy() end)
  panel.apply:SetScript("OnEnter", function(self)
    if not self.why then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.why, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  panel.apply:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.apply:SetMotionScriptsWhileDisabled(true)

  panel.plansHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.plansHeader:SetJustifyH("LEFT")
  place(panel.plansHeader, 16, 142)

  panel.rows = {}
  for i = 1, PLAN_ROWS do
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(WIDTH - 58, 20)
    place(row, 16, PLAN_Y + (i - 1) * 21)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:GetHighlightTexture():SetBlendMode("ADD")
    row.mark = row:CreateTexture(nil, "BACKGROUND")
    row.mark:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.mark:SetBlendMode("ADD")
    row.mark:SetAllPoints(row)
    row:SetScript("OnClick", function(self)
      if not self.plan then return end
      if FA.db.legacyFollow == self.plan.id then Legacy.SetActive(nil) else Legacy.SetActive(self.plan.id) end
      FA.RefreshLegacy()
    end)
    row.forget = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.forget:SetSize(20, 20)
    row.forget:SetPoint("LEFT", row, "RIGHT", 0, 0)
    row.forget:SetScript("OnClick", function(self)
      local p = self:GetParent().plan
      if p then StaticPopup_Show("FOREVERARMOURY_FORGET_LEGACY", FA.ShownName(p), nil, { id = p.id }) end
    end)
    panel.rows[i] = row
  end

  --[[ More plans than rows: an arrow pair under the list (and the mouse wheel over the panel) moves it. ]]
  panel.up = CreateFrame("Button", nil, panel, "UIPanelScrollUpButtonTemplate")
  panel.up:SetSize(18, 18)
  panel.up:SetScript("OnClick", function() FA.ScrollLegacy(-PLAN_ROWS + 1) end)
  panel.down = CreateFrame("Button", nil, panel, "UIPanelScrollDownButtonTemplate")
  panel.down:SetSize(18, 18)
  panel.down:SetPoint("LEFT", panel.up, "RIGHT", 2, 0)
  panel.down:SetScript("OnClick", function() FA.ScrollLegacy(PLAN_ROWS - 1) end)
  panel.more = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.more:SetPoint("LEFT", panel.down, "RIGHT", 6, 0)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) FA.ScrollLegacy(delta > 0 and -1 or 1) end)

  panel.perksHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.perksHeader:SetJustifyH("LEFT")
  panel.perks = {}
  for i = 1, PERK_ROWS + 1 do   -- the last one says how many more
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(WIDTH - 32, PERK_H)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetPoint("RIGHT", -44, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.ranks = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.ranks:SetPoint("RIGHT", -4, 0)
    row.ranks:SetJustifyH("RIGHT")
    panel.perks[i] = row
  end

  local import = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  import:SetSize(92, 22)
  import:SetPoint("BOTTOMLEFT", 14, 14)
  import:SetText("Import")
  import:SetScript("OnClick", function() FA.OpenImport() end)
  local export = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  export:SetSize(92, 22)
  export:SetPoint("BOTTOMRIGHT", -14, 14)
  export:SetText("Export")
  export:SetScript("OnClick", function()
    local code = Legacy.Export()
    if code then FA.OpenImport(code, "Every Legacy plan. Ctrl+C copies it; paste it into the site's Legacy tab Import box.")
    else FA.Print("No Legacy plans yet. Import to paste some in.") end
  end)
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["FOREVERARMOURY_FORGET_LEGACY"] = {
  text = "Forget the Legacy plan %s on this account?", button1 = YES or "Yes", button2 = NO or "No",
  OnAccept = function(self, data) if data then Legacy.Forget(data.id); FA.RefreshLegacy() end end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["FOREVERARMOURY_LEGACY_APPLY"] = {
  text = "%s", button1 = "Buy", button2 = CANCEL or "Cancel",
  OnAccept = function(self, data)
    local plan = data and Legacy.Find(data.id)
    if not plan then return end
    local ok, said = FA.ApplyLegacy(plan)
    FA.Print(ok and ("Bought as " .. FA.ShownName(plan) .. " says: " .. said .. ".") or said)
    FA.RefreshLegacy()
  end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

--[[ Apply: one confirm naming what it buys, then the perks, tree by tree, all or none in each (FA.ApplyLegacy). ]]
function FA.AskApplyLegacy()
  local plan = Legacy.Active()
  if not plan then FA.Print("Pick a Legacy plan to follow first."); return end
  local list, why = Legacy.Plan(plan)
  if not list then FA.Print(why); return end
  StaticPopup_Show("FOREVERARMOURY_LEGACY_APPLY", "Buy " .. #list .. (#list == 1 and " Legacy rank" or " Legacy ranks") .. " as " ..
    FA.ShownName(plan) .. " says?\n\n" .. Legacy.Summary(list, 8), nil, { id = plan.id })
end

--[[ The list moved by some plans, up (negative) or down, as far as it goes. ]]
function FA.ScrollLegacy(by)
  offset = math.max(0, math.min(offset + by, #Legacy.Plans() - PLAN_ROWS))
  FA.RefreshLegacy()
end

--[[ What the panel says: the plan followed, the points, and the next perk or why there isn't one. ]]
local function statusText(plan, p, why, available, cap)
  local lines = {}
  lines[#lines + 1] = plan and ("Following " .. GOLD .. FA.ShownName(plan) .. "|r.") or "Pick a plan to follow. Its next perk lights up in the tree."
  local spent = p and p.spent
  lines[#lines + 1] = "Legacy points: " .. (available ~= nil and (available .. " available") or "not told by the game") ..
    (spent and (", " .. spent .. " of " .. (cap or Legacy.CAP) .. " spent") or (", cap " .. (cap or Legacy.CAP))) .. "."
  if plan then
    if not p then lines[#lines + 1] = RED .. why .. "|r"
    elseif p.steps[1] then
      local s = p.steps[1]
      lines[#lines + 1] = "Next: " .. GOLD .. s.name .. "|r " .. s.rank .. "/" .. s.max .. " (" .. s.tree.name .. ")."
    elseif p.blocked[1] then
      lines[#lines + 1] = RED .. Legacy.PERKS[p.blocked[1].perk].name .. " can't be bought: " .. p.blocked[1].why .. ".|r"
    else
      lines[#lines + 1] = "Every rank of this plan is bought."
    end
    if p and p.over > 0 then lines[#lines + 1] = GREY .. p.over .. (p.over == 1 and " rank isn't" or " ranks aren't") .. " in this plan; Apply never takes points back.|r" end
  end
  return table.concat(lines, "\n")
end

--[[ A perk's row: name left, ranks had/wanted right, coloured by where it stands. p is Progress's answer, nil for a
     plan that can't be followed (then only the ranks wanted show). ]]
local function perkRow(row, i, plan, p, nextPerk)
  local perk = Legacy.PERKS[i]
  local want = math.min(tonumber(plan.ranks:sub(i, i), 36) or 0, perk.max)
  local color, ranks = GREY, tostring(want)
  if p then
    local have = p.perks[i].have
    ranks = have .. "/" .. want
    if have >= want then color = GREEN elseif i == nextPerk then color = GOLD else color = "|cffffffff" end
    for _, b in ipairs(p.blocked) do if b.perk == i then color = RED end end
  end
  row.name:SetText(color .. perk.name .. "|r")
  row.ranks:SetText(color .. ranks .. "|r")
end

function FA.RefreshLegacy()
  if not panel then return end
  local f = _G.LegacySystemFrame
  if not FA.PartOn("legacy") or (f and not f:IsShown()) then
    panel:Hide()
    FA.LightButtons(glows, {})
    return
  end
  panel:Show()
  local list, active = Legacy.Plans(), Legacy.Active()
  offset = math.max(0, math.min(offset, #list - PLAN_ROWS))
  local shown = math.min(#list, PLAN_ROWS)
  panel.plansHeader:SetText("Plans (" .. #list .. ")")
  for i, row in ipairs(panel.rows) do
    local plan = list[i + offset]
    row.plan = plan
    if plan then
      row.text:SetText((Legacy.Differs(plan) and (RED .. "! |r") or "") .. FA.ShownName(plan))
      row.mark:SetShown(active == plan)
      row:Show()
    else
      row:Hide()
    end
  end
  local y = PLAN_Y + shown * 21 + 4
  if #list > PLAN_ROWS then
    place(panel.up, 16, y)
    panel.up:Show(); panel.down:Show(); panel.more:Show()
    if offset > 0 then panel.up:Enable() else panel.up:Disable() end
    if offset < #list - PLAN_ROWS then panel.down:Enable() else panel.down:Disable() end
    panel.more:SetText((offset + 1) .. "-" .. (offset + PLAN_ROWS) .. " of " .. #list)
    y = y + 22
  else
    panel.up:Hide(); panel.down:Hide(); panel.more:Hide()
  end

  local available, cap = Legacy.Points()
  local p, why
  if active then p, why = Legacy.Progress(active) end
  panel.status:SetText(statusText(active, p, why, available, cap))

  --[[ Apply says how many ranks it would buy, or why it can't, before it's pressed. ]]
  local steps, held
  if not active then why = "Pick a plan to follow first."
  else steps, why, held = Legacy.Plan(active) end   -- why is the progress when there are steps, and unused then
  if steps then
    panel.apply:Enable()
    panel.apply:SetText("Apply " .. #steps .. (#steps == 1 and " rank" or " ranks"))
    panel.apply.why = Legacy.Summary(steps, 8) .. (held > 0 and ("\n" .. held .. " more when you have the points.") or "")
  else
    panel.apply:Disable(); panel.apply:SetText("Apply"); panel.apply.why = why
  end

  --[[ The followed plan's perks, those it wants, in the order of the trees; the next perk of each tree is lit. ]]
  local rows, wanted = {}, 0
  local nextPerk = p and p.steps[1] and p.steps[1].perk
  if active then
    for i = 1, #Legacy.PERKS do
      if (tonumber(active.ranks:sub(i, i), 36) or 0) > 0 then rows[#rows + 1] = i end
    end
  end
  panel.perksHeader:SetText(active and "Perks" or "")
  place(panel.perksHeader, 16, y + 4)
  y = y + 24
  for r, row in ipairs(panel.perks) do
    local i = rows[r]
    if i and r <= PERK_ROWS then
      perkRow(row, i, active, p, nextPerk)
      place(row, 16, y + (r - 1) * PERK_H)
      row:Show()
    elseif r == PERK_ROWS + 1 and #rows > PERK_ROWS then
      row.name:SetText(GREY .. "and " .. (#rows - PERK_ROWS) .. " more|r")
      row.ranks:SetText("")
      place(row, 16, y + (r - 1) * PERK_H)
      row:Show()
    else
      row:Hide()
    end
  end
  y = y + math.min(#rows, PERK_ROWS + (#rows > PERK_ROWS and 1 or 0)) * PERK_H
  panel:SetHeight(y + 50)

  local buttons, seen = {}, {}
  for _, s in ipairs(p and p.steps or {}) do
    if not seen[s.tree] then
      seen[s.tree] = true
      local button = Legacy.Button(s)
      if button then buttons[#buttons + 1] = button end
    end
  end
  FA.LightButtons(glows, buttons, nil, nil, nil, true)
end

--[[ Once Blizzard's Legacy UI is in: the panel on its window, and a refresh whenever it shows, hides or redraws its
     tree. The window shows one tree at a time, so a new tree's buttons are looked for again as it picks them. ]]
function FA.HookLegacyFrame()
  if hooked then return end
  local f = _G.LegacySystemFrame
  if not f then return end
  hooked = true
  makePanel()
  f:HookScript("OnShow", FA.RefreshLegacy)
  f:HookScript("OnHide", FA.RefreshLegacy)
  if EventRegistry and EventRegistry.RegisterCallback then
    for _, name in ipairs({ "Legacy.SelectTree", "TalentFrameBase.ButtonsUpdated", "TalentFrameBase.ConfigUpdated" }) do
      EventRegistry:RegisterCallback(name, FA.RefreshSoon, panel)
    end
  end
  FA.RefreshLegacy()
end

--[[ /fa legacy: the game's Legacy window, on its trees, with the panel beside it. The game opens it only once the
     Legacy track has begun, and has no opener for it besides ToggleLegacySystemUI (Blizzard_LegacySystem's bootstrap,
     which loads the window). ]]
function FA.ToggleLegacy()
  local was = _G.LegacySystemFrame and _G.LegacySystemFrame:IsShown()
  if type(ToggleLegacySystemUI) == "function" then ToggleLegacySystemUI()
  elseif _G.LegacySystemFrame then ToggleFrame(_G.LegacySystemFrame)
  else FA.Print("This client has no Legacy window to open."); return end
  local f = _G.LegacySystemFrame
  if not f or (not was and not f:IsShown()) then
    FA.Print("The game didn't open the Legacy window. It opens once the Legacy track has begun.")
    return
  end
  if not was and f:IsShown() and EventRegistry and EventRegistry.TriggerEvent then
    pcall(EventRegistry.TriggerEvent, EventRegistry, "Legacy.SelectPage", TREE_PAGE)
  end
  FA.RefreshLegacy()
end
