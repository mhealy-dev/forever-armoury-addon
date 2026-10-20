--[[ Forever Armoury, the addon: the site's talent builds in the game (forever-armoury#280, #871).

     This file is the addon's spine: its namespace, its saved variables, the parts that can be turned on and off, the
     /fa command and the game events it listens to. The other files add to the namespace:
       BuildCode.lua   a build code as the site writes it, read and written (FA.Code)
       Talents.lua     the game's talents as three trees of cells, and its talent window (FA.Talents)
       Builds.lua      the saved builds, the character's active one, and where it is on it (FA.Progress)
       TalentUI.lua    the panel beside the talent window, the next-talent highlight, the import box, the settings
       GearCode.lua    a gear route code as the site writes it, read and written (FA.GearCode)
       Gear.lua        the saved gear routes, the character's, and the next pieces at its level (FA.Gear)
       GearUI.lua      the panel beside the character window listing them

     Saved variables: ForeverArmouryDB for the account (every build and gear route, by class, and the parts' switches)
     and ForeverArmouryCharDB for the character (which build it follows, and the spec it chose for its gear route). ]]

local ADDON, FA = ...
_G.ForeverArmoury = FA

local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
FA.VERSION = meta and meta(ADDON, "Version") or "dev"
if FA.VERSION:find("^@") then FA.VERSION = "dev" end   -- a checkout, not a package: @project-version@ unfilled

--[[ Point n of a build is taken at level n + FA.FirstLevel() - 1. The site's builds start at level 10, FIRST_LEVEL;
     the Legacy perk Talented (forever-armoury#512) moves the first point a level earlier for each rank, so the
     character's first level is 10 minus its rank. The perk is a node of the Legacy system's Adventure tree, read from
     the game; a game that won't say counts as no ranks. ]]
FA.FIRST_LEVEL = 10
local LEGACY = Constants and Constants.LegacyConsts or {}
FA.TALENTED_TREE = LEGACY.LEGACY_TREE_ADVENTURE_ID or 1188
FA.TALENTED_NODE = LEGACY.LEGACY_TREE_ADVENTURE_TALENTED_NODE_ID or 110298

--[[ The ranks of Talented the character has, 0 when the game won't say. ]]
function FA.TalentedRank()
  if not (C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetNodeInfo) then return 0 end
  local configID = C_Traits.GetConfigIDByTreeID(FA.TALENTED_TREE)
  local info = configID and C_Traits.GetNodeInfo(configID, FA.TALENTED_NODE)
  local rank = info and tonumber(info.ranksPurchased) or 0
  return math.max(0, math.min(FA.FIRST_LEVEL - 1, rank))
end
function FA.FirstLevel() return FA.FIRST_LEVEL - FA.TalentedRank() end

--[[ The addon's parts, each with its own switch (FA.PartOn). The level plan and the leveling gear are the first;
     BIS lists, macros and the UI layout may follow. A part that is off draws nothing and hooks nothing it can avoid. ]]
FA.PARTS = {
  { key = "plan", name = "Level plan", text = "Your builds beside the talent window, with the next talent to take" },
  { key = "gear", name = "Leveling gear", text = "The site's gear route beside the character window: the pieces to get at your level, and where" },
}

local DEFAULTS = { builds = {}, gear = {}, nextId = 1, parts = { plan = true, gear = true } }

function FA.Print(text)
  (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffffd100Forever Armoury:|r " .. tostring(text))
end

--[[ The saved variables, with anything a new version added filled in. ]]
function FA.Init()
  ForeverArmouryDB = ForeverArmouryDB or {}
  local db = ForeverArmouryDB
  if type(db.builds) ~= "table" then db.builds = {} end
  if type(db.gear) ~= "table" then db.gear = {} end
  if type(db.nextId) ~= "number" then db.nextId = DEFAULTS.nextId end
  if type(db.parts) ~= "table" then db.parts = {} end
  for key, on in pairs(DEFAULTS.parts) do if db.parts[key] == nil then db.parts[key] = on end end
  ForeverArmouryCharDB = ForeverArmouryCharDB or {}
  FA.db, FA.char = db, ForeverArmouryCharDB
end

function FA.PartOn(key) return FA.db and FA.db.parts[key] ~= false end
function FA.SetPart(key, on)
  FA.db.parts[key] = on and true or false
  if FA.Refresh then FA.Refresh() end
  if FA.RefreshGear then FA.RefreshGear() end
end

--[[ /fa: the panel, the import box, the switches. ]]
local HELP = {
  "/fa  the talent window with your builds beside it",
  "/fa import  paste a build code from the site",
  "/fa apply  spend your unspent points as the build you follow says",
  "/fa export  the code for every build of your class, to paste into the site",
  "/fa list  your builds for this class",
  "/fa plan on|off  the level plan part",
  "/fa gear  the character window with your gear route beside it",
  "/fa gear on|off  the leveling gear part",
  "/fa options  the addon's settings",
  "/fa debug  every talent by tree, row and column, as the addon reads them from the game's positions",
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
    for _, b in ipairs(list) do FA.Print((active == b and "> " or "  ") .. b.name .. " (" .. math.floor(#b.picks / 2) .. " points)") end
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
  elseif cmd == "options" or cmd == "settings" then
    if FA.OpenOptions then FA.OpenOptions() end
  elseif cmd == "debug" then
    FA.Talents.Forget()
    for _, line in ipairs(FA.Talents.Dump()) do FA.Print(line) end
  else
    FA.Print("Forever Armoury " .. FA.VERSION)
    for _, line in ipairs(HELP) do FA.Print(line) end
  end
end

--[[ Events: the saved variables once this addon has loaded, the talent window once Blizzard's talent UI has (it
     loads on demand), and the character's points and level as they change. ]]
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then FA.Init()
    elseif FA.Talents.Loaded(arg1) and FA.HookTalentFrame then FA.HookTalentFrame() end
  elseif event == "PLAYER_LOGIN" then
    FA.class = (select(2, UnitClass("player")) or ""):lower()   -- "warrior", as the site names it
    for _, e in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "TRAIT_NODE_CHANGED", "TRAIT_CONFIG_UPDATED",
      "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED", "CONFIG_COMMIT_FAILED", "CONFIRM_TALENT_WIPE" }) do
      pcall(events.RegisterEvent, events, e)
    end
    if FA.HookTalentFrame then FA.HookTalentFrame() end
    if FA.HookCharacterFrame then FA.HookCharacterFrame() end
    if FA.SetupOptions then FA.SetupOptions() end
  elseif event == "CONFIG_COMMIT_FAILED" then
    --[[ The commit is a cast, so the game can turn it down after CommitConfig said yes: what the addon staged is
         rolled back here. A commit of the window's own is the window's to report. ]]
    if FA.Talents.CommitFailed(arg1) then FA.Print("The game didn't apply the talents, so they were rolled back. Nothing was spent.") end
    FA.Talents.Forget()
    if FA.Refresh then FA.Refresh() end
  elseif event == "CONFIRM_TALENT_WIPE" then
    --[[ At a trainer's reset, before it's confirmed: what Apply does after it. The reset itself, and its cost, stay
         the game's own dialog. ]]
    local build = FA.PartOn("plan") and FA.ActiveBuild()
    local points = build and FA.Code.Points(build.picks)
    if points then
      local due = math.min(#points, math.max(0, (UnitLevel("player") or 1) - FA.FirstLevel() + 1))
      FA.Print("After the reset, open your talents and press Apply: it spends " .. due .. (due == 1 and " point" or " points") .. " as " ..
        (build.name ~= "" and build.name or "your build") .. " says.")
    end
  else
    if event == "TRAIT_CONFIG_UPDATED" then FA.Talents.Committed(arg1) end
    FA.Talents.Forget()
    if FA.Refresh then FA.Refresh() end
  end
end)
