--[[ The level plan part's windows: a panel beside the talent window listing the character's builds, with the active
     one's next talent named and lit in the trees; the import box, where codes are pasted in and copied out; and the
     addon's settings page. Talents.lua says which frame the talent window is and which button a talent has, so
     nothing here depends on the client's version of it. ]]

local _, FA = ...
local Talents = FA.Talents

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ROWS = 10    -- rows the list shows at once; more builds than that scroll (FA.ScrollBuilds)
local panel, importBox, options, hooked
local glows = {}   -- talent button -> its highlight

--[[ A build's name as the panel and chat draw it: escaped (FA.Escape), so a | in it is a pipe and not a colour. ]]
local function shownName(b, none) return b.name ~= "" and FA.Escape(b.name) or none end

--[[ ---- the next-talent highlight ---- ]]
local function lightTalent(t)
  for _, g in pairs(glows) do g:Hide() end
  local button = t and Talents.Button(t)
  if not button or not button:IsShown() then return end
  local g = glows[button]
  if not g then
    g = CreateFrame("Frame", nil, button)
    g:SetAllPoints(button)
    g:SetFrameLevel(button:GetFrameLevel() + 5)
    local tex = g:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    tex:SetBlendMode("ADD")
    tex:SetPoint("TOPLEFT", -4, 4)
    tex:SetPoint("BOTTOMRIGHT", 4, -4)
    local pulse = g:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7)
    g.pulse = pulse
    glows[button] = g
  end
  g:Show()
  g.pulse:Play()
end

--[[ ---- the panel beside the talent window ---- ]]
local function makePanel()
  local window = Talents.Window() or UIParent
  panel = CreateFrame("Frame", "ForeverArmouryTalentPanel", window, TEMPLATE)
  panel:SetSize(210, 410)
  if Talents.Window() then panel:SetPoint("TOPLEFT", window, "TOPRIGHT", -2, -20) else panel:SetPoint("CENTER") end
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

  panel.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(158, 20)
    row:SetPoint("TOPLEFT", 16, -132 - (i - 1) * 21)
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
      if b then StaticPopup_Show("FOREVERARMOURY_FORGET", shownName(b, "Unnamed"), nil, { cls = FA.class, id = b.id }) end
    end)
    panel.rows[i] = row
  end

  --[[ The list's scroll, for more builds than rows: an up and a down button with "1-10 of 12" between them, under the
       rows, and the mouse wheel over the panel. Hidden with ROWS builds or fewer. ]]
  panel.offset = 0
  panel.pager = CreateFrame("Frame", nil, panel)
  panel.pager:SetSize(178, 20)
  panel.pager:SetPoint("TOPLEFT", 16, -132 - ROWS * 21 - 2)
  panel.pager.up = CreateFrame("Button", nil, panel.pager, "UIPanelScrollUpButtonTemplate")
  panel.pager.up:SetSize(18, 18)
  panel.pager.up:SetPoint("LEFT", 0, 0)
  panel.pager.up:SetScript("OnClick", function() FA.ScrollBuilds(-1) end)
  panel.pager.down = CreateFrame("Button", nil, panel.pager, "UIPanelScrollDownButtonTemplate")
  panel.pager.down:SetSize(18, 18)
  panel.pager.down:SetPoint("RIGHT", 0, 0)
  panel.pager.down:SetScript("OnClick", function() FA.ScrollBuilds(1) end)
  panel.pager.text = panel.pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.pager.text:SetPoint("LEFT", panel.pager.up, "RIGHT", 4, 0)
  panel.pager.text:SetPoint("RIGHT", panel.pager.down, "LEFT", -4, 0)
  panel.pager.text:SetJustifyH("CENTER")
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
    if not build then return end
    local ok, said = FA.Apply(build)
    FA.Print(ok and ("Spent as " .. shownName(build, "the build") .. " says: " .. said .. ".") or said)
    FA.Refresh()
  end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

--[[ Apply: one confirm naming what it spends, then the points, all or none (FA.Apply). ]]
function FA.AskApply()
  local build = FA.ActiveBuild()
  if not build then FA.Print("Pick a build to follow first."); return end
  local ok, why = FA.Talents.CanChange()
  local list
  if ok then list, why = FA.PlanApply(build) end
  if not list then FA.Print(why); return end
  StaticPopup_Show("FOREVERARMOURY_APPLY", "Spend " .. #list .. (#list == 1 and " point" or " points") .. " as " ..
    shownName(build, "the build") .. " says?\n\n" .. FA.Summary(list, 8), nil, { id = build.id })
end

--[[ What the panel says about the active build: its next point, or why there isn't one, and what it takes to swap. ]]
local function statusText(build)
  if not build then return "Pick a build to follow. Its next talent lights up in the trees." end
  local p, why = FA.Progress(build)
  if not p then return why end
  local lines = {}
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
    lines[#lines + 1] = "Every point of this build is spent."
  end
  return table.concat(lines, "\n")
end

function FA.Refresh()
  if not panel then return end
  local f = Talents.Frame()
  if not FA.PartOn("plan") or (f and not f:IsShown()) then
    panel:Hide()
    lightTalent(nil)
    return
  end
  panel:Show()
  local list, active = FA.BuildsFor(FA.class), FA.ActiveBuild()
  local last = math.max(0, #list - ROWS)   -- the furthest the list scrolls
  if panel.offset > last then panel.offset = last end
  for i, row in ipairs(panel.rows) do
    local b = list[panel.offset + i]
    row.build = b
    if b then
      row.text:SetText(shownName(b, "Unnamed"))
      row.mark:SetShown(active == b)
      row:Show()
    else
      row:Hide()
    end
  end
  if last > 0 then
    panel.pager.text:SetText((panel.offset + 1) .. "-" .. math.min(panel.offset + ROWS, #list) .. " of " .. #list)
    if panel.offset > 0 then panel.pager.up:Enable() else panel.pager.up:Disable() end
    if panel.offset < last then panel.pager.down:Enable() else panel.pager.down:Disable() end
    panel.pager:Show()
  else
    panel.pager:Hide()
  end
  if #list == 0 then
    panel.status:SetText("No builds for this class yet. On the site, Copy for addon, then Import here.")
    panel.apply:Disable(); panel.apply:SetText("Apply"); panel.apply.why = nil
    lightTalent(nil)
    return
  end
  panel.status:SetText(statusText(active))
  local p = active and FA.Progress(active)
  lightTalent(p and p.next and p.next.talent or nil)
  --[[ Apply says how many points it would spend, or why it can't, before it's pressed. ]]
  local plan, why
  if active then plan, why = FA.PlanApply(active) else why = "Pick a build to follow first." end
  if plan then
    panel.apply:Enable(); panel.apply:SetText("Apply " .. #plan .. (#plan == 1 and " point" or " points")); panel.apply.why = FA.Summary(plan, 8)
  else
    panel.apply:Disable(); panel.apply:SetText("Apply"); panel.apply.why = why
  end
end

--[[ Scrolls the build list by a number of rows (negative is up), and redraws; the list keeps within its builds. ]]
function FA.ScrollBuilds(rows)
  if not panel then return end
  panel.offset = math.max(0, math.min(panel.offset + rows, #FA.BuildsFor(FA.class) - ROWS))
  FA.Refresh()
end

--[[ Once Blizzard's talent UI is in: the panel on its window, and a refresh whenever it shows, hides or redraws (the
     window's own redraws come in bursts, so they queue one, as the game's events do). ]]
function FA.HookTalentFrame()
  if hooked then return end
  local f = Talents.Frame()
  if not f then return end
  hooked = true
  makePanel()
  f:HookScript("OnShow", FA.Refresh)
  f:HookScript("OnHide", FA.Refresh)
  if f.LoadTalentTreeInternal then hooksecurefunc(f, "LoadTalentTreeInternal", function() FA.QueueRefresh(true) end) end
  if f.OnTraitConfigUpdated then hooksecurefunc(f, "OnTraitConfigUpdated", function() FA.QueueRefresh(true) end) end
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
  hint:SetText("Paste a build code or a gear route code from the site (Copy for addon) and press Import. Export puts your builds' code here to copy.")

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
    local code = FA.ExportCode()
    if code then box:SetText(code); box:SetFocus(); box:HighlightText(); importBox.status:SetText("Every build of your class. Ctrl+C copies it; paste it into the site's Import box.")
    else importBox.status:SetText("No builds for this class yet.") end
  end)
  local close = CreateFrame("Button", nil, importBox, "UIPanelButtonTemplate")
  close:SetSize(80, 22)
  close:SetPoint("BOTTOMRIGHT", -14, 14)
  close:SetText("Close")
  close:SetScript("OnClick", function() importBox:Hide() end)
end

--[[ Reads the codes in a pasted text and keeps their builds and gear routes; says what came of it in the box and in
     chat. One paste can hold both kinds. When neither reads, the error is the gear code's if the text has one and no
     build code, else the build code's; when one kind reads and the other doesn't, the other's error is added. ]]
function FA.ImportText(text)
  local builds, err, notes = FA.Code.Read(text)
  local routes, gerr, gnotes = nil, nil, nil
  if FA.GearCode then routes, gerr, gnotes = FA.GearCode.Read(text) end
  local hasBuild = tostring(text or ""):find("FAT%d+%-") ~= nil
  local hasGear = FA.GearCode and FA.GearCode.Find(text)
  if not builds and not routes then
    if hasGear and not hasBuild then err = gerr end
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
      if #list == 1 then FA.SetActive(list[1].id); said = said .. " Following " .. shownName(list[1], "it") .. "." end
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
  if builds and not routes and hasGear then said = said .. " " .. gerr end
  if routes and not builds and hasBuild then said = said .. " " .. err end
  if importBox then importBox.status:SetText(said); importBox.box:SetText("") end
  FA.Print(said)
  FA.Refresh()
  if FA.RefreshGear then FA.RefreshGear() end
  return true, said
end

function FA.OpenImport(text)
  if not importBox then makeImportBox() end
  importBox:Show()
  importBox.status:SetText("")
  if text then
    importBox.box:SetText(text)
    importBox.box:SetFocus()
    importBox.box:HighlightText()
    importBox.status:SetText("Every build of your class. Ctrl+C copies it; paste it into the site's Import box.")
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
