--[[ The Napkin part's window, the goblin counting engine: a dark panel with a gold border, the pad's rows down the
     left with an amber answer at each row's end, the keys in a block on the right, and a footer with Use, a hint and
     the character's own numbers. Napkin.lua reads the sums; nothing here does arithmetic.

     The pad is a list of lines (FA.char.napkin.lines, kept per character) seen through as many rows as fit the
     window's height: offset is the first line shown, visible how many rows there are, and bind() puts the lines into
     the rows. Dragging the bottom-right corner resizes the window: the keys grow with it, uniformly, and more rows fit
     as it gets taller; the place, size and whether the keys show are kept for the account (FA.db.napkin).

     The handlers are in Napkin.ui (Typed, Enter, Move, Remove, Scroll, Key, Copy, ToChat, Tooltip, Use, Focus) so the
     tests can drive the window through the frame mock, which keeps no scripts. ]]

local _, FA = ...
local Napkin = FA.Napkin

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local PAD, TITLE_H, FOOT_H, GAP, ROW_H = 16, 38, 32, 4, 22
local MIN_W, MIN_H, DEFAULT_W, DEFAULT_H = 300, 180, 440, 280
local KEY_MIN, KEY_MAX, PAD_MIN_W = 20, 64, 150
local ERROR_DELAY = 0.5
local KEYS = {
  { "7", "8", "9", "÷", "<<" },
  { "4", "5", "6", "×", "C" },
  { "1", "2", "3", "-", "pi" },
  { "0", ".", "%", "+", "=" },
  { "g", "s", "c", "(", ")" },
}
local TYPES = { ["÷"] = " / ", ["×"] = " * ", ["-"] = " - ", ["+"] = " + " }   -- what a key types; the others type their label
local DIGIT = { ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true, ["6"] = true, ["7"] = true, ["8"] = true, ["9"] = true, ["."] = true }
local AMBER, INK, RED, DIM = { 0.98, 0.78, 0.46 }, { 0.85, 0.84, 0.80 }, { 0.94, 0.58, 0.58 }, { 0.55, 0.54, 0.50 }
local MONEY_FRAMES = { "SendMailMoney", "TradePlayerInputMoney", "StartPrice", "BuyoutPrice" }
local MONEY_NAMES = { SendMailMoney = "the mail's money box", TradePlayerInputMoney = "the trade window's money box",
  StartPrice = "the auction's starting price", BuyoutPrice = "the auction's buyout price" }

local win, rows, keys, coins, hooked = nil, {}, {}, {}, {}
local results, offset, visible, binding = {}, 0, 0, false
local focused, lastLine, lastMoney, typedAt = nil, 1, nil, 0
local ui = {}
Napkin.ui = ui

local function lines() return FA.char.napkin.lines end
local function now() return GetTime and GetTime() or os.clock() end
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function setFont(fs, size)
  local path, _, flags = GameFontNormal:GetFont()
  if path then fs:SetFont(path, size, flags) end
end

--[[ ---- the answers ---- ]]
local function liveText()
  local parts = {}
  for _, w in ipairs({ "gold", "level", "points" }) do
    local ok, v = pcall(Napkin.values[w])
    if ok and v then parts[#parts + 1] = w .. " " .. Napkin.Format(v, false) end
  end
  return table.concat(parts, "  ·  ")
end

local function currentAnswer()
  local line = focused and focused.line or lastLine
  local r = results[line]
  return r and r.value
end

local function updateUse()
  if not win then return end
  local v = currentAnswer()
  local target = lastMoney and lastMoney:IsVisible() and MoneyInputFrame_SetCopper and lastMoney or nil
  if target and v and v.kind == "money" then
    win.use:Enable()
    win.use.why = "Puts " .. Napkin.Format(v, false) .. " into " .. (target.napkinName or "the money box") .. "."
  else
    win.use:Disable()
    win.use.why = target and "Use puts a money answer into " .. (target.napkinName or "the money box") .. "."
      or "Click into a money box in the mail, trade or auction house window first; then Use puts a money answer there."
  end
end

local function recalc()
  results = Napkin.Pad(lines(), { icons = true })
  if win then win.live:SetText(liveText()) end
end

--[[ A row's answer: amber, or its error in red; while the row is being typed in, the error waits half a second. ]]
local function showAnswer(row)
  local r = results[row.line] or {}
  local text = row.ans.text
  if r.err then
    if row == focused and C_Timer and now() - typedAt < ERROR_DELAY then text:SetText("")
    else text:SetText(r.err); text:SetTextColor(RED[1], RED[2], RED[3]) end
  elseif r.text then text:SetText(r.text); text:SetTextColor(AMBER[1], AMBER[2], AMBER[3])
  else text:SetText("") end
end
local function showAnswers()
  for i = 1, visible do showAnswer(rows[i]) end
  updateUse()
end

--[[ The lines into the rows, from offset. ]]
local function bind()
  binding = true
  local L = lines()
  for i = 1, visible do
    local row = rows[i]
    row.line = offset + i
    if row.line <= #L then row.box:SetText(L[row.line]); row:Show()
    else row.box:SetText(""); row:Hide() end
    showAnswer(row)
  end
  for i = visible + 1, #rows do rows[i]:Hide() end
  binding = false
end

--[[ ---- the handlers ---- ]]
function ui.Typed(row, text, user)
  if binding or not row.line or row.line > Napkin.MAX_LINES then return end
  local L = lines()
  while #L < row.line do L[#L + 1] = "" end
  L[row.line] = text
  if user then
    typedAt = now()
    if C_Timer and C_Timer.After then C_Timer.After(ERROR_DELAY + 0.05, function() if win and win:IsShown() then showAnswers() end end) end
  end
  recalc()
  showAnswers()
end

function ui.Focus(line)
  local L = lines()
  line = clamp(line, 1, #L)
  offset = clamp(offset, 0, math.max(0, #L - visible))
  if line <= offset then offset = line - 1 elseif line > offset + visible then offset = line - visible end
  bind()
  local row = rows[line - offset]
  lastLine = line
  if row then row.box:SetFocus(); row.box:SetCursorPosition(#(L[line] or "")) end
  return row
end

function ui.Enter(row)
  local L, line = lines(), row.line
  if not line or line >= Napkin.MAX_LINES then return end
  if line == #L then L[line + 1] = "" end
  return ui.Focus(line + 1)
end

function ui.Move(row, dir) return ui.Focus((row.line or 1) + dir) end

function ui.Remove(row)
  local L = lines()
  if #L <= 1 or not row.line or row.line > #L then return end
  table.remove(L, row.line)
  recalc()
  return ui.Focus(math.max(1, row.line - 1))
end

function ui.Scroll(delta)
  offset = clamp(offset - delta, 0, math.max(0, #lines() - visible))
  bind()
end

--[[ A key types into the row being written, or the pad's last line; = is Enter, C clears the row, << is backspace. ]]
function ui.Key(label)
  local row = focused
  if not row then row = ui.Focus(#lines()) end
  if not row then return end
  if label == "=" then ui.Enter(row); return "\n" end
  if label == "C" then row.box:SetText(""); ui.Typed(row, "", true); return "" end
  if label == "<<" then
    local t, pos = row.box:GetText(), row.box:GetCursorPosition()
    if pos > 0 then
      row.box:SetText(t:sub(1, pos - 1) .. t:sub(pos + 1))
      row.box:SetCursorPosition(pos - 1)
      ui.Typed(row, t:sub(1, pos - 1) .. t:sub(pos + 1), true)
    end
    return "<<"
  end
  local typed = TYPES[label] or label
  row.box:Insert(typed)
  return typed
end

function ui.Copy(row)
  local r = results[row.line]
  if not (r and r.value) then return end
  local text = Napkin.Format(r.value, false)
  win.copy:SetText(text)
  win.copy:Show()
  win.copy:SetFocus()
  win.copy:HighlightText()
  return text
end

function ui.ToChat(row)
  local r = results[row.line]
  if not (r and r.value) then return end
  local text = Napkin.Format(r.value, false)
  if ChatEdit_InsertLink and ChatEdit_InsertLink(text) then return text end
  if ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
  return text
end

function ui.Tooltip(row, owner)
  local r = results[row.line]
  if not (r and (r.value or r.err)) then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if r.err then GameTooltip:SetText(r.err, RED[1], RED[2], RED[3], 1, true)
  else
    GameTooltip:SetText(r.read or "", 1, 1, 1, 1, true)
    local v = r.value
    if v.kind == "money" then
      local c = math.floor(math.abs(v.v) + 0.5)
      GameTooltip:AddLine(Napkin.Number(c / 100) .. " silver, " .. Napkin.Number(c) .. " copper", AMBER[1], AMBER[2], AMBER[3])
    elseif v.kind == "percent" then GameTooltip:AddLine("exactly " .. Napkin.Number(v.v, 6) .. "%", AMBER[1], AMBER[2], AMBER[3])
    else GameTooltip:AddLine("exactly " .. Napkin.Number(v.v, 6), AMBER[1], AMBER[2], AMBER[3]) end
    GameTooltip:AddLine("Click to copy. Shift-click puts it in chat.", DIM[1], DIM[2], DIM[3])
  end
  GameTooltip:Show()
end

function ui.Use()
  local v = currentAnswer()
  if not (lastMoney and v and v.kind == "money" and MoneyInputFrame_SetCopper) then return nil end
  MoneyInputFrame_SetCopper(lastMoney, math.floor(math.max(0, v.v) + 0.5))
  return lastMoney
end

--[[ ---- the window ---- ]]
local function savePlace()
  local db = FA.db.napkin
  db.x, db.y, db.w, db.h = win:GetLeft(), win:GetBottom(), win:GetWidth(), win:GetHeight()
end
local function restorePlace()
  local db = FA.db.napkin
  if tonumber(db.w) and tonumber(db.h) then win:SetSize(math.max(MIN_W, db.w), math.max(MIN_H, db.h)) else win:SetSize(DEFAULT_W, DEFAULT_H) end
  win:ClearAllPoints()
  if tonumber(db.x) and tonumber(db.y) then win:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
  else win:SetPoint("CENTER", UIParent, "CENTER", 220, 0) end
end

--[[ The keys' size from the window's: as big as five rows of them fit the height, no wider than leaves the pad its
     room; the rows from what's left. ]]
local function layout()
  if not win then return end
  local db = FA.db.napkin
  local w, h = win:GetWidth(), win:GetHeight()
  local innerH = h - TITLE_H - FOOT_H - PAD
  local keyW = 0
  if db.keys ~= false then
    local k = math.floor((innerH - 4 * GAP) / 5)
    k = math.min(k, math.floor((w - 2 * PAD - PAD_MIN_W - 10 - 4 * GAP) / 5))
    k = clamp(k, KEY_MIN, KEY_MAX)
    keyW = 5 * k + 4 * GAP
    win.keypad:SetSize(keyW, keyW)
    win.keypad:Show()
    local size = clamp(math.floor(k * 0.46), 10, 26)
    for r = 1, 5 do for c = 1, 5 do
      local key = keys[r][c]
      key:SetSize(k, k)
      key:ClearAllPoints()
      key:SetPoint("TOPLEFT", win.keypad, "TOPLEFT", (c - 1) * (k + GAP), -(r - 1) * (k + GAP))
      setFont(key.text, size)
    end end
    win.keyW = k
  else
    win.keypad:Hide()
    win.keyW = 0
  end
  local padW = math.max(PAD_MIN_W, w - 2 * PAD - (keyW > 0 and keyW + 10 or 0))
  win.pad:SetSize(padW, innerH)
  visible = clamp(math.floor(innerH / ROW_H), 1, Napkin.MAX_LINES)
  local ansW = clamp(math.floor(padW * 0.42), 70, 180)
  for i = 1, visible do
    if not rows[i] then rows[i] = win.makeRow(i) end
    rows[i].ans:SetWidth(ansW)
    rows[i].box:SetPoint("RIGHT", rows[i], "RIGHT", -ansW - 6, 0)
  end
  offset = clamp(offset, 0, math.max(0, #lines() - visible))
  bind()
end
ui.Layout = layout

local function makeRow(i)
  local row = CreateFrame("Frame", nil, win.pad)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", win.pad, "TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetPoint("RIGHT", win.pad, "RIGHT", 0, 0)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetColorTexture(1, 0.8, 0.5, 0.07)
  row.hl:SetAllPoints(row)
  row.hl:Hide()
  local box = CreateFrame("EditBox", nil, row)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal)
  box:SetMaxLetters(200)
  box:SetHeight(ROW_H)
  box:SetPoint("LEFT", row, "LEFT", 4, 0)
  box:SetTextColor(INK[1], INK[2], INK[3])
  box:SetScript("OnTextChanged", function(self, user) ui.Typed(row, self:GetText(), user) end)
  box:SetScript("OnEnterPressed", function() ui.Enter(row) end)
  box:SetScript("OnTabPressed", function() ui.Enter(row) end)
  box:SetScript("OnEscapePressed", function() win:Hide() end)
  box:SetScript("OnArrowPressed", function(_, key) if key == "UP" then ui.Move(row, -1) elseif key == "DOWN" then ui.Move(row, 1) end end)
  box:SetScript("OnKeyDown", function(self, key) if key == "BACKSPACE" and self:GetText() == "" then ui.Remove(row) end end)
  box:SetScript("OnEditFocusGained", function() focused = row; lastLine = row.line or lastLine; row.hl:Show(); updateUse() end)
  box:SetScript("OnEditFocusLost", function() if focused == row then focused = nil end; row.hl:Hide(); showAnswer(row) end)
  row.box = box
  local ans = CreateFrame("Button", nil, row)
  ans:SetHeight(ROW_H)
  ans:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  ans.text = ans:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ans.text:SetAllPoints(ans)
  ans.text:SetJustifyH("RIGHT")
  ans.text:SetWordWrap(false)
  ans:SetScript("OnClick", function() if IsShiftKeyDown and IsShiftKeyDown() then ui.ToChat(row) else ui.Copy(row) end end)
  ans:SetScript("OnEnter", function(self) ui.Tooltip(row, self) end)
  ans:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.ans = ans
  return row
end

local function makeWindow()
  win = CreateFrame("Frame", "ForeverArmouryNapkin", UIParent, TEMPLATE)
  win.makeRow = makeRow
  win:SetBackdrop(BACKDROP)
  win:SetFrameStrata("DIALOG")
  win:SetToplevel(true)
  win:SetMovable(true)
  win:SetResizable(true)
  win:EnableMouse(true)
  win:SetClampedToScreen(true)
  if win.SetResizeBounds then win:SetResizeBounds(MIN_W, MIN_H) elseif win.SetMinResize then win:SetMinResize(MIN_W, MIN_H) end
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", function() win:StartMoving() end)
  win:SetScript("OnDragStop", function() win:StopMovingOrSizing(); savePlace() end)
  win:SetScript("OnSizeChanged", function() layout() end)
  win:SetScript("OnShow", function() recalc(); layout() end)
  win:SetScript("OnHide", function() savePlace(); GameTooltip:Hide() end)
  tinsert(UISpecialFrames, "ForeverArmouryNapkin")   -- Escape closes it

  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", PAD, -14)
  title:SetText("Napkin")
  local sub = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sub:SetPoint("LEFT", title, "RIGHT", 6, 0)
  sub:SetText("the counting engine")

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -5, -5)
  win.keysToggle = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  win.keysToggle:SetSize(50, 18)
  win.keysToggle:SetPoint("RIGHT", close, "LEFT", 2, 0)
  win.keysToggle:SetText("Keys")
  win.keysToggle:SetScript("OnClick", function() FA.db.napkin.keys = FA.db.napkin.keys == false; layout() end)

  win.pad = CreateFrame("Frame", nil, win)
  win.pad:SetPoint("TOPLEFT", PAD, -TITLE_H)
  win.pad:EnableMouseWheel(true)
  win.pad:SetScript("OnMouseWheel", function(_, delta) ui.Scroll(delta) end)

  win.keypad = CreateFrame("Frame", nil, win)
  win.keypad:SetPoint("TOPRIGHT", -PAD, -TITLE_H)
  for r = 1, 5 do
    keys[r] = {}
    for c = 1, 5 do
      local label = KEYS[r][c]
      local key = CreateFrame("Button", nil, win.keypad, "UIPanelButtonTemplate")
      key:SetText(label)
      key.text = key:GetFontString() or key:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      if not DIGIT[label] then key.text:SetTextColor(AMBER[1], AMBER[2], AMBER[3]) end
      key:SetScript("OnClick", function() ui.Key(label) end)
      keys[r][c] = key
    end
  end

  win.use = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  win.use:SetSize(54, 20)
  win.use:SetPoint("BOTTOMLEFT", PAD, 11)
  win.use:SetText("Use")
  win.use:SetScript("OnClick", function() ui.Use() end)
  win.use:SetScript("OnEnter", function(self)
    if not self.why then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.why, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  win.use:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.use:SetMotionScriptsWhileDisabled(true)
  win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.hint:SetPoint("LEFT", win.use, "RIGHT", 8, 0)
  win.hint:SetText("click an answer to copy, shift-click for chat")
  win.live = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.live:SetPoint("BOTTOMRIGHT", -PAD - 16, 15)
  win.live:SetJustifyH("RIGHT")
  win.live:SetTextColor(AMBER[1], AMBER[2], AMBER[3])

  --[[ a one-line box over the hint, where a copied answer sits selected for Ctrl+C ]]
  win.copy = CreateFrame("EditBox", nil, win)
  win.copy:SetAutoFocus(false)
  win.copy:SetFontObject(ChatFontNormal)
  win.copy:SetHeight(20)
  win.copy:SetPoint("LEFT", win.use, "RIGHT", 8, 0)
  win.copy:SetWidth(160)
  win.copy:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:Hide() end)
  win.copy:SetScript("OnEnterPressed", function(self) self:ClearFocus(); self:Hide() end)
  win.copy:SetScript("OnEditFocusLost", function(self) self:Hide() end)
  win.copy:Hide()

  local grip = CreateFrame("Button", nil, win)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -6, 6)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); savePlace(); layout() end)
  win.grip = grip

  restorePlace()
end

function FA.OpenNapkin()
  if not FA.PartOn("napkin") then FA.Print("The Napkin is off. /fa napkin on turns it on."); return false end
  if not win then makeWindow() end
  win:Show()
  recalc()
  layout()
  ui.Focus(#lines())
  return true
end

function FA.ToggleNapkin()
  if win and win:IsShown() then win:Hide() else FA.OpenNapkin() end
end

function FA.ClearNapkin()
  if not FA.PartOn("napkin") then FA.Print("The Napkin is off. /fa napkin on turns it on."); return end
  FA.char.napkin.lines = { "" }
  offset = 0
  if win then recalc(); bind(); if win:IsShown() then ui.Focus(1) end end
  FA.Print("The Napkin is wiped.")
end

--[[ The part's switch: off hides the window and the coin buttons by the money boxes. ]]
function FA.RefreshNapkin()
  local on = FA.PartOn("napkin")
  if win and not on then win:Hide() end
  for _, b in ipairs(coins) do if on then b:Show() else b:Hide() end end
end

--[[ ---- the money boxes: the mail's, the trade window's and the auction house's ----
     Clicking into one makes it where Use puts a money answer, and a coin button beside each opens the Napkin, as
     fermi's calculator icon sits beside its guess box. The auction house loads on demand, so this runs again when it
     has (ForeverArmoury.lua's ADDON_LOADED). ]]
function FA.HookMoneyFrames()
  for _, name in ipairs(MONEY_FRAMES) do
    local f = _G[name]
    if f and not hooked[f] then
      hooked[f] = true
      f.napkinName = MONEY_NAMES[name]
      for _, part in ipairs({ "Gold", "Silver", "Copper" }) do
        local box = _G[name .. part]
        if box and box.HookScript then box:HookScript("OnEditFocusGained", function() lastMoney = f; updateUse() end) end
      end
      local b = CreateFrame("Button", nil, f)
      b:SetSize(16, 16)
      b:SetPoint("LEFT", f, "RIGHT", 2, 0)
      b:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_02")
      b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      b:SetScript("OnClick", function() lastMoney = f; FA.OpenNapkin() end)
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Napkin: work the sum out, then Use puts the answer here.", 1, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      if not FA.PartOn("napkin") then b:Hide() end
      coins[#coins + 1] = b
    end
  end
end

--[[ for the tests: a row, and the window's state ]]
function ui.Row(i) return rows[i] end
function ui.State()
  return { offset = offset, visible = visible, lastLine = lastLine, focused = focused and focused.line or nil, lastMoney = lastMoney and lastMoney.name or nil, keyW = win and win.keyW or nil }
end
