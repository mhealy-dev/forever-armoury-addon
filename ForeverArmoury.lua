--[[ Forever Armoury, the addon: the site's talent builds in the game (forever-armoury#280, #871).

     This file is the addon's spine: its namespace, its saved variables, the parts that can be turned on and off, the
     /fa command and the game events it listens to. The other files add to the namespace:
       BuildCode.lua   a build code as the site writes it, read and written (FA.Code)
       Talents.lua     the game's talents as three trees of cells, and its talent window (FA.Talents)
       Builds.lua      the saved builds, the character's active one, and where it is on it (FA.Progress)
       Strip.lua       the strip of icons beside a window, shared by the talent window and the Legacy window, and the highlights in the trees (FA.Strip)
       TalentUI.lua    the panel beside the talent window and its side of the strip, the import box, the settings
       GearCode.lua    a gear route code as the site writes it, read and written (FA.GearCode)
       Data/Routes.lua the gear routes the addon ships, written by tools/routes.py (FA.RouteData)
       Gear.lua        the shipped and the saved gear routes, the character's, and the next pieces at its level (FA.Gear)
       GearUI.lua      the panel beside the character window listing them
       LegacyCode.lua  a Legacy plan code as the site writes it, read and written (FA.LegacyCode)
       Legacy.lua      the account's Legacy plans, where it is on one, and what Apply buys in the three Legacy trees (FA.Legacy)
       LegacyUI.lua    the strip and the panel beside the game's Legacy window listing them
       Napkin.lua      a sum as a person scribbles it, read and answered (FA.Napkin)
       NapkinUI.lua    the Napkin window: the pad, the keys, the key binding, the money boxes

     Saved variables: ForeverArmouryDB for the account (every build and gear route, by class, every Legacy plan, whether the Legacy panel's plan list is open, the parts' switches, and shown, whether each part's panel is out or put away)
     and ForeverArmouryCharDB for the character (which build it follows, whether the panel's build list is open, and the
     spec it chose for its gear route). Besides the parts' switches the account has strip, where the strips start and how big their icons are, and napkin, the
     Napkin window's place and size; the character's napkin holds its pad's lines. ]]

local ADDON, FA = ...
_G.ForeverArmoury = FA

local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
FA.VERSION = meta and meta(ADDON, "Version") or "dev"
if FA.VERSION:find("^@") then FA.VERSION = "dev" end   -- a checkout, not a package: @project-version@ unfilled

--[[ The key binding's names (Bindings.xml), as the game's key bindings window shows them: plain globals, that is
     how the game names a binding. ]]
BINDING_HEADER_FOREVERARMOURY = "Forever Armoury"
BINDING_NAME_FOREVERARMOURY_NAPKIN = "Open the Napkin"

--[[ Point n of a build is taken at level n + FA.FirstLevel() - 1. The site's builds start at level 10, FIRST_LEVEL;
     the Legacy perk Talented (forever-armoury#512) moves the first point a level earlier for each rank, so the
     character's first level is 10 minus its rank. The perk is a node of the Legacy system's Adventure tree, read from
     the game. When the game won't say, the build's own rank is used (a FAT3- code carries it, forever-armoury#1540),
     and 10 when neither is known. ]]
FA.FIRST_LEVEL = 10
local LEGACY = Constants and Constants.LegacyConsts or {}
FA.TALENTED_TREE = LEGACY.LEGACY_TREE_ADVENTURE_ID or 1188
FA.TALENTED_NODE = LEGACY.LEGACY_TREE_ADVENTURE_TALENTED_NODE_ID or 110298

--[[ The ranks of Talented the character has, as the game says, or nil when it won't (no Legacy config, no node, no
     rank in the answer: a 0 the game does give is a 0). ]]
function FA.GameTalentedRank()
  if not (C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetNodeInfo) then return nil end
  local configID = C_Traits.GetConfigIDByTreeID(FA.TALENTED_TREE)
  local info = configID and C_Traits.GetNodeInfo(configID, FA.TALENTED_NODE)
  local rank = info and tonumber(info.ranksPurchased)
  return rank and math.max(0, math.min(FA.FIRST_LEVEL - 1, rank))
end

--[[ The rank of Talented to count levels by, and where it came from: the game's ("game"), else the build's own
     ("build", for a build given and one that knows its rank), else 0 ("none"). ]]
function FA.TalentedRank(build)
  local game = FA.GameTalentedRank()
  if game then return game, "game" end
  local own = build and tonumber(build.talented)
  if own then return math.max(0, math.min(FA.FIRST_LEVEL - 1, own)), "build" end
  return 0, "none"
end
function FA.FirstLevel(build) return FA.FIRST_LEVEL - (FA.TalentedRank(build)) end

--[[ The addon's parts, each with its own switch (FA.PartOn). The level plan, the leveling gear, the Legacy plans and the Napkin are the first;
     BIS lists, macros and the UI layout may follow. A part that is off draws nothing and hooks nothing it can avoid. ]]
FA.PARTS = {
  { key = "plan", name = "Level plan", panel = "the level plan", text = "Your builds beside the talent window, with the next talent to take" },
  { key = "gear", name = "Leveling gear", panel = "the leveling gear", text = "The site's gear route beside the character window: the pieces to get at your level, and where" },
  { key = "legacy", name = "Legacy plans", panel = "the Legacy plan", text = "The site's Legacy plan beside the Legacy window: a strip of its ranks, the perks still to buy, and Apply buying them" },
  { key = "napkin", name = "Napkin", panel = "the Napkin", text = "A small calculator with a scratch pad: gold, percentages, your character's own numbers" },
}

--[[ Where the strips beside the talent window and the Legacy window start their view: the points taken above the next, and the points coming kept in
     view after it. And the size of its icons, in pixels. ]]
FA.STRIP_MAX = { past = 5, coming = 8 }
FA.STRIP_SIZE = { min = 34, max = 56 }
local DEFAULTS = { builds = {}, gear = {}, legacy = {}, nextId = 1, parts = { plan = true, gear = true, legacy = true, napkin = true }, shown = { plan = true, gear = true, legacy = true }, strip = { past = 3, coming = 5, size = 44 } }

function FA.Print(text)
  (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffffd100Forever Armoury:|r " .. tostring(text))
end

--[[ A name as text to draw: a | in it is doubled, so a |c or |H in a build's name shows as typed instead of taking effect. ]]
function FA.Esc(text) return (tostring(text or ""):gsub("|", "||")) end

--[[ A build's name to draw: escaped, and "Unnamed" for none. ]]
function FA.ShownName(build) return build.name ~= "" and FA.Esc(build.name) or "Unnamed" end

--[[ The character's class as the site names it ("warrior"). ]]
function FA.SetClass() FA.class = (select(2, UnitClass("player")) or ""):lower() end

--[[ The saved variables, with anything a new version added filled in. ]]
function FA.Init()
  ForeverArmouryDB = ForeverArmouryDB or {}
  local db = ForeverArmouryDB
  if type(db.builds) ~= "table" then db.builds = {} end
  if type(db.gear) ~= "table" then db.gear = {} end
  if type(db.legacy) ~= "table" then db.legacy = {} end
  if type(db.nextId) ~= "number" then db.nextId = DEFAULTS.nextId end
  if type(db.parts) ~= "table" then db.parts = {} end
  for key, on in pairs(DEFAULTS.parts) do if db.parts[key] == nil then db.parts[key] = on end end
  if type(db.shown) ~= "table" then db.shown = {} end
  for key, on in pairs(DEFAULTS.shown) do if db.shown[key] == nil then db.shown[key] = on end end
  if type(db.strip) ~= "table" then db.strip = {} end
  for key, n in pairs(DEFAULTS.strip) do if type(db.strip[key]) ~= "number" then db.strip[key] = n end end
  --[[ The Napkin window is the account's (its place, its size, whether the keys show); its lines are the
       character's: a list of strings, never empty, never past the pad's limit. ]]
  if type(db.napkin) ~= "table" then db.napkin = {} end
  if db.napkin.keys == nil then db.napkin.keys = true end
  ForeverArmouryCharDB = ForeverArmouryCharDB or {}
  local char = ForeverArmouryCharDB
  if type(char.napkin) ~= "table" then char.napkin = {} end
  local lines, kept = char.napkin.lines, {}
  local most = FA.Napkin and FA.Napkin.MAX_LINES or 60
  if type(lines) == "table" then
    for _, line in ipairs(lines) do if type(line) == "string" and #kept < most then kept[#kept + 1] = line end end
  end
  if #kept == 0 then kept[1] = "" end
  char.napkin.lines = kept
  FA.db, FA.char = db, char
  FA.SetClass()   -- not at PLAYER_LOGIN: an import before it needs the class
  if FA.RepairBuilds then
    local dropped, repaired = FA.RepairBuilds()
    if dropped > 0 or repaired > 0 then
      local said = {}
      if dropped > 0 then said[#said + 1] = "dropped " .. dropped .. (dropped == 1 and " saved build" or " saved builds") .. " it couldn't read" end
      if repaired > 0 then said[#said + 1] = "repaired " .. repaired .. (repaired == 1 and " saved build" or " saved builds") .. " with a missing name or id" end
      FA.Print("Your saved builds were damaged: " .. table.concat(said, ", and ") .. ".")
    end
  end
  if FA.Legacy then
    local dropped, repaired = FA.Legacy.Repair()
    if dropped > 0 or repaired > 0 then
      local said = {}
      if dropped > 0 then said[#said + 1] = "dropped " .. dropped .. (dropped == 1 and " saved Legacy plan" or " saved Legacy plans") .. " it couldn't read" end
      if repaired > 0 then said[#said + 1] = "repaired " .. repaired .. (repaired == 1 and " saved Legacy plan" or " saved Legacy plans") .. " with a missing name, build or id" end
      FA.Print("Your saved Legacy plans were damaged: " .. table.concat(said, ", and ") .. ".")
    end
  end
end

--[[ A strip count from the settings ("past" or "coming"), a whole number within what the strip has room for. ]]
function FA.StripCount(key)
  return math.max(0, math.min(FA.STRIP_MAX[key], math.floor(FA.db.strip[key] + 0.5)))
end

--[[ The size of the strip's icons from the settings, a whole number of pixels from the smallest to the largest. ]]
function FA.StripSize()
  return math.max(FA.STRIP_SIZE.min, math.min(FA.STRIP_SIZE.max, math.floor(FA.db.strip.size + 0.5)))
end

function FA.PartOn(key) return FA.db and FA.db.parts[key] ~= false end

--[[ Whether a part's panel is out, apart from its switch: the button on the part's window puts it away and brings it back
     (forever-armoury#1604), and the choice is the account's, kept across sessions. A panel shows when its part is on, it is
     not put away, and its window is open (FA.PanelWanted is the first two). ]]
function FA.PanelShown(key) return not (FA.db and FA.db.shown and FA.db.shown[key] == false) end
function FA.PanelWanted(key) return FA.PartOn(key) and FA.PanelShown(key) end

function FA.RefreshAll()
  if FA.Refresh then FA.Refresh() end
  if FA.RefreshGear then FA.RefreshGear() end
  if FA.RefreshLegacy then FA.RefreshLegacy() end
  if FA.RefreshNapkin then FA.RefreshNapkin() end
end

--[[ A part on or off. Turning one on brings its panel back if it was put away, so a switch (the options page, /fa gear on)
     always ends with the panel out. ]]
function FA.SetPart(key, on)
  FA.db.parts[key] = on and true or false
  if on then FA.db.shown[key] = true end
  FA.RefreshAll()
end
function FA.SetPanelShown(key, on)
  FA.db.shown[key] = on and true or false
  FA.RefreshAll()
end

--[[ A click on a window's button: a panel that is out is put away and one that is put away comes back; with the part off the
     click turns it on, which shows the panel. ]]
function FA.TogglePanel(key)
  if not FA.PartOn(key) then FA.SetPart(key, true) else FA.SetPanelShown(key, not FA.PanelShown(key)) end
end

--[[ ---- the button on each game window ---- ]]
local BUTTON_SIZE, BUTTON_GAP = 20, 2
local WINDOW_BUTTONS = {}   -- part key -> its button

local function partOf(key) for _, part in ipairs(FA.PARTS) do if part.key == key then return part end end end

--[[ The window's own close button, as the frame names it (Blizzard's frame templates name it CloseButton or
     ClosePanelButton), else the global the older frames are known by (CharacterFrameCloseButton); nil when there is none. ]]
local function closeButtonOf(window)
  local named, name = pcall(function() return window:GetName() end)   -- a read the client refuses is no name
  if not named then name = nil end
  for _, found in ipairs({ window.CloseButton or false, window.ClosePanelButton or false,
    type(name) == "string" and _G[name .. "CloseButton"] or false, type(name) == "string" and _G[name .. "ClosePanelButton"] or false }) do
    if type(found) == "table" and found.SetPoint then return found end
  end
end

local function buttonTip(button)
  GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
  GameTooltip:SetText("Forever Armoury \226\128\148 " .. (FA.PanelWanted(button.key) and "hide " or "show ") .. partOf(button.key).panel, 1, 1, 1)
  GameTooltip:Show()
end

--[[ The button looks lit while the panel is out: a gold wash and gold letters; otherwise a dark square with grey letters. ]]
function FA.SyncWindowButton(key)
  local button = WINDOW_BUTTONS[key]
  if not button then return end
  local lit = FA.PanelWanted(key)
  button.lit:SetShown(lit)
  if lit then button.label:SetTextColor(1, 0.82, 0) else button.label:SetTextColor(0.6, 0.6, 0.6) end
end

--[[ The small square button at the top right of a game window, left of its close button, that puts the part's panel away
     and brings it back. One a part; made when the window is hooked. The addon ships no icon, so it carries "FA". ]]
local function makeWindowButton(key, window)
  local close = closeButtonOf(window)
  local button = CreateFrame("Button", "ForeverArmoury" .. key:sub(1, 1):upper() .. key:sub(2) .. "Button", window)
  button.key = key
  button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  if close then button:SetPoint("RIGHT", close, "LEFT", -BUTTON_GAP, 0) else button:SetPoint("TOPRIGHT", window, "TOPRIGHT", -34, -6) end
  local ok, level = pcall(function() return (close or window):GetFrameLevel() end)
  if ok and type(level) == "number" then button:SetFrameLevel(level + (close and 0 or 10)) end
  button:RegisterForClicks("LeftButtonUp")
  local back = button:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0.06, 0.05, 0.03, 0.85)
  button.lit = button:CreateTexture(nil, "BORDER")
  button.lit:SetAllPoints()
  button.lit:SetColorTexture(1, 0.82, 0, 0.3)
  button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.label:SetPoint("CENTER", 0, 0)
  button.label:SetText("FA")
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  button:GetHighlightTexture():SetBlendMode("ADD")
  button:SetScript("OnEnter", buttonTip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnClick", function(self)
    FA.TogglePanel(self.key)
    if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then buttonTip(self) end   -- the tooltip says what the next click does
  end)
  WINDOW_BUTTONS[key] = button
  FA.SyncWindowButton(key)
  return button
end

--[[ The hooks that make the window's panel come after this, so a client that errors on any of it costs the button and
     nothing else: the error is dropped and there is no button. ]]
function FA.WindowButton(key, window)
  if WINDOW_BUTTONS[key] then return WINDOW_BUTTONS[key] end
  if not (window and partOf(key)) then return nil end
  local ok, button = pcall(makeWindowButton, key, window)
  return ok and button or nil
end

--[[ A sum answered in chat, or why it couldn't be. ]]
function FA.NapkinSay(text)
  local said, err = FA.Napkin.Say(text)
  FA.Print(said and ("Napkin: " .. said) or err)
end

--[[ /fa: the panel, the import box, the switches, the Napkin. ]]
local HELP = {
  "/fa  the talent window with your builds beside it",
  "/fa import  paste a build code from the site",
  "/fa apply  spend your unspent points as the build you follow says",
  "/fa export  the code for every build of your class, to paste into the site",
  "/fa list  your builds for this class",
  "/fa plan on|off  the level plan part",
  "/fa gear  the character window with your gear route beside it",
  "/fa gear on|off  the leveling gear part",
  "/fa legacy  the Legacy window with your Legacy plan beside it",
  "/fa legacy on|off  the Legacy plans part",
  "/fa calc [sum]  the Napkin, a small calculator with a scratch pad; with a sum, its answer in chat",
  "/fa napkin on|off  the Napkin part",
  "/fa options  the addon's settings",
  "/fa debug  every talent by tree, row and column, as the addon reads them from the game's positions",
  "/fa debug nodes  every node of your talent trees as the game gives it, and the tree the addon put it in",
}
SLASH_FOREVERARMOURY1 = "/fa"
SLASH_FOREVERARMOURY2 = "/armoury"
SlashCmdList.FOREVERARMOURY = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "builds" or cmd == "talents" then
    if FA.ToggleTalents then FA.ToggleTalents() end
  elseif cmd == "import" then
    if FA.OpenImport then FA.OpenImport() end
  elseif cmd == "apply" then
    if FA.AskApply then FA.AskApply() end
  elseif cmd == "export" then
    local code = FA.ExportCode and FA.ExportCode()
    if not code then FA.Print("No builds for this class yet. /fa import to paste some in.")
    elseif FA.OpenImport then FA.OpenImport(code) else FA.Print(code) end
  elseif cmd == "list" then
    local list = FA.BuildsFor and FA.BuildsFor(FA.class) or {}
    if #list == 0 then FA.Print("No builds for this class yet. /fa import to paste some in.") end
    local active = FA.ActiveBuild and FA.ActiveBuild()
    for _, b in ipairs(list) do FA.Print((active == b and "> " or "  ") .. FA.ShownName(b) .. " (" .. math.floor(#b.picks / 2) .. " points)") end
  elseif cmd == "plan" then
    local on = rest:lower()
    if on == "on" then FA.SetPart("plan", true) elseif on == "off" then FA.SetPart("plan", false) else FA.SetPart("plan", not FA.PartOn("plan")) end
    FA.Print("Level plan " .. (FA.PartOn("plan") and "on" or "off") .. ".")
  elseif cmd == "gear" then
    local on = rest:lower()
    if on == "on" then FA.SetPart("gear", true); FA.Print("Leveling gear on.")
    elseif on == "off" then FA.SetPart("gear", false); FA.Print("Leveling gear off.")
    elseif not FA.PartOn("gear") then FA.Print("The leveling gear part is off. /fa gear on turns it on.")
    elseif FA.ToggleGear then FA.ToggleGear() end
  elseif cmd == "legacy" then
    local on = rest:lower()
    if on == "on" then FA.SetPart("legacy", true); FA.Print("Legacy plans on.")
    elseif on == "off" then FA.SetPart("legacy", false); FA.Print("Legacy plans off.")
    elseif not FA.PartOn("legacy") then FA.Print("The Legacy plans part is off. /fa legacy on turns it on.")
    elseif FA.ToggleLegacy then FA.ToggleLegacy() end
  elseif cmd == "calc" and rest == "" then
    if FA.OpenNapkin then FA.OpenNapkin() end
  elseif cmd == "napkin" and (rest == "" or rest:lower() == "on" or rest:lower() == "off") then
    local on = rest:lower()
    if on == "on" then FA.SetPart("napkin", true) elseif on == "off" then FA.SetPart("napkin", false) else FA.SetPart("napkin", not FA.PartOn("napkin")) end
    FA.Print("Napkin " .. (FA.PartOn("napkin") and "on" or "off") .. ".")
  elseif cmd == "calc" or cmd == "napkin" then   -- with a sum: its answer in chat
    FA.NapkinSay(rest)
  elseif cmd == "options" or cmd == "settings" then
    if FA.OpenOptions then FA.OpenOptions() end
  elseif cmd == "debug" and rest:lower() == "nodes" then
    for _, line in ipairs(FA.Talents.DumpNodes()) do FA.Print(line) end
  elseif cmd == "debug" then
    FA.Talents.Forget()
    for _, line in ipairs(FA.Talents.Dump()) do FA.Print(line) end
    local active = FA.ActiveBuild and FA.ActiveBuild()
    local rank, from = FA.TalentedRank(active)
    FA.Print("Talented rank " .. rank .. ", " .. (from == "game" and "read from the game" or
      from == "build" and ("the build " .. FA.ShownName(active) .. "'s own: the game won't say") or
      "neither the game nor a build says") .. "; the first point comes at level " .. FA.FirstLevel(active) .. ".")
  else
    FA.Print("Forever Armoury " .. FA.VERSION)
    for _, line in ipairs(HELP) do FA.Print(line) end
  end
end

--[[ /napkin: the window on its own, a sum answered in chat, the pad wiped, the words the sums know. ]]
SLASH_FOREVERNAPKIN1 = "/napkin"
SlashCmdList.FOREVERNAPKIN = function(msg)
  local text = (msg or ""):match("^%s*(.-)%s*$")
  local word = text:lower()
  if word == "" then
    if FA.ToggleNapkin then FA.ToggleNapkin() end
  elseif word == "clear" then
    if FA.ClearNapkin then FA.ClearNapkin() end
  elseif word == "words" then
    FA.Print("The Napkin's words:")
    for _, w in ipairs(FA.Napkin.WORDS) do FA.Print(w[1] .. ": " .. w[2]) end
  else
    FA.NapkinSay(text)
  end
end

--[[ The trainer's reset: once it's accepted, what Apply does after it. The reset itself, and its cost, stay the game's
     own dialog, Blizzard's CONFIRM_TALENT_WIPE popup; this is hooked after the popup's OnAccept, so a cancelled dialog
     says nothing. ]]
function FA.TrainerReset()
  local build = FA.PartOn("plan") and FA.ActiveBuild()
  local due = build and FA.PointsAfterReset(build)
  if due then
    FA.Print("After the reset, open your talents and press Apply: it spends " .. due .. (due == 1 and " point" or " points") .. " as " ..
      (build.name ~= "" and FA.Esc(build.name) or "your build") .. " says.")
  end
end
function FA.HookWipe()
  local dialog = StaticPopupDialogs and StaticPopupDialogs.CONFIRM_TALENT_WIPE
  if not (dialog and type(dialog.OnAccept) == "function" and hooksecurefunc) then
    FA.Print("The trainer's reset dialog (CONFIRM_TALENT_WIPE) isn't there, so the addon won't say what Apply spends after a reset.")
    return
  end
  hooksecurefunc(dialog, "OnAccept", FA.TrainerReset)
end

--[[ The panel redraws once a frame however many events come: a burst of TRAIT_NODE_CHANGED while points are staged, or
     one event after another at a login. What's cached is dropped at once, so a read in between asks the game. ]]
local refreshing
function FA.RefreshSoon()
  FA.Talents.Forget()
  if refreshing then return end
  if not (C_Timer and C_Timer.After) then
    if FA.Refresh then FA.Refresh() end
    if FA.RefreshLegacy then FA.RefreshLegacy() end
    return
  end
  refreshing = true
  C_Timer.After(0, function()
    refreshing = false
    if FA.Refresh then FA.Refresh() end
    if FA.RefreshLegacy then FA.RefreshLegacy() end
  end)
end

--[[ Events: the saved variables once this addon has loaded, the talent window once Blizzard's talent UI has (it
     loads on demand), the Napkin's money boxes once the auction house has, and the character's points, level and combat
     as they change. A name the game doesn't know is
     said in chat, since registering it fails without a word. ]]
local EVENTS = { "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "TRAIT_NODE_CHANGED", "TRAIT_CONFIG_UPDATED",
  "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "CHARACTER_POINTS_CHANGED", "CONFIG_COMMIT_FAILED",
  "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then FA.Init()
    elseif arg1 == "Blizzard_AuctionUI" or arg1 == "Blizzard_AuctionHouseUI" then
      if FA.HookMoneyFrames then FA.HookMoneyFrames() end
    elseif FA.Talents.Loaded(arg1) and FA.HookTalentFrame then FA.HookTalentFrame()
    elseif FA.Legacy.Loaded(arg1) and FA.HookLegacyFrame then FA.HookLegacyFrame() end
  elseif event == "PLAYER_LOGIN" then
    for _, e in ipairs(EVENTS) do
      if not pcall(events.RegisterEvent, events, e) then FA.Print("The game has no event " .. e .. ", so the addon won't hear it.") end
    end
    FA.HookWipe()
    if FA.HookTalentFrame then FA.HookTalentFrame() end
    if FA.HookCharacterFrame then FA.HookCharacterFrame() end
    if FA.HookLegacyFrame then FA.HookLegacyFrame() end
    if FA.SetupOptions then FA.SetupOptions() end
    if FA.HookMoneyFrames then FA.HookMoneyFrames() end
  elseif event == "CONFIG_COMMIT_FAILED" then
    --[[ The commit is a cast, so the game can turn it down after CommitConfig said yes: what the addon staged is
         rolled back here. A commit of the window's own is the window's to report. ]]
    if FA.Talents.CommitFailed(arg1) then FA.Print("The game didn't apply the talents, so they were rolled back. Nothing was spent.") end
    if FA.Legacy.CommitFailed(arg1) then FA.Print("The game didn't apply the Legacy perks, so they were rolled back. Nothing was bought.") end
    FA.RefreshSoon()
  else
    if event == "TRAIT_CONFIG_UPDATED" then
      FA.Talents.Committed(arg1); FA.Legacy.Committed(arg1)
      if FA.StripFollow then FA.StripFollow() end
    end
    FA.RefreshSoon()
  end
end)
