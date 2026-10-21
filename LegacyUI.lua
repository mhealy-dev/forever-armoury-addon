--[[ The Legacy part's windows: beside the game's Legacy window (LegacySystemFrame, Blizzard_LegacySystem, which loads on
     demand), a strip of icons showing the followed plan's ranks in the order Apply buys them (the ranks the account has,
     the next, the ones coming), as the talent window's strip does for a build (Strip.lua draws both; the plan's side of
     it is here), and a panel beside that with the account's Legacy plans (a section that opens and closes), the plan it
     follows with each perk's ranks had and wanted, the points available against the seasonal cap, and an Apply that
     buys what's next. Legacy.lua says what that is and does the buying; the next perk of each tree is lit in the
     window's tree with the talent window's glow (Strip.lua's FA.LightButtons), and only when the tree shows its button:
     the window shows one tree at a time. The strip and the panel hang on the window's right edge under its side tabs,
     which are how the person gets to the trees page. ]]

local _, FA = ...
local Legacy = FA.Legacy

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local WIDTH, HEIGHT = 230, 460   -- the panel's; the strip runs from under the tabs to the window's bottom
local PLAN_ROWS, PERK_ROWS = 5, 12   -- plans shown at once (the list scrolls past them), perks shown (the rest are counted)
local PLAN_Y, PERK_H = 160, 16
local HEADER_Y = 140   -- the plans section's header row, above its list
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"
local TABS_BOTTOM = 284   -- how far below the Legacy window's top its side tabs end, when there is no tab to hang under (measured in the beta)
local GREEN, GOLD, GREY, RED = "|cff40ff40", "|cffffd100", "|cff909090", "|cffff6060"
local panel, strip, window, hooked
local panelBy         -- what the panel is anchored to: the strip, or the window when there is no strip
local offset = 0      -- how many plans are scrolled off the top of the list
local glows = {}      -- perk button -> its highlight
local followed, progress, sequence, nowOk   -- the strip's: the plan, where the account is on it, its ranks in order, and whether a point can be spent now

local function place(frame, x, y)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
end

--[[ What the strip and the panel hang under: the window's lowest side tab (the reward track, the challenges and the
     trees hang off its right edge, the trees tab lowest), so the game keeps them lined up at any scale and the tabs
     stay clickable; without the tab, a number of pixels below the window's top, as measured in the beta. ]]
local function underTabs()
  local tab = window ~= UIParent and window.LegacyTreeTab
  if type(tab) == "table" and tab.GetBottom then return tab end
  return TABS_BOTTOM
end

--[[ ---- the strip of icons beside the Legacy window ---- ]]
--[[ Buys the plan's next ranks (the first `limit` of them, else all Apply would): tree by tree, all or none in each
     (FA.ApplyLegacy), then a line in chat and a redraw. The confirm's Buy and the strip's click both come here. ]]
local function buy(plan, limit)
  local ok, said = FA.ApplyLegacy(plan, limit)
  FA.StripFollow()   -- the strip shows the next rank again, wherever it was scrolled
  FA.Print(ok and ("Bought as " .. FA.ShownName(plan) .. " says: " .. said .. ".") or said)
  FA.RefreshLegacy()
end

--[[ A rank of the plan's order as the strip draws it: the perk's name and icon as the game's trait definition gives them
     (through the tree's config), else the site's (the perk's table row); the r/m; "Now" or "wait" under the next one
     and the tree's short name on a coming one. ]]
local function entry(x, n)
  local s = x.step
  local perk = Legacy.PERKS[s.perk]
  local configID = Legacy.Config(s.tree)
  local info = configID and FA.Talents.Game("C_Traits.GetNodeInfo", configID, perk.node)
  local name, icon, spell
  if info then name, icon, spell = FA.Talents.NodeNameAndIcon(configID, info) end
  return { kind = x.kind, n = n, perk = s.perk, rank = s.rank, max = s.max, node = s.node, tree = s.tree, step = s, spell = spell,
    name = name or perk.name, icon = icon or ("Interface\\Icons\\" .. perk.icon), ranks = FA.Strip.RankText(s.rank, s.max),
    label = x.kind == "next" and (nowOk and "Now" or "wait") or nil, badge = x.kind == "coming" and s.tree.short or nil }
end

--[[ The plan's ranks in the order to buy them, as kind and step: those the account has (the order Apply would have bought
     them in, from nothing), the next rank to buy, and the ones after it (Progress's steps). Nothing without a plan that
     can be followed. ]]
local function orderOf(plan, p)
  local list = {}
  if not (plan and p) then return list end
  for _, s in ipairs(Legacy.Order(plan)) do
    local perk = p.perks[s.perk]
    if s.rank <= math.min(perk.have, perk.want) then list[#list + 1] = { kind = "taken", step = s } end
  end
  for i, s in ipairs(p.steps) do list[#list + 1] = { kind = i == 1 and "next" or "coming", step = s } end
  return list
end

--[[ The plan's side of the strip: the ranks from where the view is, the perk's button in the tree on show for hover, the
     game's tooltip for the perk, and the click, which buys the next rank the way Apply does (switching the window to its
     tree first when another is on show), and the shift-click, which is Apply. ]]
local owner = {
  name = "ForeverArmouryLegacyStrip",
  verb = "buy",
  anchor = function() return window, -2, underTabs() end,
  refreshKey = function() return tostring(followed and followed.id) .. ":" .. (progress and progress.spent or "") end,
  button = function(e) return Legacy.Button(e) end,
}

function owner.plan(from, count)
  local total, nextAt = #sequence, nil
  for i, x in ipairs(sequence) do if x.kind == "next" then nextAt = i end end
  from = math.max(0, math.min(math.floor(from or 0), total - count))
  local out = {}
  for i = from + 1, math.min(total, from + count) do out[#out + 1] = entry(sequence[i], i) end
  return out, from, total - from - #out, nextAt, total
end

function owner.tooltip(e, tip)
  if e.spell then tip:SetSpellByID(e.spell) else tip:SetText(e.name, 1, 1, 1) end
  tip:AddLine("Rank " .. e.rank .. " of " .. e.max, 1, 0.82, 0)
  if e.kind == "taken" then tip:AddLine("Taken", 0.3, 1, 0.3) end
  if not Legacy.TreeShown(e.tree) then tip:AddLine("In the " .. e.tree.name .. " tree", 0.6, 0.8, 1) end
end

--[[ What a click on a strip icon can do now: how many ranks Apply would buy, or nil and why not (nil and nil for an icon
     that isn't the next one, which has no click). The reasons are Apply's own, and that the next rank is in a tree the
     window shows no button for and an addon can't switch to. ]]
function owner.can(e)
  local plan = Legacy.Active()
  if e.kind ~= "next" or not plan then return nil end
  if Legacy.Applying() then return nil, "That rank is being bought." end
  local list, why = Legacy.Plan(plan)
  if not list then return nil, why end
  if not Legacy.TreeShown(e.tree) and not Legacy.CanShowTree() then
    return nil, "Open the " .. e.tree.name .. " tab in the Legacy window to buy it."
  end
  return #list
end

function owner.spend()
  local plan = Legacy.Active()
  local list = plan and Legacy.Plan(plan)
  if not list then return end
  if not Legacy.TreeShown(list[1].tree) then Legacy.ShowTree(list[1].tree) end
  buy(plan, 1)
end
function owner.spendAll() FA.AskApplyLegacy() end

--[[ The panel sits against the strip while there is one to show, else against the window under its side tabs. ]]
local function anchorPanel(by)
  if panelBy == by then return end
  panelBy = by
  panel:ClearAllPoints()
  local under = underTabs()
  if window == UIParent then panel:SetPoint("CENTER")
  elseif by ~= window then panel:SetPoint("TOPLEFT", by, "TOPRIGHT", -2, 0)
  elseif type(under) == "table" then panel:SetPoint("TOPLEFT", under, "BOTTOMLEFT", -2, -4)
  else panel:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, -under) end
end

--[[ The strip for the followed plan and where the account is on it (Progress's answer, nil without a plan that can be
     followed), with whether a Legacy point can be spent now: one is available and the cap isn't reached. ]]
local function refreshStrip(plan, p, available, cap)
  if not strip then return end
  followed, progress = plan, p
  nowOk = p ~= nil and (available == nil or available > 0) and p.spent < (cap or Legacy.CAP)
  sequence = orderOf(plan, p)
  anchorPanel(strip:Refresh() and strip.frame or window)
end

--[[ Whether the plans list is open: as the account left it, else open until it follows a plan. ]]
local function plansOpen(active)
  local open = FA.db.legacyPlansOpen
  if type(open) ~= "boolean" then return active == nil end
  return open
end

local function makePanel()
  window = _G.LegacySystemFrame or UIParent
  sequence = {}
  if window ~= UIParent then strip = FA.Strip.New(owner) end
  panel = CreateFrame("Frame", "ForeverArmouryLegacyPanel", window, TEMPLATE)
  panel:SetSize(WIDTH, HEIGHT)
  anchorPanel(window)
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

  --[[ The plans are a section: a header row that opens and closes the list, and says which plan is followed when it's closed. ]]
  local header = CreateFrame("Button", nil, panel)
  header:SetSize(WIDTH - 32, 20)
  place(header, 16, HEADER_Y)
  header:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  header:GetHighlightTexture():SetBlendMode("ADD")
  header.sign = header:CreateTexture(nil, "ARTWORK")
  header.sign:SetSize(14, 14)
  header.sign:SetPoint("LEFT", 4, 0)
  header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header.text:SetPoint("LEFT", 24, 0)
  header.text:SetPoint("RIGHT", -4, 0)
  header.text:SetJustifyH("LEFT")
  header.text:SetWordWrap(false)
  header:SetScript("OnClick", function()
    FA.db.legacyPlansOpen = not plansOpen(Legacy.Active())
    FA.RefreshLegacy()
  end)
  panel.plansHeader = header

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
    buy(plan)
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
  FA.SyncWindowButton("legacy")
  if not FA.PanelWanted("legacy") or (f and not f:IsShown()) then
    panel:Hide()
    if strip then strip:Hide() end
    FA.LightButtons(glows, {})
    return
  end
  panel:Show()
  local list, active = Legacy.Plans(), Legacy.Active()
  offset = math.max(0, math.min(offset, #list - PLAN_ROWS))
  --[[ The plans section: its header, then the list when it's open; the panel is as tall as what it shows. ]]
  local open = plansOpen(active)
  local shown = open and math.min(#list, PLAN_ROWS) or 0
  panel.plansHeader.sign:SetTexture(open and MINUS or PLUS)
  panel.plansHeader.text:SetText((not open and active) and FA.ShownName(active) or ("Plans (" .. #list .. ")"))
  for i, row in ipairs(panel.rows) do
    local plan = open and list[i + offset] or nil
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
  if open and #list > PLAN_ROWS then
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
  refreshStrip(active, p, available, cap)

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
  FA.WindowButton("legacy", f)
  f:HookScript("OnShow", FA.RefreshLegacy)
  f:HookScript("OnHide", FA.RefreshLegacy)
  if EventRegistry and EventRegistry.RegisterCallback then
    for _, name in ipairs({ "Legacy.SelectTree", "TalentFrameBase.ButtonsUpdated", "TalentFrameBase.ConfigUpdated" }) do
      EventRegistry:RegisterCallback(name, FA.RefreshSoon, panel)
    end
  end
  FA.RefreshLegacy()
end

--[[ /fa legacy: the game's Legacy window, on its trees, with the panel beside it (a panel put away comes back). The game opens it only once the
     Legacy track has begun, and has no opener for it besides ToggleLegacySystemUI (Blizzard_LegacySystem's bootstrap,
     which loads the window). ]]
function FA.ToggleLegacy()
  local was = _G.LegacySystemFrame and _G.LegacySystemFrame:IsShown()
  if not FA.PanelShown("legacy") then   -- a panel put away comes back: on the open window, or with the window as it opens
    if was then FA.SetPanelShown("legacy", true); return end
    FA.db.shown.legacy = true
  end
  if type(ToggleLegacySystemUI) == "function" then ToggleLegacySystemUI()
  elseif _G.LegacySystemFrame then ToggleFrame(_G.LegacySystemFrame)
  else FA.Print("This client has no Legacy window to open."); return end
  local f = _G.LegacySystemFrame
  if not f or (not was and not f:IsShown()) then
    FA.Print("The game didn't open the Legacy window. It opens once the Legacy track has begun.")
    return
  end
  if not was and f:IsShown() and EventRegistry and EventRegistry.TriggerEvent then
    pcall(EventRegistry.TriggerEvent, EventRegistry, "Legacy.SelectPage", Legacy.TREE_PAGE)
  end
  FA.RefreshLegacy()
end
