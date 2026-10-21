--[[ The strip of icons beside a window, which the talent window and the Legacy window share: a plan's points in the order
     they come (the last few taken, the next, the ones coming), as many as the strip's height holds, scrolling past them;
     hovering an icon lights its button in the window's tree and shows the game's tooltip, a click on the next icon spends
     it and a shift-click spends everything due. What a plan is, what its buttons are and how a point is spent belong to
     the strip's owner (TalentUI.lua for builds, LegacyUI.lua for Legacy plans); the size and the scroll settings are the
     same for both (FA.db.strip).

     FA.Strip.New(owner) makes a strip for an owner, a table with:
       name            the strip frame's global name
       anchor()        the frame the strip hangs on, and how far its left edge sits from that frame's right edge (-2 for
                       the strip to touch it, more to clear a window's side tabs)
       plan(offset, count)  the plan from the point `offset` points down its order, `count` of them: the list, the offset
                       (held to what fits), how many points follow, where the next sits in the whole order (nil once every
                       point is taken) and how many points the whole order has. A count of 0 gives the last two without
                       the list; a total of 0 hides the strip. An entry is { kind = "taken" | "next" | "coming" |
                       "unplaced", icon, ranks (the r/m on the icon, "" for none), label (under the next: "Now", "L17"),
                       badge (on a coming point: its level, its tree) } and whatever else the owner's functions want
       refreshKey()    text that changes when the character's points do, so the view follows the next point again
       button(entry)   the window's tree button for an entry, or nil (hover lights it)
       tooltip(entry, tip)  fills the game's tooltip, which the strip has put on the icon, for an entry
       can(entry)      what a click on the entry can do now: how many points a shift-click would take (1 or more), or nil
                       and why not (nil and nil for an entry with no click, which is every one but the next)
       spend(entry)    the click: spends that one point, says how it went in chat and redraws
       spendAll()      the shift-click: everything due, through the owner's confirm
       verb            "take" or "buy", for the tooltip's "Click to take it"
     and answers a strip with
       strip.frame     the frame
       strip:Refresh() draws the plan again; answers whether the strip is shown (it isn't for a plan with no points)
       strip:Hide()    hides it and lets go of the icon under the mouse
       strip:Follow()  the view goes back to the next point at the next Refresh
     FA.Strip.RankText(rank, max) is an icon's r/m. FA.LightButtons lights buttons of the tree; FA.StripFollow() does
     Follow for every strip, as the character's points change. ]]

local _, FA = ...
local Strip = {}
FA.Strip = Strip

local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local ICON = 34     -- the icon size the strip's proportions are drawn for; the setting scales them
local STRIP_PAD = 14    -- the strip is this much wider than its icons
local PAD, GAP, ARROW, DOTS = 12, 4, 18, 16   -- the strip's margin at its ends, between icons, an arrow's height, the dots' height
local GAP_AFTER = 8     -- between the points taken and the ones coming
local FALLBACK_H = 850  -- the strip's height when the game hasn't laid it out yet (the talent window's, on the live client)
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--[[ The panel's border at half the weight, so the icons fit a strip 14 px wider than they are. ]]
local STRIP_BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 16, insets = { left = 5, right = 5, top = 5, bottom = 5 } }

local strips = {}   -- every strip made, for FA.StripFollow

--[[ ---- the highlights in the trees ---- ]]
--[[ A frame of ours over each of a list of buttons, kept in a set by button: the game's talent frames pool and reuse their
     buttons, so nothing is written on them. Lights those that are shown and hides the rest of the set; r, g, b tint
     it. The talent panel and the Legacy panel light their next talents with it, the strips the one under the mouse. ]]
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

--[[ An icon's r/m: nothing for a point whose talent has one rank, "?" for a count the game didn't give. ]]
function Strip.RankText(rank, max)
  if max == nil then return rank .. "/?" end
  return max > 1 and (rank .. "/" .. max) or ""
end

--[[ The size of the text on an icon at a size: the r/m, the level in its badge, and the "Now" or level under the next one. ]]
local function fontPx(size) return math.floor(size * 0.3 + 0.5) end

--[[ An icon drawn for a size: the glow, border, check, badge and text scale with it (the proportions are those of ICON). ]]
local function sizeIcon(icon, size)
  if icon.drawnSize == size then return end
  icon.drawnSize = size
  local k, px = size / ICON, fontPx(size)
  local function scaled(n) return math.floor(n * k + 0.5) end
  icon:SetSize(size, size)
  icon.edge:ClearAllPoints()
  icon.edge:SetPoint("TOPLEFT", -scaled(2), scaled(2))
  icon.edge:SetPoint("BOTTOMRIGHT", scaled(2), -scaled(2))
  icon.glow:ClearAllPoints()
  icon.glow:SetPoint("TOPLEFT", -scaled(4), scaled(4))
  icon.glow:SetPoint("BOTTOMRIGHT", scaled(4), -scaled(4))
  icon.check:SetSize(scaled(16), scaled(16))
  icon.check:ClearAllPoints()
  icon.check:SetPoint("TOPRIGHT", scaled(3), scaled(3))
  icon.levelBg:SetSize(scaled(18), scaled(12))
  icon.rank:ClearAllPoints()
  icon.rank:SetPoint("TOPLEFT", scaled(2), -scaled(2))
  for _, text in ipairs({ icon.rank, icon.level, icon.label }) do
    local path, _, flags = text:GetFont()
    if path then text:SetFont(path, px, flags) end
  end
  icon.label:ClearAllPoints()
  icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -1)
end

--[[ How many icons fit the strip's height at a size, with or without the arrows (and the dots) a scrolling strip needs:
     the margins, the label under the next icon and the gap after the taken ones come off the height first. ]]
local function fits(height, size, arrows)
  local pad = 2 * PAD + fontPx(size) + 2 + GAP_AFTER + (arrows and 2 * ARROW + DOTS or 0)
  return math.max(1, math.floor((height - pad) / (size + GAP)))
end

--[[ Where the view starts when the player hasn't scrolled it: the setting's count of taken points above the next, and at
     least the setting's count of coming points below it when the strip has room, the next always in view. ]]
local function startOf(nextAt, total, count)
  local top
  if nextAt then
    top = nextAt - 1 - FA.StripCount("past")
    top = math.min(math.max(top, nextAt + FA.StripCount("coming") - count), nextAt - 1)
  else
    top = total - count   -- every point is taken: the end of the plan
  end
  return math.max(0, math.min(top, total - count))
end

local Methods = {}
local meta = { __index = Methods }

--[[ What a click on an icon can do now: how many points a shift-click would take, or nil and why not. The icon's
     highlight shows only when the click would work. ]]
function Methods:Clickable(icon)
  local n, why
  if icon.entry then n, why = self.owner.can(icon.entry) end
  icon.highlight:SetAlpha(n and 1 or 0)
  return n, why
end

--[[ An icon's tooltip: the owner's (the point's spell as the game shows it, its rank and where it stands), then what a
     click does, or why it does nothing. ]]
function Methods:Tip(icon)
  local e = icon.entry
  if not e then return end
  local owner = self.owner
  GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
  owner.tooltip(e, GameTooltip)
  local n, why = self:Clickable(icon)
  if n then
    GameTooltip:AddLine("Click to " .. owner.verb .. " it", 0.3, 1, 0.3)
    if n > 1 then GameTooltip:AddLine("Shift-click to " .. owner.verb .. " all " .. n, 0.3, 1, 0.3) end
  elseif why then
    GameTooltip:AddLine(why, 1, 0.4, 0.4, true)
  end
  GameTooltip:Show()
end

--[[ The entry's button in the tree lit in blue, so it reads beside the next point's glow, which stays; nil lights none. ]]
function Methods:Light(entry)
  local button = entry and self.owner.button(entry)
  lightButtons(self.hovers, button and { button } or {}, 0.3, 0.7, 1)
end

--[[ The strip is going away, or the window is: no icon is under the mouse any more. ]]
function Methods:DropHover()
  if self.hovering then GameTooltip:Hide() end
  self.hovering = nil
  self:Light(nil)
end

function Methods:Hide()
  self.frame:Hide()
  self:DropHover()
end

function Methods:Follow() self.scrolled = false end

--[[ The strip moves to show the points from `by` further down the order (negative is up), as far as it goes. The player
     has scrolled it, so it stays there until their points change (Follow). ]]
function Methods:Scroll(by)
  if self.fromMax <= 0 then return end
  self.from = math.max(0, math.min(self.from + by, self.fromMax))
  self.scrolled = true
  self:Refresh()
end

local function makeIcon(self)
  local owner = self.owner
  local icon = CreateFrame("Button", nil, self.frame)
  icon:SetSize(ICON, ICON)
  icon.edge = icon:CreateTexture(nil, "BACKGROUND")   -- the next one's gold border
  icon.edge:SetColorTexture(1, 0.82, 0, 1)
  icon.tex = icon:CreateTexture(nil, "ARTWORK")
  icon.tex:SetAllPoints(icon)
  icon.glow = icon:CreateTexture(nil, "OVERLAY")   -- and the glow the panel puts on its button
  icon.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  icon.glow:SetBlendMode("ADD")
  icon.check = icon:CreateTexture(nil, "OVERLAY")
  icon.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  icon.rank = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  icon.rank:SetShadowOffset(1, -1)
  icon.levelBg = icon:CreateTexture(nil, "ARTWORK", nil, 2)   -- the level a coming point is due in
  icon.levelBg:SetColorTexture(0, 0, 0, 0.7)
  icon.levelBg:SetPoint("BOTTOMRIGHT")
  icon.level = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  icon.level:SetPoint("CENTER", icon.levelBg)
  icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")   -- "Now" or "L25", under the next one
  icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")   -- shown on the mouse over, and only when Clickable says a click would work
  icon.highlight = icon:GetHighlightTexture()
  icon.highlight:SetBlendMode("ADD")
  icon.highlight:SetAlpha(0)
  icon:RegisterForClicks("LeftButtonUp")
  icon:SetScript("OnEnter", function(this)
    if not this.entry then return end
    self.hovering = this
    self:Light(this.entry)
    self:Tip(this)
  end)
  icon:SetScript("OnLeave", function()
    self.hovering = nil
    self:Light(nil)
    GameTooltip:Hide()
  end)
  --[[ The next icon takes its point: one click, and Apply's way (staged and committed together, all or none, rolled back
       and said in chat if the game refuses); shift-click is Apply for every point due, through its confirm. A click that
       can't do either does nothing, and the tooltip says why. While the commit casts the points are staged, so a second
       click finds the owner busy and is ignored. ]]
  icon:SetScript("OnClick", function(this)
    if not self:Clickable(this) then return end
    if IsShiftKeyDown() then owner.spendAll() else owner.spend(this.entry) end
  end)
  return icon
end

local function makeFrame(self)
  local owner = self.owner
  local anchor, by = owner.anchor()
  local strip = CreateFrame("Frame", owner.name, anchor, TEMPLATE)
  strip:SetWidth(ICON + STRIP_PAD)
  strip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", by, 0)
  strip:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", by, 0)
  strip:SetBackdrop(STRIP_BACKDROP)
  strip:SetFrameStrata("HIGH")
  strip:SetClampedToScreen(true)
  strip.icons = {}
  --[[ the game lays the strip out after it is shown, so the height drawn for may be out of date: draw again when it changes ]]
  strip:SetScript("OnSizeChanged", function(_, _, height)
    if height and height ~= self.usedHeight then FA.RefreshSoon() end
  end)
  --[[ more points than fit: the wheel over the strip moves it an icon a notch, and an arrow at each end a page ]]
  strip:EnableMouseWheel(true)
  strip:SetScript("OnMouseWheel", function(_, delta) self:Scroll(delta > 0 and -1 or 1) end)
  strip.up = CreateFrame("Button", nil, strip, "UIPanelScrollUpButtonTemplate")
  strip.up:SetSize(ARROW, ARROW)
  strip.up:SetPoint("TOP", 0, -8)
  strip.up:SetScript("OnClick", function() self:Scroll(-math.max(1, self.shownCount - 1)) end)
  strip.down = CreateFrame("Button", nil, strip, "UIPanelScrollDownButtonTemplate")
  strip.down:SetSize(ARROW, ARROW)
  strip.down:SetPoint("BOTTOM", 0, 8)
  strip.down:SetScript("OnClick", function() self:Scroll(math.max(1, self.shownCount - 1)) end)
  strip.more = CreateFrame("Frame", nil, strip)   -- three dots, drawn here since the font may not have a vertical ellipsis
  strip.more:SetSize(ICON, DOTS)
  strip.more:EnableMouse(true)
  for i = 1, 3 do
    local dot = strip.more:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(0.8, 0.8, 0.8, 1)
    dot:SetSize(3, 3)
    dot:SetPoint("TOP", 0, -2 - (i - 1) * 5)
  end
  strip.more:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(this.count .. (this.count == 1 and " more point" or " more points"), 1, 1, 1)
    GameTooltip:Show()
  end)
  strip.more:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return strip
end

function Strip.New(owner)
  local self = setmetatable({ owner = owner, hovers = {}, from = 0, fromMax = 0, shownCount = 0 }, meta)
  --[[ from: how many points are scrolled off the top; fromMax the most it can be; shownCount how many are shown; scrolled
       whether the player has scrolled it, which keeps the view where it is until their points change; usedHeight the
       height it was drawn for; seen the owner's key it was last drawn for; hovering the icon under the mouse ]]
  self.frame = makeFrame(self)
  strips[#strips + 1] = self
  return self
end

--[[ The strip's points shown again as the character's change: each strip goes back to its next point. ]]
function FA.StripFollow() for _, s in ipairs(strips) do s:Follow() end end

--[[ The strip for the owner's plan: hidden without points, else as many of them as its height holds at the icon size, top to
     bottom from where the view starts; a plan that doesn't fit scrolls. The icon under the mouse keeps its highlight and
     tooltip through the redraw. Answers whether the strip is shown. ]]
function Methods:Refresh()
  local owner, strip = self.owner, self.frame
  local size = FA.StripSize()
  local _, _, _, nextAt, total = owner.plan(0, 0)
  if total == 0 then
    self:Hide()
    return false
  end
  strip:SetWidth(size + STRIP_PAD)
  strip:Show()
  local height = strip:GetHeight()   -- once anchored and shown
  if type(height) ~= "number" or height <= 0 then height = (owner.anchor()):GetHeight() end
  if type(height) ~= "number" or height <= 0 then height = FALLBACK_H end
  self.usedHeight = height
  local arrows = total > fits(height, size, false)
  local count = arrows and fits(height, size, true) or total
  --[[ a new plan or a point spent, and the strip follows the next point again ]]
  local now = owner.refreshKey()
  if now ~= self.seen then self.scrolled = false; self.seen = now end
  self.fromMax = math.max(0, total - count)
  if not self.scrolled then self.from = startOf(nextAt, total, count) end
  local entries, above, below = owner.plan(self.from, count)
  self.from, self.shownCount = above, #entries
  strip.up:SetShown(arrows)
  strip.down:SetShown(arrows)
  if above > 0 then strip.up:Enable() else strip.up:Disable() end
  if below > 0 then strip.down:Enable() else strip.down:Disable() end
  local y = PAD + (arrows and ARROW or 0)
  for i, e in ipairs(entries) do
    local icon = strip.icons[i]
    if not icon then icon = makeIcon(self); strip.icons[i] = icon end
    sizeIcon(icon, size)
    icon.entry = e
    icon.tex:SetTexture(e.icon or UNKNOWN_ICON)   -- a pick off the trees has no talent: a question mark, greyed
    icon.tex:SetAlpha(e.kind == "taken" and 0.45 or e.kind == "unplaced" and 0.5 or 1)
    if icon.tex.SetDesaturated then icon.tex:SetDesaturated(e.kind == "unplaced") end
    icon.check:SetShown(e.kind == "taken")
    icon.edge:SetShown(e.kind == "next")
    icon.glow:SetShown(e.kind == "next")
    icon.rank:SetText(e.ranks or "")
    local badged = e.kind == "coming" or e.kind == "unplaced"
    icon.levelBg:SetShown(badged)
    icon.level:SetShown(badged)
    icon.level:SetText(badged and e.badge or "")
    icon.label:SetShown(e.kind == "next")
    icon.label:SetText(e.kind == "next" and e.label or "")
    self:Clickable(icon)
    if e.kind == "coming" and entries[i - 1] and entries[i - 1].kind ~= "coming" then y = y + GAP_AFTER end   -- a gap after the next one
    icon:ClearAllPoints()
    icon:SetPoint("TOP", strip, "TOP", 0, -y)
    icon:Show()
    y = y + size + GAP + (e.kind == "next" and fontPx(size) + 2 or 0)
  end
  for i = #entries + 1, #strip.icons do
    strip.icons[i].entry = false
    strip.icons[i]:Hide()
  end
  strip.more.count = below
  strip.more:SetShown(below > 0)
  strip.more:SetWidth(size)
  strip.more:ClearAllPoints()
  strip.more:SetPoint("TOP", strip, "TOP", 0, -y)
  if self.hovering and self.hovering.entry then
    self:Light(self.hovering.entry)
    self:Tip(self.hovering)
  else
    self:DropHover()
  end
  return true
end
