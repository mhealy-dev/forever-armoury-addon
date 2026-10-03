--[[ Forever Armoury, the addon: the site's talent builds in the game (forever-armoury#280, #871).

     This file is the addon's spine: its namespace, its saved variables, the parts that can be turned on and off, the
     /fa command and the game events it listens to. The other files add to the namespace:
       BuildCode.lua   a build code as the site writes it, read and written (FA.Code)
       Talents.lua     the game's talents as three trees of cells, and its talent window (FA.Talents)
       Builds.lua      the saved builds, the character's active one, and where it is on it (FA.Progress)
       TalentUI.lua    the panel beside the talent window, the next-talent highlight, the import box, the settings

     Saved variables: ForeverArmouryDB for the account (every build, by class, and the parts' switches) and
     ForeverArmouryCharDB for the character (which build it follows). ]]

local ADDON, FA = ...
_G.ForeverArmoury = FA

local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
FA.VERSION = meta and meta(ADDON, "Version") or "dev"
--[[ Point n of a build is taken at level n + FIRST_LEVEL - 1: the site's builds start at level 10. A Legacy perk that
     moves the first point earlier (forever-armoury#512) would change this, which is what the code's version number is
     for. ]]
FA.FIRST_LEVEL = 10

--[[ The addon's parts, each with its own switch (FA.PartOn). The level plan is the first; macros and the UI layout
     may follow. A part that is off draws nothing and hooks nothing it can avoid. ]]
FA.PARTS = {
  { key = "plan", name = "Level plan", text = "Your builds beside the talent window, with the next talent to take" },
}

local DEFAULTS = { builds = {}, nextId = 1, parts = { plan = true } }

function FA.Print(text)
  (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffffd100Forever Armoury:|r " .. tostring(text))
end

--[[ The saved variables, with anything a new version added filled in. ]]
function FA.Init()
  ForeverArmouryDB = ForeverArmouryDB or {}
  local db = ForeverArmouryDB
  if type(db.builds) ~= "table" then db.builds = {} end
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
end

--[[ /fa: the panel, the import box, the switches. ]]
local HELP = {
  "/fa  the talent window with your builds beside it",
  "/fa import  paste a build code from the site",
  "/fa export  the code for every build of your class, to paste into the site",
  "/fa list  your builds for this class",
  "/fa plan on|off  the level plan part",
  "/fa options  the addon's settings",
  "/fa debug  every talent by tree, row and column, as the addon reads them",
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
      "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED" }) do pcall(events.RegisterEvent, events, e) end
    if FA.HookTalentFrame then FA.HookTalentFrame() end
    if FA.SetupOptions then FA.SetupOptions() end
  else
    FA.Talents.Forget()
    if FA.Refresh then FA.Refresh() end
  end
end)
