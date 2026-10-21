--[[ The level plan part's windows: a strip of icons beside the talent window showing the followed build's talents in its
     order (the last few taken, the next, the ones coming), and a panel beside that listing the character's builds, with
     the active one's next talent named and lit in the trees; the import box, where codes are pasted in and copied out;
     and the addon's settings page. Talents.lua says which frame the talent window is and which button a talent has,
     so nothing here depends on the client's version of it. ]]

local _, FA = ...
local Talents = FA.Talents

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ROWS = 10   -- builds shown at once; the list scrolls past them
local ICON = 34     -- the strip's icons
local STRIP_W = 48
local HEADER_Y, LIST_Y = 132, 156   -- where the panel's builds header and its list start
local panel, strip, window, importBox, options, hooked
local panelBy   -- what the panel is anchored to: the strip, or the window when there is no strip
local offset = 0   -- how many builds are scrolled off the top of the list
local glows = {}   -- talent button -> its highlight
local hovers = {}  -- talent button -> the highlight of the strip icon under the mouse
local hovering     -- the strip icon under the mouse

--[[ ---- the highlights in the trees ---- ]]
--[[ A frame of ours over each of a list of buttons, kept in a set by button: the client's talent frame pools and reuses
     its buttons, so nothing is written on them. Lights those that are shown and hides the rest of the set; r, g, b tint
     it. The Legacy panel lights its perks' buttons with it (FA.LightButtons). ]]
local function lightButtons(set, buttons, r, g, b, pulses)
  for _, o in pairs(set) do o.frame:Hide() end
  for _, button in ipairs(buttons) do
    if button:IsShown() then
      local o = set[button]
      if not o then
        local f = CreateFrame("Frame", nil, button)
        f:SetAllPoints(button)
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        tex:SetBlendMode("ADD")
        if r then tex:SetVertexColor(r, g, b) end
        tex:SetPoint("TOPLEFT", -4, 4)
        tex:SetPoint("BOTTOMRIGHT", 4, -4)
        o = { frame = f }
        if pulses then
          o.pulse = f:CreateAnimationGroup()
          o.pulse:SetLooping("BOUNCE")
          local a = o.pulse:CreateAnimation("Alpha")
          a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7)
        end
        set[button] = o
      end
      o.frame:SetFrameLevel(button:GetFrameLevel() + 5)   -- every time: a recycled button may have a new level, and the overlay stays above it
      o.frame:Show()
      if o.pulse then o.pulse:Play() end
    end
  end
end
FA.LightButtons = lightButtons

--[[ The talent's own button lit, the rest of the set hidden. ]]
local function lightOn(set, t, r, g, b, pulses)
  lightButtons(set, { Talents.Button(t) }, r, g, b, pulses)
end

--[[ The next talent: the game's own glow, pulsing. ]]
local function lightTalent(t) lightOn(glows, t, nil, nil, nil, true) end
--[[ The talent of the strip icon under the mouse, in blue so it reads beside the next talent's glow, which stays. ]]
local function lightHover(t) lightOn(hovers, t, 0.3, 0.7, 1) end
--[[ The strip is going away, or the window is: no icon is under the mouse any more. ]]
local function dropHover()
  if hovering then GameTooltip:Hide() end
  hovering = nil
  lightHover(nil)
end

--[[ ---- the strip of icons beside the talent window ---- ]]
--[[ The panel's border at half the weight, so a 34 px icon fits a 48 px strip. ]]
local STRIP_BACKDROP = { bgFile = BACKDROP.bgFile, edgeFile = BACKDROP.edgeFile, tile = true, tileSize = 32, edgeSize = 16,
  insets = { left = 5, right = 5, top = 5, bottom = 5 } }

--[[ Spends a build's due points (the first `count` of them, else all): the points, all or none (FA.Apply), then a line in
     chat and a redraw. The confirm's Spend and the strip's click both come here. ]]
local function spend(build, count)
  local ok, said, stopped = FA.Apply(build, count)
  FA.Print(ok and ("Spent as " .. (build.name ~= "" and FA.Esc(build.name) or "the build") .. " says: " .. said .. "." ..
    (stopped and (" It stopped at " .. FA.Where(stopped.tab, stopped.cell) .. ", a talent your trees don't have.") or "")) or said)
  FA.Refresh()
end

--[[ What a click on a strip icon can do now: the points Apply would spend, or nil and why not (nil and nil for an icon
     that isn't the next one, which has no click). The reasons are Apply's own. The icon's highlight shows only when
     the click would work. ]]
local function clickPlan(icon)
  local e = icon.entry
  local list, why
  if e and e.kind == "next" and FA.ActiveBuild() then
    local ok, combat = Talents.CanChange()
    if Talents.Applying() then why = "That point is being applied."
    elseif not ok then why = combat
    else list, why = FA.PlanApply(FA.ActiveBuild()) end
  end
  icon.highlight:SetAlpha(list and 1 or 0)
  return list, why
end

--[[ An icon's tooltip: the talent's spell as the game shows it (its name when the game gave no spell), then its level and
     rank, and whether the rank is taken; the next one ends with what a click does, or why it does nothing. ]]
local function showTip(icon)
  local e = icon.entry
  if not e then return end
  local t = e.talent
  GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
  if not t then
    GameTooltip:SetText("Not in your trees", 1, 1, 1)
    GameTooltip:AddLine(FA.Where(e.tab, e.cell), 1, 0.82, 0)
    GameTooltip:AddLine("Level " .. e.level, 1, 0.82, 0)
    GameTooltip:AddLine("The site may be newer than this addon, or the game's nodes didn't sort. Apply stops here.", 1, 0.4, 0.4, true)
    GameTooltip:Show()
    return
  end
  if t.spell then GameTooltip:SetSpellByID(t.spell) else GameTooltip:SetText(t.name or "Unknown talent", 1, 1, 1) end
  GameTooltip:AddLine("Level " .. e.level .. " \194\183 Rank " .. e.rank .. " of " .. (t.max or "?"), 1, 0.82, 0)
  if e.kind == "taken" then GameTooltip:AddLine("Taken", 0.3, 1, 0.3) end
  local list, why = clickPlan(icon)
  if list then
    GameTooltip:AddLine("Click to take it", 0.3, 1, 0.3)
    if #list > 1 then GameTooltip:AddLine("Shift-click to take all " .. #list, 0.3, 1, 0.3) end
  elseif why then
    GameTooltip:AddLine(why, 1, 0.4, 0.4, true)
  end
  GameTooltip:Show()
end

local function makeIcon()
  local icon = CreateFrame("Button", nil, strip)
  icon:SetSize(ICON, ICON)
  icon.edge = icon:CreateTexture(nil, "BACKGROUND")   -- the next one's gold border
  icon.edge:SetColorTexture(1, 0.82, 0, 1)
  icon.edge:SetPoint("TOPLEFT", -2, 2)
  icon.edge:SetPoint("BOTTOMRIGHT", 2, -2)
  icon.tex = icon:CreateTexture(nil, "ARTWORK")
  icon.tex:SetAllPoints(icon)
  icon.glow = icon:CreateTexture(nil, "OVERLAY")   -- and the glow lightTalent puts on its button
  icon.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  icon.glow:SetBlendMode("ADD")
  icon.glow:SetPoint("TOPLEFT", -4, 4)
  icon.glow:SetPoint("BOTTOMRIGHT", 4, -4)
  icon.check = icon:CreateTexture(nil, "OVERLAY")
  icon.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  icon.check:SetSize(16, 16)
  icon.check:SetPoint("TOPRIGHT", 3, 3)
  icon.rank = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  icon.rank:SetPoint("TOPLEFT", 2, -2)
  icon.rank:SetShadowOffset(1, -1)
  icon.levelBg = icon:CreateTexture(nil, "ARTWORK", nil, 2)   -- the level a coming point is due in
  icon.levelBg:SetColorTexture(0, 0, 0, 0.7)
  icon.levelBg:SetSize(18, 12)
  icon.levelBg:SetPoint("BOTTOMRIGHT")
  icon.level = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  icon.level:SetPoint("CENTER", icon.levelBg)
  icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")   -- "Now" or "L25", under the next one
  icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -1)
  icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")   -- shown on the mouse over, and only when clickPlan says a click would work
  icon.highlight = icon:GetHighlightTexture()
  icon.highlight:SetBlendMode("ADD")
  icon.highlight:SetAlpha(0)
  icon:RegisterForClicks("LeftButtonUp")
  icon:SetScript("OnEnter", function(self)
    if not self.entry then return end
    hovering = self
    lightHover(self.entry.talent)
    showTip(self)
  end)
  icon:SetScript("OnLeave", function()
    hovering = nil
    lightHover(nil)
    GameTooltip:Hide()
  end)
  --[[ The next icon takes its point: one click, and Apply's way (staged and committed together, all or none, rolled back
       and said in chat if the game refuses); shift-click is Apply for every point due, through its confirm. A click that
       can't do either does nothing, and the tooltip says why. While the commit casts the points are staged, so a second
       click finds Applying true and is ignored. ]]
  icon:SetScript("OnClick", function(self)
    local list = clickPlan(self)
    if not list then return end
    if IsShiftKeyDown() then FA.AskApply() else spend(FA.ActiveBuild(), 1) end
  end)
  return icon
end

local function makeStrip()
  strip = CreateFrame("Frame", "ForeverArmouryTalentStrip", window, TEMPLATE)
  strip:SetWidth(STRIP_W)
  strip:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, 0)
  strip:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", -2, 0)
  strip:SetBackdrop(STRIP_BACKDROP)
  strip:SetFrameStrata("HIGH")
  strip:SetClampedToScreen(true)
  strip.icons = {}
  strip.more = CreateFrame("Frame", nil, strip)   -- three dots, drawn here since the font may not have a vertical ellipsis
  strip.more:SetSize(ICON, 16)
  strip.more:EnableMouse(true)
  for i = 1, 3 do
    local dot = strip.more:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(0.8, 0.8, 0.8, 1)
    dot:SetSize(3, 3)
    dot:SetPoint("TOP", 0, -2 - (i - 1) * 5)
  end
  strip.more:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.count .. (self.count == 1 and " more point" or " more points"), 1, 1, 1)
    GameTooltip:Show()
  end)
  strip.more:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--[[ The panel sits against the strip while there is one to show, else against the window. ]]
local function anchorPanel(by)
  if panelBy == by then return end
  panelBy = by
  panel:ClearAllPoints()
  if window == UIParent then panel:SetPoint("CENTER") else panel:SetPoint("TOPLEFT", by, "TOPRIGHT", -2, -20) end
end

--[[ The strip for a build's progress (FA.Progress's answer, nil without a build to show): hidden without one, else an
     icon for each point FA.StripPlan names, top to bottom. The icon under the mouse keeps its highlight and tooltip
     through the redraw. ]]
local function refreshStrip(p)
  if not strip then return end
  local entries, more
  if p then entries, more = FA.StripPlan(p, FA.StripCount("past"), FA.StripCount("coming")) end
  if not entries or #entries == 0 then
    strip:Hide()
    anchorPanel(window)
    dropHover()
    return
  end
  strip:Show()
  anchorPanel(strip)
  local y = 12
  for i, e in ipairs(entries) do
    local icon = strip.icons[i]
    if not icon then icon = makeIcon(); strip.icons[i] = icon end
    local t = e.talent
    icon.entry = e
    icon.tex:SetTexture(Talents.Icon(t))   -- a pick off the trees has no talent: a question mark, greyed
    icon.tex:SetAlpha(e.kind == "taken" and 0.45 or e.kind == "unplaced" and 0.5 or 1)
    if icon.tex.SetDesaturated then icon.tex:SetDesaturated(e.kind == "unplaced") end
    icon.check:SetShown(e.kind == "taken")
    icon.edge:SetShown(e.kind == "next")
    icon.glow:SetShown(e.kind == "next")
    icon.rank:SetText(t and (t.max == nil or t.max > 1) and (e.rank .. "/" .. (t.max or "?")) or "")
    local levelled = e.kind == "coming" or e.kind == "unplaced"
    icon.levelBg:SetShown(levelled)
    icon.level:SetShown(levelled)
    icon.level:SetText(levelled and e.level or "")
    icon.label:SetShown(e.kind == "next")
    icon.label:SetText(e.kind == "next" and (e.now and "Now" or ("L" .. e.level)) or "")
    clickPlan(icon)
    if e.kind == "coming" and entries[i - 1].kind ~= "coming" then y = y + 8 end   -- a gap after the next one
    icon:ClearAllPoints()
    icon:SetPoint("TOP", strip, "TOP", 0, -y)
    icon:Show()
    y = y + ICON + 4 + (e.kind == "next" and 12 or 0)
  end
  for i = #entries + 1, #strip.icons do
    strip.icons[i].entry = false
    strip.icons[i]:Hide()
  end
  strip.more.count = more
  strip.more:SetShown(more > 0)
  strip.more:ClearAllPoints()
  strip.more:SetPoint("TOP", strip, "TOP", 0, -y)
  if hovering and hovering.entry then
    lightHover(hovering.entry.talent)
    showTip(hovering)
  else
    dropHover()
  end
end

--[[ ---- the panel beside the talent window ---- ]]
--[[ Whether the panel's build list is open: as the character left it, else open until it follows a build. ]]
local function buildsOpen(active)
  local open = FA.char.buildsOpen
  if open == nil then return active == nil end
  return open
end

local function makePanel()
  window = Talents.Window() or UIParent
  if window ~= UIParent then makeStrip() end
  panel = CreateFrame("Frame", "ForeverArmouryTalentPanel", window, TEMPLATE)
  panel:SetSize(210, 410)
  anchorPanel(window)
  panel:SetBackdrop(BACKDROP)
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Forever Armoury")

  panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", 16, -36)
  panel.status:SetPoint("TOPRIGHT", -16, -36)
  panel.status:SetJustifyH("LEFT")
  panel.status:SetJustifyV("TOP")
  panel.status:SetHeight(66)
  panel.status:SetWordWrap(true)

  panel.apply = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.apply:SetSize(178, 22)
  panel.apply:SetPoint("TOP", 0, -104)
  panel.apply:SetText("Apply")
  panel.apply:SetScript("OnClick", function() FA.AskApply() end)
  panel.apply:SetScript("OnEnter", function(self)
    if not self.why then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.why, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  panel.apply:SetScript("OnLeave", function() GameTooltip:Hide() end)
  panel.apply:SetMotionScriptsWhileDisabled(true)

  --[[ The builds are a section: a header row that opens and closes the list, and says which build is followed when it's closed. ]]
  local header = CreateFrame("Button", nil, panel)
  header:SetSize(178, 20)
  header:SetPoint("TOPLEFT", 16, -HEADER_Y)
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
    FA.char.buildsOpen = not buildsOpen(FA.ActiveBuild())
    FA.Refresh()
  end)
  panel.header = header

  panel.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(158, 20)
    row:SetPoint("TOPLEFT", 16, -LIST_Y - (i - 1) * 21)
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
      if not self.build then return end
      FA.SetActive(FA.char.build == self.build.id and nil or self.build.id)
      FA.Refresh()
    end)
    row.forget = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    row.forget:SetSize(20, 20)
    row.forget:SetPoint("LEFT", row, "RIGHT", 0, 0)
    row.forget:SetScript("OnClick", function(self)
      local b = self:GetParent().build
      if b then StaticPopup_Show("FOREVERARMOURY_FORGET", FA.ShownName(b), nil, { cls = FA.class, id = b.id }) end
    end)
    panel.rows[i] = row
  end

  --[[ More builds than rows: an arrow pair under the list (and the mouse wheel over the panel) moves it. ]]
  panel.up = CreateFrame("Button", nil, panel, "UIPanelScrollUpButtonTemplate")
  panel.up:SetSize(18, 18)
  panel.up:SetPoint("TOPLEFT", 16, -LIST_Y - ROWS * 21 - 4)
  panel.up:SetScript("OnClick", function() FA.ScrollBuilds(-ROWS + 1) end)
  panel.down = CreateFrame("Button", nil, panel, "UIPanelScrollDownButtonTemplate")
  panel.down:SetSize(18, 18)
  panel.down:SetPoint("LEFT", panel.up, "RIGHT", 2, 0)
  panel.down:SetScript("OnClick", function() FA.ScrollBuilds(ROWS - 1) end)
  panel.more = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.more:SetPoint("LEFT", panel.down, "RIGHT", 6, 0)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) FA.ScrollBuilds(delta > 0 and -1 or 1) end)

  local import = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  import:SetSize(84, 22)
  import:SetPoint("BOTTOMLEFT", 14, 14)
  import:SetText("Import")
  import:SetScript("OnClick", function() FA.OpenImport() end)
  local export = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  export:SetSize(84, 22)
  export:SetPoint("BOTTOMRIGHT", -14, 14)
  export:SetText("Export")
  export:SetScript("OnClick", function()
    local code = FA.ExportCode()
    if code then FA.OpenImport(code) else FA.Print("No builds for this class yet. Import to paste some in.") end
  end)
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["FOREVERARMOURY_FORGET"] = {
  text = "Forget the build %s on this account?", button1 = YES or "Yes", button2 = NO or "No",
  OnAccept = function(self, data) if data then FA.ForgetBuild(data.cls, data.id); FA.Refresh() end end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["FOREVERARMOURY_APPLY"] = {
  text = "%s", button1 = "Spend", button2 = CANCEL or "Cancel",
  OnAccept = function(self, data)
    local build = data and FA.FindBuild(FA.class, data.id)
    if build then spend(build) end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

--[[ Apply: one confirm naming what it spends, then the points, all or none (FA.Apply). ]]
function FA.AskApply()
  local build = FA.ActiveBuild()
  if not build then FA.Print("Pick a build to follow first."); return end
  local ok, why = FA.Talents.CanChange()
  local list, stopped
  if ok then
    local answer = { FA.PlanApply(build) }
    list, why, stopped = answer[1], answer[2], answer[4]
  end
  if not list then FA.Print(why); return end
  StaticPopup_Show("FOREVERARMOURY_APPLY", "Spend " .. #list .. (#list == 1 and " point" or " points") .. " as " ..
    (build.name ~= "" and FA.Esc(build.name) or "the build") .. " says?\n\n" .. FA.Summary(list, 8) ..
    (stopped and ("\n\nIt stops at " .. FA.Where(stopped.tab, stopped.cell) .. ", a talent your trees don't have.") or ""), nil, { id = build.id })
end

--[[ What the panel says about the active build: its next point, or why there isn't one, and what it takes to swap. ]]
local function statusText(build, p, why)
  if not build then return "Pick a build to follow. Its next talent lights up in the trees." end
  if not p then return why end
  local lines = {}
  local unplaced = FA.UnplacedText(p.unplaced)
  if unplaced then lines[1] = "|cffff6060" .. unplaced .. "|r." end
  if p.off > 0 then
    local names = {}
    for i, x in ipairs(p.extra) do if i <= 3 then names[#names + 1] = (x.talent.name or "?") .. (x.over > 1 and (" x" .. x.over) or "") end end
    lines[#lines + 1] = "|cffff6060" .. p.off .. (p.off == 1 and " point isn't" or " points aren't") .. " in this build|r (" .. table.concat(names, ", ") .. (#p.extra > 3 and ", ..." or "") .. ")."
    lines[#lines + 1] = FA.SwapAdvice(build)
    return table.concat(lines, "\n")
  end
  if p.next then
    local trees = Talents.Trees()
    local tree = trees and trees[p.next.talent.tab]
    local when = p.next.n <= p.due and "now" or ("at level " .. p.next.level)
    lines[#lines + 1] = "Next: |cffffd100" .. (p.next.talent.name or "?") .. "|r " .. p.next.rank .. "/" .. (p.next.talent.max or "?") ..
      (tree and (" (" .. tree.name .. ")") or "") .. ", " .. when .. "."
  else
    lines[#lines + 1] = p.blocked and "Every point of this build that your trees have is spent." or "Every point of this build is spent."
  end
  return table.concat(lines, "\n")
end

--[[ The list moved by some builds, up (negative) or down, as far as it goes. ]]
function FA.ScrollBuilds(by)
  offset = math.max(0, math.min(offset + by, #FA.BuildsFor(FA.class) - ROWS))
  FA.Refresh()
end

function FA.Refresh()
  if not panel then return end
  local f = Talents.Frame()
  if not FA.PartOn("plan") or (f and not f:IsShown()) then
    panel:Hide()
    if strip then strip:Hide() end
    lightTalent(nil)
    dropHover()
    return
  end
  panel:Show()
  local list, active = FA.BuildsFor(FA.class), FA.ActiveBuild()
  offset = math.max(0, math.min(offset, #list - ROWS))
  --[[ The builds section: its header, then the list when it's open; the panel is as tall as what it shows. ]]
  local open = buildsOpen(active)
  local shown = open and math.min(#list, ROWS) or 0
  panel.header.sign:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
  panel.header.text:SetText((not open and active) and FA.ShownName(active) or ("Builds (" .. #list .. ")"))
  panel:SetHeight(LIST_Y - 4 + shown * 21 + (open and #list > ROWS and 22 or 0) + 50)
  for i, row in ipairs(panel.rows) do
    local b = open and list[i + offset] or nil
    row.build = b
    if b then
      row.text:SetText(FA.ShownName(b))
      row.mark:SetShown(active == b)
      row:Show()
    else
      row:Hide()
    end
  end
  if open and #list > ROWS then
    panel.up:Show(); panel.down:Show(); panel.more:Show()
    if offset > 0 then panel.up:Enable() else panel.up:Disable() end
    if offset < #list - ROWS then panel.down:Enable() else panel.down:Disable() end
    panel.more:SetText((offset + 1) .. "-" .. (offset + ROWS) .. " of " .. #list)
  else
    panel.up:Hide(); panel.down:Hide(); panel.more:Hide()
  end
  if #list == 0 then
    panel.status:SetText("No builds for this class yet. On the site, Copy for addon, then Import here.")
    panel.apply:Disable(); panel.apply:SetText("Apply"); panel.apply.why = nil
    lightTalent(nil)
    refreshStrip(nil)
    return
  end
  local p, why
  if active then p, why = FA.Progress(active) end
  panel.status:SetText(statusText(active, p, why))
  lightTalent(p and p.next and p.next.talent or nil)
  refreshStrip(p)
  --[[ Apply says how many points it would spend, or why it can't, before it's pressed. ]]
  local plan, stopped
  if not active then why = "Pick a build to follow first."
  else
    local can, combat = Talents.CanChange()
    if can then
      local answer = { FA.PlanApply(active) }   -- list, why, progress, the pick that stopped it
      plan, why, stopped = answer[1], answer[2], answer[4]
    else why = combat end
  end
  if plan then
    panel.apply:Enable(); panel.apply:SetText("Apply " .. #plan .. (#plan == 1 and " point" or " points")); panel.apply.why = FA.Summary(plan, 8) ..
      (stopped and ("\nStops at " .. FA.Where(stopped.tab, stopped.cell) .. ", a talent your trees don't have.") or "")
  else
    panel.apply:Disable(); panel.apply:SetText("Apply"); panel.apply.why = why
  end
end

--[[ Once Blizzard's talent UI is in: the panel on its window, and a refresh whenever it shows, hides or redraws. ]]
function FA.HookTalentFrame()
  if hooked then return end
  local f = Talents.Frame()
  if not f then return end
  hooked = true
  makePanel()
  f:HookScript("OnShow", FA.Refresh)
  f:HookScript("OnHide", FA.Refresh)
  if f.LoadTalentTreeInternal then hooksecurefunc(f, "LoadTalentTreeInternal", FA.RefreshSoon) end
  if f.OnTraitConfigUpdated then hooksecurefunc(f, "OnTraitConfigUpdated", FA.RefreshSoon) end
  if TalentFrame_Update then hooksecurefunc("TalentFrame_Update", FA.Refresh) end
  FA.Refresh()
end

function FA.ToggleTalents() Talents.Toggle() end

--[[ ---- the import box ---- ]]
local function makeImportBox()
  importBox = CreateFrame("Frame", "ForeverArmouryImport", UIParent, TEMPLATE)
  importBox:SetSize(440, 250)
  importBox:SetPoint("CENTER")
  importBox:SetBackdrop(BACKDROP)
  importBox:SetFrameStrata("DIALOG")
  importBox:SetMovable(true)
  importBox:EnableMouse(true)
  importBox:RegisterForDrag("LeftButton")
  importBox:SetScript("OnDragStart", importBox.StartMoving)
  importBox:SetScript("OnDragStop", importBox.StopMovingOrSizing)
  importBox:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "ForeverArmouryImport")   -- Escape closes it

  local title = importBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Forever Armoury: codes from the site")
  local hint = importBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -34)
  hint:SetPoint("TOPRIGHT", -16, -34)
  hint:SetJustifyH("LEFT")
  hint:SetText("Paste a build code, a gear route code or a Legacy plan code from the site (Copy for addon) and press Import. Export puts your builds' and Legacy plans' codes here to copy.")

  local scroll = CreateFrame("ScrollFrame", "ForeverArmouryImportScroll", importBox, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 18, -64)
  scroll:SetPoint("BOTTOMRIGHT", -36, 70)
  local bg = importBox:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0, 0, 0, 0.5)
  bg:SetPoint("TOPLEFT", scroll, -4, 4)
  bg:SetPoint("BOTTOMRIGHT", scroll, 4, -4)
  local box = CreateFrame("EditBox", "ForeverArmouryImportText", scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(380)
  box:SetMaxLetters(0)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnTextChanged", function() importBox.status:SetText("") end)
  scroll:SetScrollChild(box)
  scroll:SetScript("OnSizeChanged", function(_, w) box:SetWidth(w) end)
  importBox.box = box

  importBox.status = importBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  importBox.status:SetPoint("BOTTOMLEFT", 16, 44)
  importBox.status:SetPoint("BOTTOMRIGHT", -16, 44)
  importBox.status:SetJustifyH("LEFT")
  importBox.status:SetWordWrap(true)

  local import = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
  import:SetSize(90, 22)
  import:SetPoint("BOTTOMLEFT", 14, 14)
  import:SetText("Import")
  import:SetScript("OnClick", function() FA.ImportText(box:GetText()) end)
  local export = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
  export:SetSize(90, 22)
  export:SetPoint("LEFT", import, "RIGHT", 6, 0)
  export:SetText("Export")
  export:SetScript("OnClick", function()
    local builds, plans = FA.ExportCode(), FA.Legacy and FA.Legacy.Export()
    if builds or plans then
      box:SetText(builds and plans and (builds .. "\n" .. plans) or builds or plans); box:SetFocus(); box:HighlightText()
      importBox.status:SetText((builds and plans and "Every build of your class and every Legacy plan." or builds and "Every build of your class." or "Every Legacy plan.") ..
        " Ctrl+C copies it; paste it into the site's Import box.")
    else importBox.status:SetText("No builds for this class or Legacy plans yet.") end
  end)
  local close = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
  close:SetSize(80, 22)
  close:SetPoint("BOTTOMRIGHT", -14, 14)
  close:SetText("Close")
  close:SetScript("OnClick", function() importBox:Hide() end)
end

--[[ Reads the codes in a pasted text and keeps their builds, gear routes and Legacy plans; says what came of it in
     the box and in chat. One paste can hold all three kinds. When none reads, the error is that of the first kind the
     text has a code of (builds, then gear, then Legacy), else the build code's; when some kinds read and another
     doesn't, the other's error is added. ]]
function FA.ImportText(text)
  local builds, err, notes = FA.Code.Read(text)
  local routes, gerr, gnotes = nil, nil, nil
  if FA.GearCode then routes, gerr, gnotes = FA.GearCode.Read(text) end
  local plans, lerr, lnotes = nil, nil, nil
  if FA.LegacyCode then plans, lerr, lnotes = FA.LegacyCode.Read(text) end
  local hasBuild = tostring(text or ""):find("FAT%d%d?%d?%-") ~= nil
  local hasGear = FA.GearCode and FA.GearCode.Find(text)
  local hasLegacy = FA.LegacyCode and FA.LegacyCode.Find(text)
  --[[ the errors of the kinds the text has a code of and that didn't read, in order ]]
  local errors = {}
  if hasBuild and not builds then errors[#errors + 1] = err end
  if hasGear and not routes then errors[#errors + 1] = gerr end
  if hasLegacy and not plans then errors[#errors + 1] = lerr end
  if not builds and not routes and not plans then
    err = errors[1] or err
    if importBox then importBox.status:SetText("|cffff6060" .. err .. "|r") end
    return false, err
  end
  local className = FA.class:sub(1, 1):upper() .. FA.class:sub(2)
  local mine, others, said = 0, 0, ""
  if builds then
    mine, others = FA.AddBuilds(builds)
    said = (mine == 0 and "No " or mine .. " ") .. className .. (mine == 1 and " build" or " builds") .. " imported"
    if others > 0 then said = said .. ", and " .. others .. " for other classes kept for their characters" end
    said = said .. "."
    for _, n in ipairs(notes or {}) do said = said .. " " .. n end
    --[[ A character with one build and none followed follows it, so the first paste lights a talent straight away. ]]
    if mine > 0 and not FA.ActiveBuild() then
      local list = FA.BuildsFor(FA.class)
      if #list == 1 then FA.SetActive(list[1].id); said = said .. " Following " .. FA.ShownName(list[1]) .. "." end
    end
    --[[ A build with picks off the character's trees is said so now, once per build, so the player knows before opening the
         window; the panel's status says it for as long as the build is followed ]]
    for _, b in ipairs(builds) do
      if b.cls == FA.class then
        local view, saved = FA.Talents.View(), nil
        for _, old in ipairs(FA.BuildsFor(FA.class)) do if old.name == b.name and old.picks == b.picks then saved = old end end
        local p = view and saved and FA.Progress(saved, view)
        local unplaced = p and FA.UnplacedText(p.unplaced)
        if unplaced then
          said = said .. " " .. FA.ShownName(saved) .. ": " .. unplaced .. ". The rest of it works; Apply stops at the first of them."
        end
      end
    end
  end
  if routes then
    local rmine, rothers = FA.Gear.Add(routes)
    said = said .. (said ~= "" and " " or "") .. (rmine == 0 and "No " or rmine .. " ") .. className .. (rmine == 1 and " gear route" or " gear routes") .. " imported"
    if rothers > 0 then said = said .. ", and " .. rothers .. " for other classes kept for their characters" end
    said = said .. "."
    for _, n in ipairs(gnotes or {}) do said = said .. " " .. n end
    if rmine > 0 and FA.Gear.Spec() == nil then said = said .. " Follow a build, or pick the route's spec in the gear panel." end
  end
  if plans then
    local count = FA.Legacy.Add(plans)
    said = said .. (said ~= "" and " " or "") .. count .. (count == 1 and " Legacy plan" or " Legacy plans") .. " imported for the account."
    for _, n in ipairs(lnotes or {}) do said = said .. " " .. n end
    local other = 0
    for _, p in ipairs(plans) do if FA.Legacy.Differs(p) then other = other + 1 end end
    if other > 0 then
      said = said .. " " .. other .. (other == 1 and " is" or " are") .. " from another client build than the addon's Legacy perks (" .. FA.Legacy.BUILD ..
        "), so " .. (other == 1 and "it is" or "they are") .. " shown and never bought."
    end
    --[[ the account with one plan and none followed follows it, as a character does a build ]]
    if not FA.Legacy.Active() and #FA.Legacy.Plans() == 1 then
      local only = FA.Legacy.Plans()[1]
      FA.Legacy.SetActive(only.id)
      said = said .. " Following " .. FA.ShownName(only) .. "."
    end
  end
  for _, e in ipairs(errors) do said = said .. " " .. e end
  if importBox then importBox.status:SetText(said); importBox.box:SetText("") end
  FA.Print(said)
  FA.Refresh()
  if FA.RefreshGear then FA.RefreshGear() end
  if FA.RefreshLegacy then FA.RefreshLegacy() end
  return true, said
end

function FA.OpenImport(text, note)
  if not importBox then makeImportBox() end
  importBox:Show()
  importBox.status:SetText("")
  if text then
    importBox.box:SetText(text)
    importBox.box:SetFocus()
    importBox.box:HighlightText()
    importBox.status:SetText(note or "Every build of your class. Ctrl+C copies it; paste it into the site's Import box.")
  else
    importBox.box:SetText("")
    importBox.box:SetFocus()
  end
end

--[[ ---- the settings page: a switch for each part ---- ]]
function FA.SetupOptions()
  if options then return end
  options = CreateFrame("Frame", "ForeverArmouryOptions", UIParent)
  options.name = "Forever Armoury"
  options:Hide()
  local title = options:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Forever Armoury " .. FA.VERSION)
  local sub = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  sub:SetText("Each part of the addon has its own switch.")
  local y = -70
  for _, part in ipairs(FA.PARTS) do
    local cb = CreateFrame("CheckButton", nil, options, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
    cb:SetChecked(FA.PartOn(part.key))
    cb:SetScript("OnClick", function(self) FA.SetPart(part.key, self:GetChecked() and true or false) end)
    local label = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(part.name)
    local text = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, 2)
    text:SetText(part.text)
    options:HookScript("OnShow", function() cb:SetChecked(FA.PartOn(part.key)) end)
    y = y - 48
  end

  --[[ The strip's counts: how many points it shows before the next one, and after it. ]]
  local heading = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  heading:SetPoint("TOPLEFT", 16, y)
  heading:SetText("The icon strip beside the talent window")
  y = y - 34
  for _, kind in ipairs({ { "past", "Taken points shown" }, { "coming", "Coming points shown" } }) do
    local key, text = kind[1], kind[2]
    local name = "ForeverArmouryStrip" .. key:sub(1, 1):upper() .. key:sub(2)
    local slider = CreateFrame("Slider", name, options, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 20, y)
    slider:SetWidth(180)
    slider:SetMinMaxValues(0, FA.STRIP_MAX[key])
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    --[[ the template's own captions say LOW and HIGH; a client without them (or named otherwise) is left alone ]]
    if _G[name .. "Low"] then _G[name .. "Low"]:SetText("0") end
    if _G[name .. "High"] then _G[name .. "High"]:SetText(tostring(FA.STRIP_MAX[key])) end
    if _G[name .. "Text"] then _G[name .. "Text"]:SetText(text) end
    local label = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", slider, "RIGHT", 14, 0)
    local function show(n) label:SetText(n) end
    slider:SetValue(FA.StripCount(key))
    show(FA.StripCount(key))
    slider:SetScript("OnValueChanged", function(_, value)
      value = math.floor(value + 0.5)
      if value == FA.db.strip[key] then return end
      FA.db.strip[key] = value
      show(value)
      FA.Refresh()
    end)
    options:HookScript("OnShow", function() slider:SetValue(FA.StripCount(key)); show(FA.StripCount(key)) end)
    y = y - 40
  end
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(options, options.name)
    Settings.RegisterAddOnCategory(cat)
    FA.optionsCategory = cat
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(options)
  end
end

function FA.OpenOptions()
  if not options then FA.SetupOptions() end
  if FA.optionsCategory and Settings and Settings.OpenToCategory then Settings.OpenToCategory(FA.optionsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(options)
    InterfaceOptionsFrame_OpenToCategory(options)   -- the first call opens the window, the second finds the page
  end
end
