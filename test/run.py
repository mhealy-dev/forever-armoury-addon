"""Checks the addon's pure parts, BuildCode.lua, Talents.lua, Builds.lua, GearCode.lua, Gear.lua, LegacyCode.lua and
Legacy.lua, in a Lua runtime with the game's talent, Legacy, item and bag APIs stubbed: a build code, a gear route code and
a Legacy plan code read and written, the game's trait nodes turned into trees of cells, the next-talent walk over a made-up
talent tree, the next pieces of a gear route against what the character wears and carries, and a Legacy plan bought across
the three Legacy trees' configs. Run with `python test/run.py` (needs `pip install lupa`). The game's Lua
is 5.1; LuaJIT's is used when lupa has it, else lupa's default."""
import locale
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def runtime():
    for name in ("luajit21", "luajit20", "lua51", "lua54"):
        try:
            mod = __import__("lupa." + name, fromlist=["LuaRuntime"])
            return mod.LuaRuntime(unpack_returned_tuples=True), name
        except ImportError:
            pass
    from lupa import LuaRuntime
    return LuaRuntime(unpack_returned_tuples=True), "default"


# The game, as much of it as these files touch. TREE[tab][index] = { name, tier, column, rank, max }: a few talents of a
# warrior, served two ways, as the Forever client's trait nodes (C_Traits) and as the old API (GetTalentInfo).
STUB = r"""
TREE = {
  { { "Deflection", 1, 2, 0, 5 }, { "Improved Heroic Strike", 1, 3, 0, 3 }, { "Tactical Mastery", 2, 1, 0, 5 }, { "Anger Management", 2, 3, 0, 1 }, { "Sweeping Strikes", 3, 4, 0, 1 } },
  { { "Booming Voice", 1, 2, 0, 5 }, { "Cruelty", 1, 3, 0, 5 } },   -- nothing in its first column: its origin comes from the full trees' spacing
  { { "Shield Specialization", 1, 2, 0, 5 }, { "Anticipation", 1, 3, 0, 5 }, { "Toughness", 2, 1, 0, 5 }, { "Last Stand", 3, 4, 0, 1 } },
}
TREE_NAMES = { "Arms", "Fury", "Protection" }
PLAYER = { level = 60, class = "WARRIOR" }
API = "traits"   -- or "legacy"

-- the old API
function GetNumTalentTabs() if API ~= "legacy" then return nil end return #TREE end
function GetNumTalents(t) return #TREE[t] end
function GetTalentTabInfo(t) return TREE_NAMES[t], "icon" end
function GetTalentInfo(t, i)
  local x = TREE[t] and TREE[t][i]
  if not x then return nil end
  return x[1], "icon", x[2], x[3], x[4], x[5], false, true
end

-- the trait system: node ids 101.., placed on a grid, each tree's own: GRID[tab] = { x of column 1, column pitch, y of
-- tier 1, row pitch }, by default 600 apart and trees 4000 apart. The second tree is listed first so the group order
-- comes from orderIndex, not the list. EXTRA(tab, posX, posY, name) adds a node off the talent list, as a misplaced one.
NODES, DEFS = {}, {}
function NODES_FROM(grid)
  NODES, DEFS = {}, {}
  local id = 100
  for t, tab in ipairs(TREE) do for i, x in ipairs(tab) do
    id = id + 1
    local g = grid and grid[t] or { (t - 1) * 4000 + 300, 600, 1500, 600 }
    NODES[id] = { tab = t, talent = x, posX = g[1] + (x[3] - 1) * g[2], posY = g[3] + (x[2] - 1) * g[4] }
    DEFS[id] = { spellID = id * 10, overrideName = nil }
  end end
end
NODES_FROM()
function EXTRA(tab, posX, posY, name)
  local id = 900
  while NODES[id] do id = id + 1 end
  NODES[id] = { tab = tab, talent = { name, 1, 1, 0, 1 }, posX = posX, posY = posY }
  DEFS[id] = { spellID = id * 10 }
  return id
end
-- Config 7 is the active spec: its committed ranks are TREE's, and STAGED holds what's bought but not applied. Config 8
-- is the other spec (dual spec), its ranks in OTHER. A rank can be bought with a point to spend, below the talent's
-- max, and with (tier - 1) * 5 points already in its tree, as the game's trees gate them. Config 99 is the Legacy
-- Adventure tree (1188), where TALENTED is the rank of Talented (node 110298); false, and the game won't say.
-- FAIL_COMMIT: true, CommitConfig says no; "late", it starts the cast and the test fails it with CONFIG_COMMIT_FAILED;
-- "now", the game fails it inside the call. NO_ACTIVE: GetActiveConfigID answers nil, as it can early on. NO_CHANGE:
-- why CanChangeTalents says no once something is staged (it says no before, as the client's docs say).
STAGED, OTHER, LOG = {}, {}, {}
SPEC = { active = 1, groups = 1 }
COMBAT, FAIL_COMMIT, NO_ACTIVE, NO_CHANGE, TALENTED, BONUS = false, false, false, false, 0, 0   -- BONUS: points the game gives that the level doesn't
local function rankOf(configID, nodeID)
  if configID == 8 then return OTHER[nodeID] or 0 end
  return NODES[nodeID].talent[4] + (STAGED[nodeID] or 0)
end
local function spentIn(configID, tab)
  local s = 0
  for id, n in pairs(NODES) do if not tab or n.tab == tab then s = s + rankOf(configID, id) end end
  return s
end
function UNSPENT() return math.max(0, PLAYER.level - 9 + (TALENTED or 0)) + BONUS - spentIn(7) end
C_ClassTalents = {
  GetActiveConfigID = function() if API ~= "traits" or NO_ACTIVE then return nil end return SPEC.active == 1 and 7 or 8 end,
  CommitConfig = function(saved)
    LOG[#LOG + 1] = "commit"
    if FAIL_COMMIT == "late" then return true end
    if FAIL_COMMIT == "now" then ON_EVENT(nil, "CONFIG_COMMIT_FAILED", 7); return true end
    if FAIL_COMMIT then return false end
    for id, n in pairs(STAGED) do NODES[id].talent[4] = NODES[id].talent[4] + n end
    STAGED = {}
    return true
  end,
  CanChangeTalents = function()
    if next(STAGED) == nil then return false, false, nil end
    if NO_CHANGE then return false, false, NO_CHANGE end
    return true, true, nil
  end,
}
C_SpecializationInfo = {
  GetActiveSpecGroup = function() return SPEC.active end,
  GetCombatConfigIDForSpecGroup = function(g) if API ~= "traits" then return nil end return g == 1 and 7 or 8 end,
}
function GetNumSpecGroups() return SPEC.groups end
function InCombatLockdown() return COMBAT end
C_Traits = {
  GetConfigInfo = function(configID) return { ID = configID, treeIDs = { 55 }, name = "Primary" } end,
  GetConfigIDByTreeID = function(treeID) if treeID == 1188 and TALENTED then return 99 end return nil end,
  GetGroupDisplayInfoByTreeID = function(treeID)
    return { { groupID = 20, orderIndex = 2, displayName = "Fury", icon = 2 }, { groupID = 10, orderIndex = 1, displayName = "Arms", icon = 1 }, { groupID = 30, orderIndex = 3, displayName = "Protection", icon = 3 } }
  end,
  GetTreeNodes = function(treeID) local ids = {} for k in pairs(NODES) do ids[#ids + 1] = k end table.sort(ids) return ids end,
  GetNodeInfo = function(configID, nodeID)
    if configID == 99 then return nodeID == 110298 and { ID = nodeID, ranksPurchased = TALENTED, maxRanks = 5 } or nil end
    local n = NODES[nodeID]
    return { ID = nodeID, posX = n.posX, posY = n.posY, groupIDs = { n.tab * 10 }, entryIDs = { nodeID * 2 }, ranksPurchased = rankOf(configID, nodeID), maxRanks = n.talent[5] }
  end,
  GetEntryInfo = function(configID, entryID) return { definitionID = entryID / 2, maxRanks = NODES[entryID / 2].talent[5] } end,
  GetDefinitionInfo = function(defID) return DEFS[defID] end,
  GetTreeCurrencyInfo = function(configID, treeID, excludeStaged) return { { traitCurrencyID = 1, quantity = UNSPENT(), spent = spentIn(7) } } end,
  ConfigHasStagedChanges = function(configID) return next(STAGED) ~= nil end,
  PurchaseRank = function(configID, nodeID)
    local n = NODES[nodeID]
    local ok = configID == 7 and UNSPENT() > 0 and rankOf(7, nodeID) < n.talent[5] and spentIn(7, n.tab) >= (n.talent[2] - 1) * 5
    LOG[#LOG + 1] = (ok and "buy " or "refused ") .. n.talent[1]
    if ok then STAGED[nodeID] = (STAGED[nodeID] or 0) + 1 end
    return ok
  end,
  RollbackConfig = function(configID) LOG[#LOG + 1] = "rollback"; STAGED = {} end,
}
-- The Legacy trees (account-wide): with LEGACY_ON, GetConfigIDByTreeID gives trees 1187, 1188 and 1189 configs 201, 202
-- and 203, whose nodes are the 27 perks (structure from the addon's own table). LEG[node] is a perk's committed rank,
-- LSTAGED[config][node] what's bought and not applied, LPOINTS the points available (nil: the game says nothing) and
-- LCAP the most that can be spent in all. A rank is bought as the game's rules have it: not a locked perk, not past the
-- perk's max, its prerequisite full first, its need of points on the tree's other perks met (unless begun), a point to
-- spend (staged ones count), under the cap. LREFUSE is a node the game turns down; LFAIL_COMMIT is false, or true (the
-- commit says no), or "late" (it starts the cast, the test fails it with CONFIG_COMMIT_FAILED), or "now" (the game fails
-- it inside the call), or a config's number for that tree's commit alone.
LEGACY_ON, LEG, LSTAGED, LPOINTS, LCAP, LREFUSE, LFAIL_COMMIT = false, {}, {}, 16, 16, nil, false
LCONFIG = { [1187] = 201, [1188] = 202, [1189] = 203 }
LTREE = { [201] = 1187, [202] = 1188, [203] = 1189 }
local base = {}
for k, v in pairs(C_Traits) do base[k] = v end
local function perkOf(configID, nodeID)
  for i, p in ipairs(FA.Legacy.PERKS) do if p.node == nodeID and p.tree == LTREE[configID] then return p, i end end
end
local function lrank(configID, nodeID) return (LEG[nodeID] or 0) + ((LSTAGED[configID] or {})[nodeID] or 0) end
local function lstaged() local n = 0 for _, st in pairs(LSTAGED) do for _, k in pairs(st) do n = n + k end end return n end
local function lspent() local n = 0 for _, k in pairs(LEG) do n = n + k end return n + lstaged() end
function LAVAILABLE() return LPOINTS and (LPOINTS - lstaged()) end
function C_Traits.GetConfigIDByTreeID(treeID) if LEGACY_ON and LCONFIG[treeID] then return LCONFIG[treeID] end return base.GetConfigIDByTreeID(treeID) end
function C_Traits.GetNodeInfo(configID, nodeID)
  if not LTREE[configID] then return base.GetNodeInfo(configID, nodeID) end
  local p = perkOf(configID, nodeID)
  return p and { ID = nodeID, ranksPurchased = lrank(configID, nodeID), maxRanks = p.max } or nil
end
function C_Traits.GetTreeCurrencyInfo(configID, treeID, excludeStaged)
  if not LTREE[configID] then return base.GetTreeCurrencyInfo(configID, treeID, excludeStaged) end
  if not LPOINTS then return {} end
  return { { traitCurrencyID = 4225, quantity = LAVAILABLE(), maxQuantity = LCAP, spentInTree = 0 } }
end
function C_Traits.ConfigHasStagedChanges(configID)
  if not LTREE[configID] then return base.ConfigHasStagedChanges(configID) end
  return next(LSTAGED[configID] or {}) ~= nil
end
function C_Traits.PurchaseRank(configID, nodeID)
  if not LTREE[configID] then return base.PurchaseRank(configID, nodeID) end
  local p, i = perkOf(configID, nodeID)
  local ok = p and not p.locked and nodeID ~= LREFUSE and lrank(configID, nodeID) < p.max and (LAVAILABLE() or 1) > 0 and lspent() < LCAP
  if ok and p.afterIndex then ok = lrank(configID, FA.Legacy.PERKS[p.afterIndex].node) >= FA.Legacy.PERKS[p.afterIndex].max end
  if ok and p.need > 0 and lrank(configID, nodeID) == 0 then
    local others = 0
    for _, q in ipairs(FA.Legacy.PERKS) do if q.tree == p.tree and q ~= p then others = others + lrank(configID, q.node) end end
    ok = others >= p.need
  end
  LOG[#LOG + 1] = (ok and "buy " or "refused ") .. (p and p.name or nodeID)
  if ok then LSTAGED[configID] = LSTAGED[configID] or {}; LSTAGED[configID][nodeID] = (LSTAGED[configID][nodeID] or 0) + 1 end
  return ok
end
function C_Traits.RollbackConfig(configID)
  if not LTREE[configID] then return base.RollbackConfig(configID) end
  LOG[#LOG + 1] = "rollback " .. LTREE[configID]
  LSTAGED[configID] = nil
end
function C_Traits.CommitConfig(configID)
  LOG[#LOG + 1] = "commit " .. tostring(LTREE[configID] or configID)
  if LFAIL_COMMIT == "late" then return true end
  if LFAIL_COMMIT == "now" then ON_EVENT(nil, "CONFIG_COMMIT_FAILED", configID); return true end
  if LFAIL_COMMIT == true or LFAIL_COMMIT == configID then return false end
  for node, n in pairs(LSTAGED[configID] or {}) do LEG[node] = (LEG[node] or 0) + n; LPOINTS = LPOINTS and (LPOINTS - n) end
  LSTAGED[configID] = nil
  return true
end
-- a plan's ranks from perk names: LRANKS{ ["Master Chef"] = 1, ... } as the code's 27 characters
function LPLAN(byName)
  local out = {}
  for i, p in ipairs(FA.Legacy.PERKS) do out[i] = string.format("%d", byName[p.name] or 0) end
  return table.concat(out)
end
-- the account's ranks, by name, committed
function LSET(byName) for _, p in ipairs(FA.Legacy.PERKS) do if byName[p.name] then LEG[p.node] = byName[p.name] end end end
function LRANKSOF(name) for _, p in ipairs(FA.Legacy.PERKS) do if p.name == name then return LEG[p.node] or 0 end end end

C_Spell = { GetSpellName = function(spellID) return NODES[spellID / 10].talent[1] end, GetSpellTexture = function(spellID) return spellID end }

function UnitLevel() return PLAYER.level end
function GetBuildInfo() return "1.60.1.70170", "70170", "Oct  2 2026", 16001 end   -- the build a code carries (#1215)
function UnitClass() return "Warrior", PLAYER.class end
-- the character's side, what it wears (EQUIPPED[slot] = item id) and carries (BAGS[bag][slot] = item id), and the items
-- the game has loaded: ITEMS[id] = { name, equip location }; one it hasn't is nil from GetItemInfo, as in the game
FACTION, EQUIPPED, BAGS, ITEMS = "Alliance", {}, {}, {}
function UnitFactionGroup() return FACTION end
function GetInventoryItemID(unit, slot) return EQUIPPED[slot] end
C_Container = {
  GetContainerNumSlots = function(bag) return BAGS[bag] and 16 or 0 end,
  GetContainerItemID = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
}
function GetItemInfo(id)
  local x = ITEMS[id]
  if not x then return nil end
  return x[1], "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. x[1] .. "]|h|r", 1, 10, 10, "Armor", "Plate", 1, x[2]
end
-- the addon's event frame: ON_EVENT is its handler, for the tests to send it the game's events. REGISTERED are the events
-- it asked for, and BAD_EVENTS the names this game would refuse, as it does an event it doesn't have (an error).
REGISTERED, BAD_EVENTS = {}, {}
function CreateFrame()
  return {
    RegisterEvent = function(_, e) if BAD_EVENTS[e] then error('Attempt to register unknown event "' .. e .. '"') end REGISTERED[e] = true end,
    SetScript = function(_, k, fn) if k == "OnEvent" then ON_EVENT = fn end end,
  }
end
function EVENT(name, ...) ON_EVENT(nil, name, ...) end
-- C_Timer.After(0, fn) is queued for FLUSH() to run, as the next frame would
TIMERS = {}
C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end }
function FLUSH() local t = TIMERS; TIMERS = {}; for _, fn in ipairs(t) do fn() end end
-- hooksecurefunc(name, hook) for a global or (table, name, hook): the hook runs after the function
function hooksecurefunc(a, b, c)
  local tbl, name, hook = _G, a, b
  if type(a) == "table" then tbl, name, hook = a, b, c end
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig(...) }; hook(...); return unpack(r) end
end
StaticPopupDialogs = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) PRINTED = (PRINTED or "") .. text .. "\n" end }
FA = {}
local function file(name)
  local f = assert(io.open(ROOT .. "/" .. name, "rb")); local src = f:read("*a"); f:close()
  local chunk = assert((loadstring or load)(src, "@" .. name))
  return chunk("ForeverArmoury", FA)
end
file("ForeverArmoury.lua")
file("BuildCode.lua")
file("Talents.lua")
file("Builds.lua")
file("GearCode.lua")
file("Gear.lua")
file("LegacyCode.lua")
file("Legacy.lua")
ForeverArmouryDB, ForeverArmouryCharDB = nil, nil
FA.Init()
FA.class = "warrior"
function RESET(api)
  FLUSH()
  API = api or "traits"
  ForeverArmouryDB, ForeverArmouryCharDB = nil, nil; FA.Init(); FA.Talents.Forget(); PLAYER.level = 60
  for _, tab in ipairs(TREE) do for _, t in ipairs(tab) do t[4] = 0 end end
  NODES_FROM()
  STAGED, OTHER, LOG, PRINTED = {}, {}, {}, ""
  SPEC.active, SPEC.groups, COMBAT, FAIL_COMMIT, NO_ACTIVE, NO_CHANGE, TALENTED, BONUS = 1, 1, false, false, false, false, 0, 0
  REGISTERED, BAD_EVENTS = {}, {}
  FACTION, EQUIPPED, BAGS, ITEMS = "Alliance", {}, {}, {}
  LEGACY_ON, LEG, LSTAGED, LPOINTS, LCAP, LREFUSE, LFAIL_COMMIT = false, {}, {}, 16, 16, nil, false
end
-- a node's id by tree and talent index, for setting OTHER
function NODE(tab, index) for id, n in pairs(NODES) do if n.tab == tab and n.talent == TREE[tab][index] then return id end end end
"""


class Lua:
    def __init__(self):
        self.lua, self.flavour = runtime()
        self.lua.globals().ROOT = ROOT.replace("\\", "/")
        self.lua.execute(STUB)

    def eval(self, src):
        return self.lua.eval(src)

    def run(self, src):
        return self.lua.execute(src)


L = Lua()
PICKS = "0101010202021c1c"   # eight well-formed points; the code reader checks their shape, not the trees


class BuildCode(unittest.TestCase):
    def read(self, text):
        return L.eval("function(t) local b, e, n = FA.Code.Read(t); return b, e, n end")(text)

    def builds(self, text):
        b, e, n = self.read(text)
        self.assertIsNone(e, text)
        return [(x.cls, x.name, x.picks) for x in b.values()], list(n.values())

    def test_writes_and_reads_back(self):
        write = L.eval("function(cls, name, picks) return FA.Code.Write({ { cls = cls, name = name, picks = picks } }) end")
        self.assertEqual(write("warrior", "Arms PvP", PICKS), "FAT3-70170-warrior-Arms%20PvP-" + PICKS + "-0")
        self.assertEqual(write("mage", "", "0a"), "FAT3-70170-mage--0a-0")
        for name in ["Arms PvP", "", "Mage's build, 31/0/20!", "Ünïcödé 🙂 名前", "a" * 40, "50% crit", "-leading-dashes-", "dots.in.name", "  Two   words "]:
            code = write("warrior", name, PICKS)
            self.assertRegex(code, r"^FAT3-70170-warrior-[A-Za-z0-9%]*-[0-9a-r]+-[0-5]$")
            builds, notes = self.builds(code)
            self.assertEqual(builds, [("warrior", " ".join(name.split()), PICKS)], name)
            self.assertEqual(notes, [])

    def test_several_builds_and_codes_in_a_text(self):
        two = "FAT2-70170-warrior-Arms%20PvP-" + PICKS + ".warrior-Fury-1a1a1b"
        self.assertEqual(self.builds(two)[0], [("warrior", "Arms PvP", PICKS), ("warrior", "Fury", "1a1a1b")])
        for pasted in [two, "  " + two + "\n", "`" + two + "`", "here: " + two + ". Enjoy!", "<" + two + ">", "\"" + two + "\"", "**" + two + "**"]:
            self.assertEqual(len(self.builds(pasted)[0]), 2, pasted)
        both = "FAT2-70170-warrior-A-0a and FAT1-mage-B-1b"   # a code from before the build was written in reads too
        self.assertEqual(self.builds(both)[0], [("warrior", "A", "0a"), ("mage", "B", "1b")])

    def test_empty_builds(self):
        self.assertEqual(self.builds("FAT2-70170-warrior-Empty-.warrior-Fury-1a1a1b"), ([("warrior", "Fury", "1a1a1b")], ["Left out a build with no talent points."]))
        self.assertEqual(self.read("FAT2-70170-warrior-Empty-")[1], "That build has no talent points.")
        self.assertEqual(self.read("FAT2-70170-warrior-A-.warrior-B-")[1], "Those builds have no talent points.")

    def test_the_build_a_code_is_from(self):
        build = L.eval("function(t) local b = assert(FA.Code.Read(t)); return b[1].build end")
        self.assertEqual(build("FAT2-70170-warrior-A-0a"), 70170)
        self.assertEqual(build("FAT2-70009-warrior-A-0a"), 70009)
        self.assertIsNone(build("FAT1-warrior-A-0a"))

    def test_write_with_a_build(self):
        write = L.eval("function(build) return FA.Code.Write({ { cls = 'warrior', name = 'A', picks = '0a' } }, build) end")
        self.assertEqual(write(70009), "FAT3-70009-warrior-A-0a-0")
        self.assertEqual(write(None), "FAT3-70170-warrior-A-0a-0")   # the game's
        self.assertEqual(write(False), "FAT3-0-warrior-A-0a-0")      # from before codes carried one: build 0, which reads as none

    def test_names_encode_the_same_under_every_locale(self):
        # %w follows the C locale, and under a UTF-8 one takes bytes above 127 for letters: Python sets LC_CTYPE from
        # the environment at start, so a run without LC_ALL=C has one. Each UTF-8 locale this machine has is tried.
        write = L.eval("function(name) return FA.Code.Write({ { cls = 'warrior', name = name, picks = '0a' } }) end")
        before = locale.setlocale(locale.LC_CTYPE)
        tried = []
        try:
            for name in ["C", "en_US.UTF-8", "C.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8", "ja_JP.UTF-8"]:
                try:
                    locale.setlocale(locale.LC_CTYPE, name)
                except locale.Error:
                    continue
                tried.append(name)
                self.assertEqual(write("Ünï 名"), "FAT3-70170-warrior-%C3%9Cn%C3%AF%20%E5%90%8D-0a-0", name)
                builds, _ = self.builds("FAT2-70170-warrior-A-0a—and more")   # a code with a dash of another script after it
                self.assertEqual(builds, [("warrior", "A", "0a")], name)
        finally:
            locale.setlocale(locale.LC_CTYPE, before)
        self.assertIn("C", tried)

    def test_errors(self):
        def say(text):
            b, e, _ = self.read(text)
            self.assertIsNone(b, text)
            return e
        self.assertIn("Paste a build code", say(""))
        self.assertIn("Paste a build code", say("  \n"))
        self.assertIn("isn't a build code", say("hello there"))
        self.assertIn("isn't a build code", say("FAT-warrior-Arms-0a"))
        self.assertIn("isn't a build code", say("FAT0-warrior-Arms-0a"))
        self.assertIn("newer version", say("FAT4-70170-warrior-Arms-0a-0"))
        for bad in ["FAT2-", "FAT2-70170", "FAT2-warrior-Arms-0a", "FAT2-x-warrior-Arms-0a"]:
            self.assertRegex(say(bad), r"doesn't read", bad)
        for bad in ["FAT2-70170-warrior", "FAT2-70170-warrior-Arms", "FAT2-70170-knight-Arms-0a", "FAT2-70170-warrior-Arms-0a0", "FAT2-70170-warrior-Arms-3a", "FAT2-70170-warrior-Arms-0z", "FAT2-70170-warrior-Arms-" + "0a" * 52, "FAT1-", "FAT1-knight-Arms-0a"]:
            self.assertRegex(say(bad), r"Build 1 .* doesn't read", bad)
        self.assertRegex(say("FAT2-70170-warrior-Arms-0a.warrior-Fury"), r"Build 2 .* doesn't read")
        self.assertRegex(say("FAT2-70170-warrior-Arms-0a..warrior-Fury-1a"), r"Build 2")
        for bad in ["FAT2-70170-warrior-Ar%2-0a", "FAT2-70170-warrior-Ar%ZZms-0a"]:
            self.assertRegex(say(bad), r"name of build 1 .* cut off", bad)

    # ---- parity with the site's reader (public/content/build-code.js, test/build-code.test.cjs in forever-armoury)
    def test_a_long_name_is_cut_to_40_characters_with_a_note(self):
        cut = L.eval("function(t) local b, e, n = FA.Code.Read(t); return b[1].name, n[1], #n end")
        name, note, count = cut("FAT2-70170-rogue-" + "a" * 50 + "-0a")
        self.assertEqual((name, note, count), ("a" * 40, "The name of build 1 was cut to 40 characters.", 1))
        # forty characters stay as they are, with no note
        self.assertEqual(cut("FAT2-70170-rogue-" + "a" * 40 + "-0a"), ("a" * 40, None, 0))
        # characters, not bytes: 50 of a two-byte one, and of a three-byte one, cut between characters
        self.assertEqual(cut("FAT2-70170-rogue-" + "%C3%A9" * 50 + "-0a")[0], "é" * 40)
        self.assertEqual(cut("FAT2-70170-rogue-" + "%E5%90%8D" * 50 + "-0a")[0], "名" * 40)
        # the cut keeps no space at its end, as the site's trim does
        self.assertEqual(cut("FAT2-70170-rogue-" + "a" * 39 + "%20" + "b" * 5 + "-0a")[0], "a" * 39)
        # the note names the build: the second here, after one with no points
        self.assertEqual(cut("FAT2-70170-rogue-E-.rogue-" + "a" * 50 + "-0a")[1], "The name of build 2 was cut to 40 characters.")
        self.assertEqual(cut("FAT2-70170-rogue-" + "a" * 50 + "-0a.rogue-" + "b" * 50 + "-0a")[2], 2)

    def test_the_writer_cuts_a_name_to_40_characters_as_the_site_does(self):
        write = L.eval("function(name) return FA.Code.Write({ { cls = 'rogue', name = name, picks = '0a' } }) end")
        self.assertEqual(write("a" * 41), "FAT3-70170-rogue-" + "a" * 40 + "-0a-0")
        self.assertEqual(write("a" * 40), "FAT3-70170-rogue-" + "a" * 40 + "-0a-0")
        self.assertEqual(write("é" * 41), "FAT3-70170-rogue-" + "%C3%A9" * 40 + "-0a-0")   # characters, not bytes
        # what it writes reads back whole, with no note
        read = L.eval("function(t) local b, e, n = FA.Code.Read(t); return b[1].name, #n end")
        self.assertEqual(read(write("b" * 60)), ("b" * 40, 0))

    def test_whitespace_of_every_kind_collapses(self):
        name = L.eval("function(t) local b = assert(FA.Code.Read(t)); return b[1].name end")
        self.assertEqual(name("FAT2-70170-rogue-%20%20Two%20%20%20words%20-0a"), "Two words")
        self.assertEqual(name("FAT2-70170-rogue-Tab%09and%0Anewline%0D%0Aand%0Bform%0Cfeed-0a"), "Tab and newline and form feed")
        # JavaScript's \s, which the site collapses: no-break, Ogham, en/em/thin and the rest of U+2000-200A, the line and
        # paragraph separators, narrow no-break, medium mathematical, ideographic and the byte order mark
        for spaces in ["%C2%A0", "%E1%9A%80", "%E2%80%80", "%E2%80%83", "%E2%80%8A", "%E2%80%A8", "%E2%80%A9", "%E2%80%AF", "%E2%81%9F", "%E3%80%80", "%EF%BB%BF"]:
            self.assertEqual(name("FAT2-70170-rogue-Two" + spaces * 3 + "%20words-0a"), "Two words", spaces)
            self.assertEqual(name("FAT2-70170-rogue-" + spaces + "Two" + spaces + "-0a"), "Two", spaces)
        # what \s doesn't take stays: the next line control, the zero width space, and the letters beside the spaces
        self.assertEqual(name("FAT2-70170-rogue-a%C2%85b-0a"), "a\u0085b")
        self.assertEqual(name("FAT2-70170-rogue-a%E2%80%8Bb-0a"), "a\u200bb")
        self.assertEqual(name("FAT2-70170-rogue-%E2%80%80%E2%80%8B%E2%80%80-0a"), "\u200b")
        self.assertEqual(name("FAT2-70170-rogue-%C3%A0%C2%A0%C3%A1-0a"), "à á")
        # and the writer says it the same way
        write = L.eval("function(name) return FA.Code.Write({ { cls = 'rogue', name = name, picks = '0a' } }) end")
        self.assertEqual(write("\u00a0Two\u3000\u3000words\ufeff"), "FAT3-70170-rogue-Two%20words-0a-0")

    def test_a_name_that_isnt_utf8_is_refused(self):
        read = L.eval("function(t) local b, e = FA.Code.Read(t); return b and b[1].name, e end")
        for bad in ["%FF%FE", "%80", "%C3", "%E2%82", "%C0%80", "%C1%BF", "%E0%80%80", "%ED%A0%80", "%ED%BF%BF", "%F4%90%80%80", "%F5%80%80%80", "%F0%9F%99", "a%C3%28", "%C3%A9%A9"]:
            name, err = read("FAT2-70170-warrior-A" + bad + "-0a")
            self.assertIsNone(name, bad)
            self.assertRegex(err, r"name of build 1 .* cut off", bad)
        # what is UTF-8 reads: two, three and four bytes, and the edges of each
        for good, text in [("%C3%9C", "Ü"), ("%C2%80", "\u0080"), ("%E5%90%8D", "名"), ("%E0%A0%80", "\u0800"), ("%ED%9F%BF", "\ud7ff"),
                           ("%EE%80%80", "\ue000"), ("%F0%9F%99%82", "🙂"), ("%F0%90%80%80", "\U00010000"), ("%F4%8F%BF%BF", "\U0010ffff")]:
            self.assertEqual(read("FAT2-70170-warrior-A" + good + "-0a")[0], "A" + text, good)

    def test_a_version_has_three_digits_at_most_and_a_build_eight(self):
        read = L.eval("function(t) local b, e = FA.Code.Read(t); return b and b[1].build, e end")
        self.assertIn("isn't a build code", read("FAT1234-70170-warrior-A-0a")[1])
        self.assertIn("newer version", read("FAT999-70170-warrior-A-0a-0")[1])
        self.assertIn("newer version", read("FAT100-70170-warrior-A-0a")[1])
        self.assertEqual(read("FAT2-12345678-warrior-A-0a"), (12345678, None))
        self.assertIn("doesn't read", read("FAT2-123456789-warrior-A-0a")[1])
        self.assertIn("doesn't read", read("FAT2-00000000000000000070170-warrior-A-0a")[1])

    def test_a_long_run_of_dots_reads_at_once(self):
        # "%.+$" tries every run of dots in a long code, and is quadratic: 200,000 of them took the site half a minute (#926)
        timed = L.eval("function(t) local c = os.clock(); local b, e = FA.Code.Read(t); return b, e, os.clock() - c end")
        for text in ["FAT2-" + "." * 200000 + "a", "FAT2-70170-warrior-A-0a" + "." * 200000 + "a", "FAT2-70170-warrior-A-0a" + "." * 200000]:
            builds, err, seconds = timed(text)
            self.assertLess(seconds, 1, text[:30])
        self.assertIsNone(timed("FAT2-" + "." * 200000 + "a")[0])
        self.assertEqual(timed("FAT2-70170-warrior-A-0a" + "." * 200000)[0][1].name, "A")   # a code's trailing full stops still go
        self.assertEqual(self.builds("FAT2-70170-warrior-Arms-0a....")[0], [("warrior", "Arms", "0a")])
        self.assertEqual(self.builds("Enjoy FAT2-70170-warrior-Arms-0a.")[0], [("warrior", "Arms", "0a")])

    # ---- version 3, the Talented rank (forever-armoury #1540; the cases are the site's, in test/build-code.test.cjs)
    def ranked(self, text):
        b, e, n = self.read(text)
        self.assertIsNone(e, text)
        return [(x.cls, x.name, x.picks, x.build, x.talented) for x in b.values()], list(n.values())

    def test_the_site_sample_round_trips_byte_for_byte(self):
        # forever-armoury PR 1586: warrior "Arms PvP", game build 70170, eight points, Talented rank 3
        sample = "FAT3-70170-warrior-Arms%20PvP-0a0a0a0b0b0b1c1c-3"
        self.assertEqual(self.ranked(sample), ([("warrior", "Arms PvP", "0a0a0a0b0b0b1c1c", 70170, 3)], []))
        write = L.eval("function(b) return FA.Code.Write({ b }, 70170) end")
        self.assertEqual(write({"cls": "warrior", "name": "Arms PvP", "picks": "0a0a0a0b0b0b1c1c", "talented": 3}), sample)
        write = L.eval("function(text) return FA.Code.Write(assert(FA.Code.Read(text)), 70170) end")
        self.assertEqual(write(sample), sample)

    def test_the_talented_rank_round_trips_zero_to_five(self):
        write = L.eval("function(rank) return FA.Code.Write({ { cls = 'warrior', name = 'Arms PvP', picks = '0a0a0a0b0b0b1c1c', talented = rank } }) end")
        for rank in range(6):
            code = write(rank)
            self.assertEqual(code, "FAT3-70170-warrior-Arms%20PvP-0a0a0a0b0b0b1c1c-" + str(rank))
            self.assertEqual(self.ranked(code)[0], [("warrior", "Arms PvP", "0a0a0a0b0b0b1c1c", 70170, rank)])
        # every build of a paste has its own
        paste = "FAT3-70170-warrior-Arms-0a-3.warrior-Fury-1a1a1b-0.warrior-Prot-2a-5"
        self.assertEqual([b[4] for b in self.ranked(paste)[0]], [3, 0, 5])
        self.assertEqual([b[4] for b in self.ranked(paste + " and " + "FAT3-70170-warrior-Fury-1a1a1b-2")[0]], [3, 0, 5, 2])
        # a build with no points is left out whatever its rank
        self.assertEqual(self.ranked("FAT3-70170-warrior-Empty--4.warrior-Fury-1a1a1b-2"),
                         ([("warrior", "Fury", "1a1a1b", 70170, 2)], ["Left out a build with no talent points."]))

    def test_a_rank_that_is_not_0_to_5_is_written_as_0(self):
        write = L.eval("function(rank) return FA.Code.Write({ { cls = 'mage', name = '', picks = '0a', talented = rank } }) end")
        for bad in [6, -1, 2.5, "3", 10]:
            self.assertEqual(write(bad), "FAT3-70170-mage--0a-0", str(bad))
        self.assertEqual(L.eval("FA.Code.Write({ { cls = 'mage', name = '', picks = '0a' } })"), "FAT3-70170-mage--0a-0")   # none given
        self.assertEqual(L.eval("FA.Code.Write({ { cls = 'mage', name = '', picks = '0a', talented = 5 } }, false)"), "FAT3-0-mage--0a-5")

    def test_older_codes_read_with_rank_0(self):
        self.assertEqual(self.ranked("FAT2-70170-warrior-Arms-0a.warrior-Fury-1a1a1b")[0],
                         [("warrior", "Arms", "0a", 70170, 0), ("warrior", "Fury", "1a1a1b", 70170, 0)])
        self.assertEqual(self.ranked("FAT1-warrior-Arms-0a")[0], [("warrior", "Arms", "0a", None, 0)])
        # a FAT3 build of 0, which is what Write gives for a FAT1- build, is no build
        self.assertEqual(self.ranked("FAT3-0-warrior-Arms-0a-2")[0], [("warrior", "Arms", "0a", None, 2)])

    def test_a_dash_after_a_version_3_code_is_not_part_of_it(self):
        code = "FAT3-70170-warrior-Arms-0a-3"
        for pasted in [code, "here it is - " + code + "-", "here: " + code + ".-", code + ".-.-", "here: " + code + ".", "<" + code + ">"]:
            self.assertEqual(self.ranked(pasted)[0], [("warrior", "Arms", "0a", 70170, 3)], pasted)
        # a version 2 code keeps its dash: it is the name's or picks' end, and the reader refuses it as cut off
        self.assertRegex(self.read("FAT2-70170-warrior-Arms-0a-")[1], r"Build 1 .* doesn't read")

    def test_version_3_errors(self):
        def say(text):
            b, e, _ = self.read(text)
            self.assertIsNone(b, text)
            return e
        for bad in ["FAT3-", "FAT3-70170", "FAT3-warrior-Arms-0a-0", "FAT3-x-warrior-Arms-0a-0"]:
            self.assertRegex(say(bad), r"doesn't read", bad)
        for bad in ["FAT3-70170-warrior-Arms-0a",           # no rank: cut off, or a FAT2 code with its version changed
                    "FAT3-70170-warrior-Arms-0a-0-0", "FAT3-70170-knight-Arms-0a-0", "FAT3-70170-warrior-Arms-0a0-0", "FAT3-70170-warrior-Arms-3a-0"]:
            self.assertRegex(say(bad), r"Build 1 .* doesn't read", bad)
        self.assertRegex(say("FAT3-70170-warrior-Arms-0a-0.warrior-Fury-1a"), r"Build 2 .* doesn't read")
        self.assertRegex(say("FAT3-70170-warrior-Ar%2-0a-0"), r"name of build 1 .* cut off")
        for rank in ["6", "9", "x", "10", "00", "a", "%30"]:
            self.assertEqual(say("FAT3-70170-warrior-Arms-0a-" + rank),
                             "The Talented rank of build 1 in that code isn't a number from 0 to 5. Copy the whole code again.", rank)
        self.assertEqual(say("FAT3-70170-warrior-Arms-0a-0.warrior-Fury-1a-7"),
                         "The Talented rank of build 2 in that code isn't a number from 0 to 5. Copy the whole code again.")
        # the version stays three digits at most, and 4 is from a newer addon
        self.assertIn("newer version", say("FAT4-70170-warrior-Arms-0a-0"))
        self.assertIn("isn't a build code", say("FAT1234-70170-warrior-Arms-0a-0"))
        # a long run of dots and dashes is read at once
        timed = L.eval("function(t) local c = os.clock(); local b, e = FA.Code.Read(t); return b, e, os.clock() - c end")
        builds, err, seconds = timed("FAT3-" + ".-" * 100000 + "a")
        self.assertIsNone(builds)
        self.assertLess(seconds, 1)
        self.assertEqual(len(self.ranked("FAT3-70170-warrior-Arms-0a-0.-.-")[0]), 1)

    def test_points(self):
        points = L.eval("function(p) local t = FA.Code.Points(p); if not t then return nil end local out = {} for i, x in ipairs(t) do out[i] = x.tab .. ':' .. x.cell end return table.concat(out, ' ') end")
        self.assertEqual(points("0001121r"), "1:0 1:1 2:2 2:27")
        self.assertIsNone(points("0"))
        self.assertIsNone(points("3a"))
        self.assertIsNone(points("0s"))


class Talents(unittest.TestCase):
    """The game's talents as trees of cells, from the trait system and from the old API alike."""

    def at(self, tab, cell):
        return L.eval("function(tab, cell) local t = FA.Talents.At(tab, cell); if not t then return nil end return t.name .. ' ' .. t.row .. ',' .. t.col .. ' ' .. t.rank .. '/' .. t.max .. ' #' .. t.node end")(tab, cell)

    def check_trees(self):
        self.assertTrue(L.eval("FA.Talents.Ready()"))
        self.assertEqual(L.eval("function() local out = {} for i, t in ipairs(FA.Talents.Trees()) do out[i] = t.name end return table.concat(out, ' ') end")(), "Arms Fury Protection")
        self.assertRegex(self.at(1, 1), r"^Deflection 1,2 0/5 #")        # tier 1 column 2 -> cell 1
        self.assertRegex(self.at(1, 2), r"^Improved Heroic Strike 1,3 0/3")
        self.assertRegex(self.at(1, 4), r"^Tactical Mastery 2,1")         # tier 2 column 1
        self.assertRegex(self.at(1, 6), r"^Anger Management 2,3")
        self.assertRegex(self.at(1, 11), r"^Sweeping Strikes 3,4")        # a lone talent in column 4
        self.assertRegex(self.at(2, 2), r"^Cruelty 1,3")
        self.assertRegex(self.at(3, 1), r"^Shield Specialization 1,2")
        self.assertRegex(self.at(3, 4), r"^Toughness 2,1")
        self.assertRegex(self.at(3, 11), r"^Last Stand 3,4")
        self.assertIsNone(self.at(1, 0))
        self.assertIsNone(self.at(2, 0))   # Fury's empty first column stays empty
        self.assertIsNone(self.at(4, 1))
        L.run("TREE[1][1][4] = 2; FA.Talents.Forget()")
        self.assertRegex(self.at(1, 1), r"^Deflection 1,2 2/5")
        self.assertEqual(L.eval("FA.Talents.Spent()"), 2)

    def test_trait_nodes_become_cells_by_position(self):
        L.run("RESET('traits')")
        self.check_trees()
        self.assertRegex(self.at(1, 1), r"#101$")   # the node id, for the window's button

    def test_the_old_api_gives_the_same_trees(self):
        L.run("RESET('legacy')")
        self.check_trees()
        self.assertRegex(self.at(1, 1), r"#1$")     # the talent index
        L.run("RESET('traits')")

    def test_not_ready_before_the_game_answers(self):
        L.run("RESET('traits'); API = 'none'")
        self.assertFalse(L.eval("FA.Talents.Ready()"))
        self.assertEqual(L.eval("FA.Talents.Spent()"), 0)
        p, why = L.eval("function() local p, why = FA.Progress({ picks = '01' }); return p, why end")()
        self.assertIsNone(p)
        self.assertIn("hasn't given its talents", why)
        L.run("RESET('traits')")

    def test_each_tree_has_its_own_grid(self):
        # Protection drawn closer: with the smallest gap of all three trees, Arms and Fury would sort on its spacing
        L.run("RESET('traits'); NODES_FROM({ { 300, 600, 1500, 600 }, { 4300, 600, 1500, 600 }, { 8300, 500, 1400, 450 } }); FA.Talents.Forget()")
        self.check_trees()

    def test_an_off_grid_node_only_touches_its_own_tree(self):
        L.run("RESET('traits'); NODES[NODE(3, 2)].posX = NODES[NODE(3, 2)].posX + 300; FA.Talents.Forget()")
        self.assertRegex(self.at(1, 1), r"^Deflection 1,2")
        self.assertRegex(self.at(1, 11), r"^Sweeping Strikes 3,4")
        self.assertRegex(self.at(2, 2), r"^Cruelty 1,3")
        dropped = L.eval("function() local out = {} for _, d in ipairs(FA.Talents.View().dropped[3]) do out[#out + 1] = d.talent.name end return table.concat(out, ',') end")()
        # Protection's step halves, so its third and fourth columns land past the fourth, and chat says so
        self.assertEqual(dropped, "Anticipation,Last Stand")
        self.assertIn("2 talents didn't sort into the trees", L.eval("PRINTED"))
        L.run("RESET('traits')")

    def test_the_active_config_falls_back_to_the_spec_group(self):
        L.run("RESET('traits'); NO_ACTIVE = true")
        self.check_trees()
        self.assertEqual(L.eval("FA.Talents.View().configID"), 7)
        ok, said = L.eval("function() return FA.Apply({ picks = '010101' }) end")()   # check_trees left two in Deflection
        self.assertTrue(ok, said)
        self.assertEqual(L.eval("UNSPENT()"), 48)
        L.run("RESET('traits')")

    def test_a_trait_function_the_client_lacks_is_said_once_and_raises_nothing(self):
        L.run("RESET('traits')")
        run = L.eval("""function(ns, name)
          local saved = _G[ns][name]; _G[ns][name] = nil
          local errors = {}
          PRINTED = ""
          SPEC.groups = 2; FAIL_COMMIT = true
          for round = 1, 2 do
            FA.Talents.Forget()
            local ok, err = pcall(function()
              FA.Talents.View(); FA.Talents.Unspent(); FA.Talents.HasStaged(); FA.Talents.OtherSpec(); FA.Talents.Dump()
              FA.Apply({ picks = "0101" }); FA.Talents.CommitFailed(7)
            end)
            if not ok then errors[#errors + 1] = err end
          end
          _G[ns][name] = saved; SPEC.groups = 1; FAIL_COMMIT = false
          return table.concat(errors, "; "), PRINTED
        end""")
        for ns, name in [("C_Traits", n) for n in ["GetConfigInfo", "GetGroupDisplayInfoByTreeID", "GetTreeNodes", "GetNodeInfo", "GetEntryInfo",
                                                    "GetDefinitionInfo", "PurchaseRank", "RollbackConfig"]] + \
                         [("C_ClassTalents", "CommitConfig"), ("C_SpecializationInfo", "GetCombatConfigIDForSpecGroup")]:
            errors, said = run(ns, name)
            self.assertEqual(errors, "", ns + "." + name)
            self.assertEqual(said.count(ns + "." + name), 1, ns + "." + name + ": " + said)
            self.assertIn("This client has no " + ns + "." + name + ", so", said)
            L.run("RESET('traits')")
        # two the addon does without by design, with no line in chat and the fallbacks used
        for name in ["GetTreeCurrencyInfo", "ConfigHasStagedChanges"]:
            errors, said = run("C_Traits", name)
            self.assertEqual((errors, said), ("", ""), name)
            L.run("RESET('traits')")
        # the functions are back: the trees read and Apply spends
        self.assertTrue(L.eval("FA.Talents.Ready()"))
        ok, said = L.eval("function() return FA.Apply({ picks = '0101' }) end")()
        self.assertTrue(ok, said)

    def test_talents_left_out_are_reported(self):
        L.run("RESET('traits')")
        stray = L.eval("EXTRA(1, 300 + 4 * 600, 1500, 'Stray')")         # Arms, column 5
        twin = L.eval("EXTRA(1, 900, 1500, 'Twin')")                       # on Deflection's cell
        deep = L.eval("EXTRA(3, 8300, 1500 + 7 * 600, 'Deep')")            # Protection, row 8
        L.run("FA.Talents.Forget()")
        self.check_trees()                                                  # the rest sorts as before
        dropped = L.eval("function(t) local out = {} for _, d in ipairs(FA.Talents.View().dropped[t]) do out[#out + 1] = d.talent.name .. ': ' .. d.why end return table.concat(out, '; ') end")
        self.assertEqual(dropped(1), "Stray: column 5, outside the four; Twin: on 1,2 with Deflection (node 101)")
        self.assertEqual(dropped(2), "")
        self.assertEqual(dropped(3), "Deep: row 8, below the seventh")
        self.assertIn("3 talents didn't sort into the trees, so builds can't use them. /fa debug lists them.", L.eval("PRINTED"))
        lines = list(L.eval("FA.Talents.Dump()").values())
        self.assertEqual(lines[0], "1. Arms")
        self.assertEqual(lines[1], "   columns 600 apart from x 300 (a full tree's leftmost talent), rows 600 apart from y 1500")
        self.assertIn("   1,2 (1) Deflection 2/5 at 900,1500, node 101", lines)   # check_trees spent two
        self.assertIn("   left out: 1,5 Stray 0/1 at 2700,1500, node %d: column 5, outside the four" % stray, lines)
        self.assertIn("   left out: 1,2 Twin 0/1 at 900,1500, node %d: on 1,2 with Deflection (node 101)" % twin, lines)
        self.assertIn("   left out: 8,1 Deep 0/1 at 8300,5700, node %d: row 8, below the seventh" % deep, lines)
        self.assertIn("   columns 600 apart from x 4300 (from the full trees' spacing), rows 600 apart from y 1500 (rows spaced as another tree's)", lines)
        self.assertEqual(lines[-1], "3 talents left out, marked above.")
        L.run("RESET('traits')")
        lines = list(L.eval("FA.Talents.Dump()").values())
        self.assertEqual(lines[-1], "Every talent has a cell of its own.")


class Builds(unittest.TestCase):
    def setUp(self):
        L.run("RESET('traits')")

    def test_add_find_forget_and_export(self):
        add = L.eval("function(text) local b = assert(FA.Code.Read(text)); return FA.AddBuilds(b) end")
        self.assertEqual(add("FAT1-warrior-Arms-0101.warrior-Fury-1a1a.mage-Frost-2b"), (2, 1))
        names = L.eval("function() local out = {} for _, b in ipairs(FA.BuildsFor('warrior')) do out[#out + 1] = b.id .. '=' .. b.name .. ':' .. b.picks end return table.concat(out, ' ') end")
        self.assertEqual(names(), "1=Arms:0101 2=Fury:1a1a")
        # the same name and points again is the same build, with its id
        self.assertEqual(add("FAT1-warrior-Arms-0101"), (1, 0))
        self.assertEqual(names(), "1=Arms:0101 2=Fury:1a1a")
        # the same name with other points is another build
        self.assertEqual(add("FAT1-warrior-Arms-010102"), (1, 0))
        self.assertEqual(names(), "1=Arms:0101 2=Fury:1a1a 4=Arms:010102")
        self.assertEqual(L.eval("FA.ExportCode()"), "FAT3-0-warrior-Arms-0101-0.warrior-Fury-1a1a-0.warrior-Arms-010102-0")   # FAT1- in, FAT3- out, build 0 and rank 0
        L.run("FA.SetActive(2)")
        self.assertEqual(L.eval("FA.ActiveBuild().name"), "Fury")
        self.assertTrue(L.eval("FA.ForgetBuild('warrior', 2)"))
        self.assertIsNone(L.eval("FA.ActiveBuild()"))
        self.assertEqual(names(), "1=Arms:0101 4=Arms:010102")
        self.assertFalse(L.eval("FA.ForgetBuild('warrior', 9)"))

    def test_builds_with_one_name_keep_each_their_picks(self):
        add = L.eval("function(text) local b = assert(FA.Code.Read(text)); return FA.AddBuilds(b) end")
        names = L.eval("function() local out = {} for _, b in ipairs(FA.BuildsFor('warrior')) do out[#out + 1] = b.id .. '=' .. b.name .. ':' .. b.picks .. '@' .. tostring(b.build) end return table.concat(out, ' ') end")
        # two builds of one name in one code, and then in another
        self.assertEqual(add("FAT2-70170-warrior-Arms-0101.warrior-Arms-0202"), (2, 0))
        self.assertEqual(names(), "1=Arms:0101@70170 2=Arms:0202@70170")
        self.assertEqual(add("FAT2-70170-warrior-Arms-0303"), (1, 0))
        self.assertEqual(names(), "1=Arms:0101@70170 2=Arms:0202@70170 3=Arms:0303@70170")
        # the same name and points updates the one, its game build with it, and keeps its id
        self.assertEqual(add("FAT2-70200-warrior-Arms-0202"), (1, 0))
        self.assertEqual(names(), "1=Arms:0101@70170 2=Arms:0202@70200 3=Arms:0303@70170")
        # builds with no name are told apart by their points too
        self.assertEqual(add("FAT1-warrior--0a0a.warrior--0b0b"), (2, 0))
        self.assertEqual(add("FAT1-warrior--0a0a"), (1, 0))
        self.assertEqual(names(), "1=Arms:0101@70170 2=Arms:0202@70200 3=Arms:0303@70170 4=:0a0a@false 5=:0b0b@false")

    def test_import_keeps_each_builds_game_build(self):
        add = L.eval("function(text) local b = assert(FA.Code.Read(text)); return FA.AddBuilds(b) end")
        add("FAT2-70009-warrior-Arms-0101.warrior-Prot-2121 FAT2-70170-warrior-Fury-1a1a FAT1-warrior-Old-0202")
        builds = L.eval("function() local out = {} for _, b in ipairs(FA.BuildsFor('warrior')) do out[#out + 1] = b.name .. '@' .. tostring(b.build) end return table.concat(out, ' ') end")
        self.assertEqual(builds(), "Arms@70009 Prot@70009 Fury@70170 Old@false")
        # a code per game build, a line each, in the order the first of each comes
        self.assertEqual(L.eval("FA.ExportCode()").split("\n"), [
            "FAT3-70009-warrior-Arms-0101-0.warrior-Prot-2121-0", "FAT3-70170-warrior-Fury-1a1a-0", "FAT3-0-warrior-Old-0202-0"])
        # Export reads back as it came: every build, each with its build
        back = L.eval("function() local out = {} for _, b in ipairs(assert(FA.Code.Read(FA.ExportCode()))) do out[#out + 1] = b.name .. '@' .. tostring(b.build) end return table.concat(out, ' ') end")
        self.assertEqual(back(), "Arms@70009 Prot@70009 Fury@70170 Old@nil")
        # pasting Arms again from the game's build moves it to that build's code
        add("FAT2-70170-warrior-Arms-0101")
        self.assertEqual(L.eval("FA.ExportCode()").split("\n"), [
            "FAT3-70170-warrior-Arms-0101-0.warrior-Fury-1a1a-0", "FAT3-70009-warrior-Prot-2121-0", "FAT3-0-warrior-Old-0202-0"])
        # a build kept before builds were (0.2) is the game's, in the game build's code
        L.run("table.insert(FA.BuildsFor('warrior'), { id = 99, name = 'Kept', picks = '0303' })")
        self.assertEqual(L.eval("FA.ExportCode()").split("\n")[0], "FAT3-70170-warrior-Arms-0101-0.warrior-Fury-1a1a-0.warrior-Kept-0303-0")

    def progress(self, picks):
        return L.eval("function(picks) local p, why = FA.Progress({ picks = picks }); if not p then return nil, why end "
                      "return { n = p.next and p.next.n, name = p.next and p.next.talent.name, rank = p.next and p.next.rank, level = p.next and p.next.level, "
                      "tab = p.next and p.next.talent.tab, points = p.points, spent = p.spent, off = p.off, due = p.due } end")(picks)

    def test_next_talent_walks_the_build_in_order(self):
        # three Deflection, one Improved Heroic Strike, two Cruelty
        picks = "010101021212"
        p = self.progress(picks)
        self.assertEqual((p.n, p.name, p.rank, p.level, p.tab, p.points, p.spent, p.off, p.due), (1, "Deflection", 1, 10, 1, 6, 0, 0, 6))
        L.run("TREE[1][1][4] = 2; FA.Talents.Forget()")   # two points in Deflection
        p = self.progress(picks)
        self.assertEqual((p.n, p.name, p.rank, p.level, p.spent, p.off), (3, "Deflection", 3, 12, 2, 0))
        L.run("TREE[1][1][4] = 3; TREE[1][2][4] = 1; FA.Talents.Forget()")
        p = self.progress(picks)
        self.assertEqual((p.n, p.name, p.rank, p.level, p.tab), (5, "Cruelty", 1, 14, 2))
        L.run("TREE[2][2][4] = 2; FA.Talents.Forget()")
        p = self.progress(picks)
        self.assertIsNone(p.n)
        self.assertEqual((p.spent, p.off), (6, 0))

    def test_points_outside_the_build_are_counted(self):
        L.run("TREE[1][1][4] = 1; TREE[3][1][4] = 2; FA.Talents.Forget()")   # one planned, two not
        p = self.progress("010101")
        self.assertEqual((p.n, p.spent, p.off), (2, 3, 2))
        L.run("TREE[1][1][4] = 4; FA.Talents.Forget()")   # a rank past the plan's three
        p = self.progress("010101")
        self.assertEqual((p.n, p.spent, p.off), (None, 6, 3))

    def test_due_follows_the_level(self):
        L.run("PLAYER.level = 11")
        p = self.progress("010101")
        self.assertEqual((p.due, p.n, p.level), (2, 1, 10))
        L.run("PLAYER.level = 5")
        self.assertEqual(self.progress("010101").due, 0)

    def test_talented_moves_the_first_point_earlier(self):
        self.assertEqual(L.eval("FA.FirstLevel()"), 10)
        L.run("TALENTED = 3; PLAYER.level = 8")   # three ranks: the first point at level 7
        self.assertEqual(self.rank(), (3, "game"))
        p = self.progress("010101")
        self.assertEqual((p.due, p.n, p.level), (2, 1, 7))
        L.run("TALENTED = 5; PLAYER.level = 5")
        self.assertEqual(self.progress("010101").due, 1)
        names = L.eval("function() local list = assert(FA.PlanApply({ picks = '010101' })); return #list end")()
        self.assertEqual(names, 1)
        L.run("TALENTED = false")                 # the game won't say, and the build doesn't: no ranks
        self.assertEqual(L.eval("FA.FirstLevel()"), 10)
        self.assertEqual(self.progress("010101").due, 0)

    def rank(self, build="nil"):
        return L.eval("function() return FA.TalentedRank(" + build + ") end")()

    def test_import_keeps_each_builds_talented_rank(self):
        add = L.eval("function(text) local b = assert(FA.Code.Read(text)); return FA.AddBuilds(b) end")
        ranks = L.eval("function() local out = {} for _, b in ipairs(FA.BuildsFor('warrior')) do out[#out + 1] = b.name .. '=' .. tostring(b.talented) end return table.concat(out, ' ') end")
        add("FAT3-70170-warrior-Arms-0101-3.warrior-Fury-1a1a-0 FAT2-70170-warrior-Old-0202 FAT1-warrior-Older-0303")
        self.assertEqual(ranks(), "Arms=3 Fury=0 Old=0 Older=0")
        # the same name and points again updates the rank, as it does the game build, and keeps the id
        add("FAT3-70170-warrior-Arms-0101-5")
        self.assertEqual(ranks(), "Arms=5 Fury=0 Old=0 Older=0")
        self.assertEqual(L.eval("FA.BuildsFor('warrior')[1].id"), 1)
        # a build kept by an older addon has none
        L.run("table.insert(FA.BuildsFor('warrior'), { id = 99, name = 'Kept', picks = '0404' })")
        self.assertIn("Kept=nil", ranks())

    def test_export_writes_each_builds_talented_rank(self):
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT3-70170-warrior-Arms-0101-3.warrior-Fury-1a1a-0.warrior-Prot-2121-5 FAT2-70170-warrior-Old-0202 FAT1-warrior-Older-0303')))")
        self.assertEqual(L.eval("FA.ExportCode()").split("\n"), [
            "FAT3-70170-warrior-Arms-0101-3.warrior-Fury-1a1a-0.warrior-Prot-2121-5.warrior-Old-0202-0", "FAT3-0-warrior-Older-0303-0"])
        # and it reads back with the same ranks
        back = L.eval("function() local out = {} for _, b in ipairs(assert(FA.Code.Read(FA.ExportCode()))) do out[#out + 1] = b.name .. '=' .. b.talented end return table.concat(out, ' ') end")
        self.assertEqual(back(), "Arms=3 Fury=0 Prot=5 Old=0 Older=0")
        # a build kept before ranks were is written with 0
        L.run("table.insert(FA.BuildsFor('warrior'), { id = 99, name = 'Kept', picks = '0404' })")
        self.assertIn("warrior-Kept-0404-0", L.eval("FA.ExportCode()"))

    def test_a_damaged_talented_rank_is_dropped(self):
        L.run("FA.db.builds.warrior = { { id = 1, name = 'A', picks = '0101', talented = 9 }, { id = 2, name = 'B', picks = '0101', talented = 'x' }, "
              "{ id = 3, name = 'C', picks = '0101', talented = 2.5 }, { id = 4, name = 'D', picks = '0101', talented = 4 } }")
        self.assertEqual(tuple(L.eval("function() return FA.RepairBuilds() end")()), (0, 3))
        self.assertEqual(L.eval("function() local out = {} for _, b in ipairs(FA.db.builds.warrior) do out[#out + 1] = tostring(b.talented) end return table.concat(out, ' ') end")(), "nil nil nil 4")

    def test_the_due_level_uses_the_games_rank_then_the_builds_then_none(self):
        self.assertEqual(self.rank("{ talented = 2 }"), (0, "game"))        # the game says 0: a 0 it gives is a 0
        L.run("TALENTED = 3")
        self.assertEqual(self.rank("{ talented = 1 }"), (3, "game"))        # the game over the build
        self.assertEqual(self.rank(), (3, "game"))
        L.run("TALENTED = false")                                           # the game won't say
        self.assertEqual(self.rank("{ talented = 4 }"), (4, "build"))
        self.assertEqual(self.rank("{ talented = 0 }"), (0, "build"))
        self.assertEqual(self.rank("{}"), (0, "none"))                      # a build that doesn't know its rank
        self.assertEqual(self.rank(), (0, "none"))                          # no build
        L.run("PLAYER.level = 8")
        L.run("function BUILD(r) return { picks = '010101', talented = r } end")
        self.assertEqual(tuple(L.eval("function() return (function(p) return p.next.level, p.due end)(FA.Progress(BUILD(3))) end")()), (7, 2))
        self.assertEqual(tuple(L.eval("function() return (function(p) return p.next.level, p.due end)(FA.Progress(BUILD(0))) end")()), (10, 0))
        self.assertEqual(tuple(L.eval("function() return (function(p) return p.next.level, p.due end)(FA.Progress(BUILD(nil))) end")()), (10, 0))
        # the game's rank wins over the build's
        L.run("TALENTED = 5")
        self.assertEqual(tuple(L.eval("function() return (function(p) return p.next.level, p.due end)(FA.Progress(BUILD(0))) end")()), (5, 3))   # three points in the build
        # the trainer reset's count by level (the game won't say how many points it has) uses the same first level
        L.run("TALENTED = false; PLAYER.level = 8; C_Traits.GetTreeCurrencyInfo, KEEP = function() end, C_Traits.GetTreeCurrencyInfo; FA.Talents.Forget()")
        try:
            self.assertEqual(L.eval("FA.PointsAfterReset(BUILD(3))"), 2)
            self.assertEqual(L.eval("FA.PointsAfterReset(BUILD(nil))"), 0)
            L.run("TALENTED = 5")
            self.assertEqual(L.eval("FA.PointsAfterReset(BUILD(0))"), 3)
        finally:
            L.run("C_Traits.GetTreeCurrencyInfo = KEEP")

    def test_debug_says_which_rank_is_in_use_and_where_it_came_from(self):
        debug = lambda: (L.run("PRINTED = ''; SlashCmdList.FOREVERARMOURY('debug')"), L.eval("PRINTED"))[1]
        L.run("TALENTED = 2")
        self.assertIn("Talented rank 2, read from the game; the first point comes at level 8.", debug())
        L.run("TALENTED = false")
        self.assertIn("Talented rank 0, neither the game nor a build says; the first point comes at level 10.", debug())
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT3-70170-warrior-Arms-0101-4'))); FA.SetActive(1)")
        self.assertIn("Talented rank 4, the build Arms's own: the game won't say; the first point comes at level 6.", debug())
        L.run("TALENTED = 1")
        self.assertIn("Talented rank 1, read from the game; the first point comes at level 9.", debug())

    def test_the_trainer_reset_counts_talented(self):
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT2-70170-warrior-Arms-" + GATED + "'))); FA.SetActive(1)")
        L.run("StaticPopupDialogs.CONFIRM_TALENT_WIPE = { OnAccept = function() end }; FA.HookWipe()")
        accept = lambda: L.run("StaticPopupDialogs.CONFIRM_TALENT_WIPE.OnAccept()")
        L.run("PLAYER.level = 12; TALENTED = 5")
        accept()
        self.assertIn("it spends 8 points as Arms says", L.eval("PRINTED"))
        L.run("PRINTED = ''; TALENTED = 0")
        accept()
        self.assertIn("it spends 3 points as Arms says", L.eval("PRINTED"))

    def accept_wipe(self):
        L.run("StaticPopupDialogs.CONFIRM_TALENT_WIPE.OnAccept()")

    def hook_wipe(self):
        L.run("ACCEPTED = 0; StaticPopupDialogs.CONFIRM_TALENT_WIPE = { OnAccept = function() ACCEPTED = ACCEPTED + 1 end }; FA.HookWipe()")

    def test_the_trainer_reset_is_said_once_accepted_not_when_cancelled(self):
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT2-70170-warrior-Arms-" + GATED + "'))); FA.SetActive(1); PLAYER.level = 12")
        self.hook_wipe()
        # the trainer asks, the dialog is up: nothing is said, and cancelling it (its OnAccept never runs) says nothing
        L.run("EVENT('CONFIRM_TALENT_WIPE', 10000)")
        self.assertEqual(L.eval("PRINTED"), "")
        # accepted: the game's own OnAccept still runs, and chat says what Apply will spend
        self.accept_wipe()
        self.assertEqual(L.eval("ACCEPTED"), 1)
        self.assertIn("After the reset, open your talents and press Apply: it spends 3 points as Arms says.", L.eval("PRINTED"))

    def test_the_trainer_reset_counts_the_points_apply_would_spend(self):
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT2-70170-warrior-Arms-" + GATED + "'))); FA.SetActive(1); PLAYER.level = 12")
        self.hook_wipe()
        said = lambda: (self.accept_wipe(), L.eval("PRINTED"))[1].split("it spends ")[-1].split(" as Arms")[0]
        self.assertEqual(said(), "3 points")
        # points the level doesn't give, which the game counts: the build's 13 at most
        L.run("PRINTED = ''; BONUS = 2"); self.assertEqual(said(), "5 points")
        L.run("PRINTED = ''; BONUS = 40"); self.assertEqual(said(), "13 points")
        # spent ones count too, since the reset makes them all unspent
        L.run("PRINTED = ''; BONUS = 0; TREE[1][1][4] = 2; FA.Talents.Forget()"); self.assertEqual(said(), "3 points")
        L.run("PRINTED = ''; BONUS = 2; FA.Talents.Forget()"); self.assertEqual(said(), "5 points")
        # when the game won't say how many it has, the level does
        L.run("PRINTED = ''; BONUS = 2; TREE[1][1][4] = 0; FA.Talents.Forget(); C_Traits.GetTreeCurrencyInfo, KEEP = function() end, C_Traits.GetTreeCurrencyInfo")
        try:
            self.assertEqual(said(), "3 points")
        finally:
            L.run("C_Traits.GetTreeCurrencyInfo = KEEP")
        L.run("PRINTED = ''; BONUS = 0; PLAYER.level = 10"); self.assertEqual(said(), "1 point")

    def test_the_trainer_reset_says_nothing_without_a_build_followed(self):
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT2-70170-warrior-Arms-" + GATED + "'))); PLAYER.level = 12")
        self.hook_wipe()
        self.accept_wipe()
        self.assertEqual(L.eval("PRINTED"), "")                      # no build followed
        L.run("FA.SetActive(1); FA.db.parts.plan = false")
        self.accept_wipe()
        self.assertEqual(L.eval("PRINTED"), "")                      # the level plan part is off
        L.run("FA.db.parts.plan = true; FA.SetActive(1)")
        self.accept_wipe()
        self.assertIn("it spends 3 points as Arms says", L.eval("PRINTED"))

    def test_a_trainer_dialog_the_addon_cant_find_is_said(self):
        L.run("local saved = StaticPopupDialogs; StaticPopupDialogs = {}; FA.HookWipe(); StaticPopupDialogs = saved")
        self.assertIn("CONFIRM_TALENT_WIPE", L.eval("PRINTED"))

    def test_a_name_with_a_colour_escape_is_drawn_as_typed(self):
        self.assertEqual(L.eval("FA.Esc('A|cffff0000Red|r |Hx|h')"), "A||cffff0000Red||r ||Hx||h")
        self.assertEqual(L.eval("FA.Esc('plain')"), "plain")
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT2-70170-warrior-A%7CcffFF0000Red-" + GATED + "'))); FA.SetActive(1); PLAYER.level = 12")
        self.assertEqual(L.eval("FA.ActiveBuild().name"), "A|cffFF0000Red")   # kept as it is: it is only drawn escaped
        self.hook_wipe()
        self.accept_wipe()
        self.assertIn("as A||cffFF0000Red says", L.eval("PRINTED"))
        L.run("PRINTED = ''; SlashCmdList.FOREVERARMOURY('list')")
        self.assertIn("> A||cffFF0000Red (13 points)", L.eval("PRINTED"))

    def test_the_class_is_known_from_init(self):
        # an import before PLAYER_LOGIN needs it
        L.run("FA.class = nil; ForeverArmouryDB, ForeverArmouryCharDB = nil, nil; FA.Init()")
        self.assertEqual(L.eval("FA.class"), "warrior")
        self.assertEqual(L.eval("function() return FA.AddBuilds(assert(FA.Code.Read('FAT1-warrior-A-0101.mage-B-0101'))) end")(), (1, 1))
        L.run("PLAYER.class = 'MAGE'; FA.Init()")
        self.assertEqual(L.eval("FA.class"), "mage")
        L.run("PLAYER.class = 'WARRIOR'; FA.Init()")

    def test_damaged_saved_builds_are_dropped_or_repaired(self):
        L.run("""
          ForeverArmouryDB = { nextId = 3, builds = { warrior = {
            { id = 1, name = "Good", picks = "0101", build = 70170 },
            { id = 2, name = "No picks" },
            "junk",
            { id = 4, name = "Odd", picks = 10 },   -- not text
            { id = 5, name = "Empty", picks = "" },
            { id = 1, name = "Same id", picks = "0202", build = false },
            { name = 7, picks = "0303", build = "x" },
          }, mage = "not a list" } }
          ForeverArmouryCharDB = { build = 5 }
          PRINTED = ""
          FA.Init()
        """)
        built = L.eval("function() local out = {} for _, b in ipairs(FA.BuildsFor('warrior')) do out[#out + 1] = b.id .. '=' .. b.name .. ':' .. b.picks .. '@' .. tostring(b.build) end return table.concat(out, ' ') end")
        self.assertEqual(built(), "1=Good:0101@70170 3=Same id:0202@false 4=:0303@nil")
        self.assertEqual(L.eval("#FA.BuildsFor('mage')"), 0)
        self.assertEqual(L.eval("FA.db.nextId"), 5)
        self.assertIsNone(L.eval("FA.char.build"))                        # the build it followed was dropped
        self.assertIn("Your saved builds were damaged: dropped 5 saved builds it couldn't read, and repaired 2 saved builds with a missing name or id.", L.eval("PRINTED"))
        # what's left works: the list, a new build's id past every other
        L.run("SlashCmdList.FOREVERARMOURY('list')")
        self.assertIn("Good (2 points)", L.eval("PRINTED"))
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT1-warrior-New-0a')))")
        self.assertEqual(L.eval("FA.BuildsFor('warrior')[4].id"), 5)
        # sound ones are left alone, and say nothing
        L.run("PRINTED = ''; FA.Init()")
        self.assertEqual(L.eval("PRINTED"), "")
        self.assertEqual(L.eval("#FA.BuildsFor('warrior')"), 4)

    def test_a_cell_with_no_talent_is_refused(self):
        p, why = L.eval("function() local p, why = FA.Progress({ picks = '00' }); return p, why end")()
        self.assertIsNone(p)
        self.assertIn("isn't in your talent trees", why)

    def test_extra_names_the_points_the_build_lacks(self):
        L.run("TREE[1][1][4] = 1; TREE[3][1][4] = 2; FA.Talents.Forget()")
        extra = L.eval("function() local p = FA.Progress({ picks = '010101' }); local out = {} for i, x in ipairs(p.extra) do out[i] = x.talent.name .. ' ' .. x.over end return table.concat(out, ', ') end")()
        self.assertEqual(extra, "Shield Specialization 2")


# A warrior build that respects the tiers: five in Deflection, then Tactical Mastery (tier 2), then Sweeping Strikes
# (tier 3, needs 10 in Arms), then Cruelty.
GATED = "0101010101" + "0404040404" + "0b" + "1212"


class Apply(unittest.TestCase):
    def setUp(self):
        L.run("RESET('traits')")

    def plan(self, picks):
        return L.eval("function(picks) local list, why = FA.PlanApply({ picks = picks }); if not list then return nil, why end "
                      "local out = {} for i, t in ipairs(list) do out[i] = t.name end return table.concat(out, ','), nil end")(picks)

    def apply(self, picks):
        return L.eval("function(picks) return FA.Apply({ picks = picks }) end")(picks)

    def log(self):
        return list(L.eval("LOG").values())

    def test_plan_takes_as_many_points_as_are_unspent(self):
        L.run("PLAYER.level = 12")   # three points
        names, why = self.plan(GATED)
        self.assertEqual(names, "Deflection,Deflection,Deflection")
        L.run("PLAYER.level = 60")
        names, _ = self.plan(GATED)
        self.assertEqual(names.split(","), ["Deflection"] * 5 + ["Tactical Mastery"] * 5 + ["Sweeping Strikes", "Cruelty", "Cruelty"])

    def test_apply_spends_in_order_and_commits_once(self):
        L.run("PLAYER.level = 22")   # thirteen points: the whole build
        ok, said = self.apply(GATED)
        self.assertTrue(ok, said)
        self.assertEqual(said, "Deflection x5, Tactical Mastery x5, Sweeping Strikes, Cruelty x2")
        self.assertEqual(self.log()[-1], "commit")
        self.assertEqual(self.log().count("commit"), 1)
        self.assertEqual(L.eval("FA.Talents.Spent()"), 13)
        self.assertEqual(L.eval("UNSPENT()"), 0)
        ok, why = self.apply(GATED)
        self.assertFalse(ok)
        self.assertIn("Every point of this build is spent", why)

    def test_apply_continues_a_build_part_spent(self):
        L.run("PLAYER.level = 14; TREE[1][1][4] = 3; FA.Talents.Forget()")   # five points, three spent as the build says
        names, _ = self.plan(GATED)
        self.assertEqual(names, "Deflection,Deflection")
        ok, _ = self.apply(GATED)
        self.assertTrue(ok)
        self.assertEqual(L.eval("TREE[1][1][4]"), 5)

    def test_a_point_the_game_refuses_spends_nothing(self):
        # Sweeping Strikes before ten points in Arms: the game refuses it, and the points before it are rolled back
        ok, why = self.apply("0101" + "0b")
        self.assertFalse(ok)
        self.assertIn("point 3 (Sweeping Strikes)", why)
        self.assertEqual(self.log()[-1], "rollback")
        self.assertNotIn("commit", self.log())
        self.assertEqual(L.eval("FA.Talents.Spent()"), 0)

    def test_a_failed_commit_spends_nothing(self):
        L.run("FAIL_COMMIT = true")
        ok, why = self.apply(GATED)
        self.assertFalse(ok)
        self.assertIn("wouldn't apply", why)
        self.assertEqual(self.log()[-1], "rollback")
        self.assertEqual(L.eval("FA.Talents.Spent()"), 0)

    def test_the_game_is_asked_whether_talents_can_change_once_a_point_is_staged(self):
        # CanChangeTalents is false with nothing staged, as the client's docs say: Apply doesn't ask it then
        self.assertEqual(L.eval("C_ClassTalents.CanChangeTalents()"), (False, False, None))
        self.assertTrue(L.eval("FA.Talents.CanChange()"))
        ok, said = self.apply(GATED)
        self.assertTrue(ok, said)
        # and once a point is staged, its no stops Apply before the commit
        L.run("RESET('traits'); NO_CHANGE = 'You can only change talents in a rested area'")
        ok, why = self.apply(GATED)
        self.assertFalse(ok)
        self.assertEqual(why, "You can only change talents in a rested area. Nothing was spent.")
        self.assertEqual(self.log(), ["buy Deflection", "rollback"])
        self.assertEqual(L.eval("FA.Talents.Spent()"), 0)

    def test_a_late_commit_failure_is_rolled_back(self):
        # CommitConfig starts the cast; the game fails it after
        L.run("FAIL_COMMIT = 'late'")
        ok, _ = self.apply(GATED)
        self.assertTrue(ok)
        self.assertTrue(L.eval("next(STAGED) ~= nil"))
        L.run("EVENT('CONFIG_COMMIT_FAILED', 7)")
        self.assertEqual(self.log()[-1], "rollback")
        self.assertFalse(L.eval("next(STAGED) ~= nil"))
        self.assertEqual(L.eval("FA.Talents.Spent()"), 0)
        self.assertIn("The game didn't apply the talents, so they were rolled back. Nothing was spent.", L.eval("PRINTED"))
        # a failure of the window's own commit, with none of the addon's casting, is the window's
        L.run("PRINTED = ''; STAGED[NODE(1, 1)] = 1; EVENT('CONFIG_COMMIT_FAILED', 7)")
        self.assertEqual(self.log().count("rollback"), 1)
        self.assertTrue(L.eval("next(STAGED) ~= nil"))
        self.assertNotIn("rolled back", L.eval("PRINTED"))

    def test_a_commit_that_went_through_isnt_rolled_back(self):
        ok, _ = self.apply(GATED)
        self.assertTrue(ok)
        L.run("EVENT('TRAIT_CONFIG_UPDATED', 7); STAGED[NODE(1, 1)] = 1; EVENT('CONFIG_COMMIT_FAILED', 7)")
        self.assertNotIn("rollback", self.log())

    def test_a_commit_the_game_fails_at_once_is_said_once(self):
        L.run("FAIL_COMMIT = 'now'")
        ok, why = self.apply(GATED)
        self.assertFalse(ok)
        self.assertIn("wouldn't apply", why)
        self.assertEqual(self.log().count("rollback"), 1)
        self.assertEqual(L.eval("FA.Talents.Spent()"), 0)
        self.assertNotIn("rolled back", L.eval("PRINTED"))

    def test_apply_refuses_points_off_the_build(self):
        L.run("TREE[3][1][4] = 2; FA.Talents.Forget()")
        names, why = self.plan(GATED)
        self.assertIsNone(names)
        self.assertIn("2 points this build doesn't", why)

    def test_apply_waits_for_a_level_with_a_point(self):
        L.run("PLAYER.level = 10; TREE[1][1][4] = 1; FA.Talents.Forget()")
        names, why = self.plan(GATED)
        self.assertIsNone(names)
        self.assertEqual(why, "Your next point comes at level 11.")

    def test_apply_refuses_in_combat_and_over_staged_changes(self):
        L.run("COMBAT = true")
        ok, why = self.apply(GATED)
        self.assertFalse(ok)
        self.assertIn("combat", why)
        L.run("COMBAT = false; STAGED[NODE(2, 1)] = 1")
        ok, why = self.apply(GATED)
        self.assertFalse(ok)
        self.assertIn("changes waiting", why)

    def test_summary_groups_and_cuts(self):
        summary = L.eval("function(picks, limit) local list = FA.PlanApply({ picks = picks }); return FA.Summary(list, limit) end")
        self.assertEqual(summary(GATED, None), "Deflection x5, Tactical Mastery x5, Sweeping Strikes, Cruelty x2")
        self.assertEqual(summary(GATED, 2), "Deflection x5, Tactical Mastery x5, and 2 more")


class Events(unittest.TestCase):
    """The addon's event frame: refreshes coalesced to one a frame, the events it listens for, and a name the game refuses."""

    def setUp(self):
        L.run("RESET('traits'); COUNT, FORGETS = 0, 0; SAVED = { FA.Refresh, FA.Talents.Forget }")
        L.run("FA.Refresh = function() COUNT = COUNT + 1 end; local forget = FA.Talents.Forget; FA.Talents.Forget = function() FORGETS = FORGETS + 1; forget() end")

    def tearDown(self):
        L.run("FA.Refresh, FA.Talents.Forget = SAVED[1], SAVED[2]; FLUSH()")

    def test_a_burst_of_events_redraws_once_a_frame(self):
        L.run("for i = 1, 20 do EVENT('TRAIT_NODE_CHANGED') end; EVENT('PLAYER_LEVEL_UP'); EVENT('TRAIT_CONFIG_UPDATED', 7); EVENT('CONFIG_COMMIT_FAILED', 7)")
        self.assertEqual(L.eval("COUNT"), 0)       # not inside an event
        self.assertEqual(L.eval("FORGETS"), 23)    # what's cached is dropped at once, so a read in between asks the game
        L.run("FLUSH()")
        self.assertEqual(L.eval("COUNT"), 1)
        L.run("FLUSH()")
        self.assertEqual(L.eval("COUNT"), 1)
        L.run("EVENT('PLAYER_REGEN_ENABLED'); EVENT('PLAYER_REGEN_DISABLED'); EVENT('ACTIVE_COMBAT_CONFIG_CHANGED'); FLUSH()")
        self.assertEqual(L.eval("COUNT"), 2)       # the next frame's own

    def test_a_client_without_a_timer_redraws_at_once(self):
        L.run("SAVED_TIMER = C_Timer; C_Timer = nil; EVENT('TRAIT_NODE_CHANGED'); EVENT('TRAIT_NODE_CHANGED'); C_Timer = SAVED_TIMER")
        self.assertEqual(L.eval("COUNT"), 2)

    def test_login_listens_for_the_talent_and_combat_events(self):
        L.run("StaticPopupDialogs.CONFIRM_TALENT_WIPE = { OnAccept = function() end }; EVENT('PLAYER_LOGIN')")
        for e in ["PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "TRAIT_NODE_CHANGED", "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED",
                  "ACTIVE_COMBAT_CONFIG_CHANGED", "CHARACTER_POINTS_CHANGED", "CONFIG_COMMIT_FAILED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED"]:
            self.assertTrue(L.eval("REGISTERED." + e), e)
        self.assertNotIn("The game has no event", L.eval("PRINTED"))

    def test_an_event_the_game_refuses_is_named_in_chat(self):
        L.run("BAD_EVENTS = { ACTIVE_COMBAT_CONFIG_CHANGED = true, PLAYER_REGEN_ENABLED = true }; StaticPopupDialogs.CONFIRM_TALENT_WIPE = { OnAccept = function() end }; EVENT('PLAYER_LOGIN')")
        said = L.eval("PRINTED")
        self.assertIn("The game has no event ACTIVE_COMBAT_CONFIG_CHANGED, so the addon won't hear it.", said)
        self.assertIn("The game has no event PLAYER_REGEN_ENABLED, so the addon won't hear it.", said)
        self.assertNotIn("PLAYER_REGEN_DISABLED", said)
        self.assertTrue(L.eval("REGISTERED.PLAYER_REGEN_DISABLED"))   # the rest are still registered
        self.assertTrue(L.eval("REGISTERED.TRAIT_NODE_CHANGED"))


class Swap(unittest.TestCase):
    def setUp(self):
        L.run("RESET('traits')")

    def advice(self, picks):
        return L.eval("function(picks) return FA.SwapAdvice({ picks = picks }) end")(picks)

    def test_no_advice_when_the_points_fit(self):
        L.run("TREE[1][1][4] = 2; FA.Talents.Forget()")
        self.assertIsNone(self.advice(GATED))

    def test_a_reset_without_dual_spec(self):
        L.run("TREE[3][1][4] = 2; FA.Talents.Forget()")
        self.assertEqual(self.advice(GATED), "Reset your talents at a class trainer, then Apply spends every point in order.")

    def test_the_other_spec_when_it_fits(self):
        L.run("TREE[3][1][4] = 2; SPEC.groups = 2; OTHER[NODE(1, 1)] = 3; FA.Talents.Forget()")
        self.assertEqual(self.advice(GATED), "Your Secondary spec fits this build: activate it in the talent window, then Apply.")
        L.run("OTHER[NODE(2, 1)] = 1; FA.Talents.Forget()")   # the other spec has a point off the build too
        self.assertIn("Reset your talents", self.advice(GATED))

    def test_the_other_spec_is_read_from_its_own_config(self):
        L.run("SPEC.groups = 2; OTHER[NODE(1, 1)] = 4; FA.Talents.Forget()")
        view_spent = L.eval("function() local v, n = FA.Talents.OtherSpec(); return FA.Talents.Spent(v), n end")()
        self.assertEqual(tuple(view_spent), (4, 2))
        self.assertEqual(L.eval("FA.Talents.Spent()"), 0)


# The first six pieces of the site's Arms warrior route for the Alliance (public/content/route/warrior.json), and the
# whole route as the code the design note's encoder writes for it (docs/gear-route.md): four drops from The Hall of Thanes
# (dungeon 3065), a quest two-hander, then a Deadmines drop.
ROUTE = [(271097, 13, "back", ("drop", 3065, 3493)), (270231, 13, "hands", ("drop", 3065, 3495)), (270260, 13, "legs", ("drop", 3065, 3496)),
         (270229, 13, "feet", ("drop", 3065, 3494)), (279895, 14, "mainhand", ("quest", 96393)), (273088, 17, "neck", ("drop", 43, 585))]
ROUTE_CODE = "FAG1-warrior-0-alliance-18wxddd0Nr0Ul18izdgd0Nr0Un18j2did0Nr0Uo18ixdjd0Nr0Um1aOreoqp4J192Ehbd00H09r"
WARRIOR_ARMS = ("FAG1-warrior-0-alliance-18wxddd0Nr0Ul18izdgd0Nr0Un18j2did0Nr0Uo18ixdjd0Nr0Um1aOreoqp4J192Ehbd00H09r02HJhed00A0Ij01Gchhd00H09s"
                "1c4bhkd00A0Ih00iEhld00A0If01SCiod00A0Ih01paicd00H09r02HUjid00H09s01DQmdd00x0Iq01OXmfq0kz19bEmjd00x0Ip01DXnld00x0Im19ecocd00y0Is"
                "01Noogd00M0Iz18fmsfq0jm01JRtod00L0IM01JQtad00L0IM19istbd01s0IH00o0ted00L0IO00Auvkd0330IP020vBad03307e02NMBcd0250IU054EBfd03307f"
                "01MaCoq0gZ02GCDid03307e02sQJcd03n09G04CCJgq1Pz02tLJlq0IE04BINfd05D06V04BHNkd05D06V0338Qed03I03I033rQgd03I03R033dQjd03I03I037yRoq14y"
                "03taWdd05j07O03u8Wfd05j07E03pYWhd03H0Nv04lSWid05j07O")


def lua_route(pieces, cls="warrior", spec=0, side="alliance"):
    """A route as a Lua table literal, pieces as ROUTE's tuples."""
    out = []
    for id_, level, slot, src in pieces:
        out.append("{ id = %d, level = %d, slot = '%s', from = { %s } }" % (id_, level, slot, ", ".join("'%s'" % x if isinstance(x, str) else str(x) for x in src)))
    return "{ cls = '%s', spec = %d, side = '%s', pieces = { %s } }" % (cls, spec, side, ", ".join(out))


class GearCode(unittest.TestCase):
    def read(self, text):
        return L.eval("function(t) local r, e, n = FA.GearCode.Read(t); return r, e, n end")(text)

    def routes(self, text):
        r, e, n = self.read(text)
        self.assertIsNone(e, text)
        out = []
        for route in r.values():
            pieces = [(p.id, p.level, p.slot, tuple(p["from"].values())) for p in route.pieces.values()]
            out.append((route.cls, route.spec, route.side, pieces))
        return out, list(n.values())

    def test_writes_and_reads_back(self):
        code = L.eval("function(r) return FA.GearCode.Write(r) end")(L.eval(lua_route(ROUTE)))
        self.assertEqual(code, ROUTE_CODE)
        routes, notes = self.routes(code)
        self.assertEqual(routes, [("warrior", 0, "alliance", ROUTE)])
        self.assertEqual(notes, [])

    def test_the_site_route_round_trips(self):
        routes, _ = self.routes(WARRIOR_ARMS)
        cls, spec, side, pieces = routes[0]
        self.assertEqual((cls, spec, side, len(pieces)), ("warrior", 0, "alliance", 43))
        self.assertEqual(pieces[:6], ROUTE)
        self.assertEqual(pieces[-1], (16732, 58, "legs", ("drop", 329, 484)))   # Stratholme; Forever's own ids, above 270000 and 2900, are in ROUTE
        self.assertEqual(L.eval("function(t) return FA.GearCode.Write((FA.GearCode.Read(t))[1]) end")(WARRIOR_ARMS), WARRIOR_ARMS)
        self.assertLess(len(WARRIOR_ARMS), 700)

    def test_every_slot_and_the_fields_edges(self):
        slots = list(L.eval("FA.GearCode.SLOTS").values())
        self.assertEqual(len(slots), 17)
        pieces = [(14776335, 60, slot, ("quest", 238327)) for slot in slots] + [(1, 1, "head", ("drop", 1, 238327))]
        code = L.eval("function(r) return FA.GearCode.Write(r) end")(L.eval(lua_route(pieces, "druid", 2, "horde")))
        self.assertRegex(code, r"^FAG1-druid-2-horde-[0-9A-Za-z]+$")
        self.assertEqual(code[len("FAG1-druid-2-horde-"):][:10], "ZZZZYaqZZZ")   # the biggest id, level 60, head, a quest
        self.assertEqual(self.routes(code)[0], [("druid", 2, "horde", pieces)])

    def test_several_codes_in_a_text(self):
        two = ROUTE_CODE + " and FAG1-warrior-1-horde-18wxddd0Nr0Ul"
        self.assertEqual([r[:3] for r in self.routes(two)[0]], [("warrior", 0, "alliance"), ("warrior", 1, "horde")])
        for pasted in [two, "  " + two + "\n", "`" + two + "`", "here: " + two + ". Enjoy!", "<" + two + ">", "\"" + two + "\"", "**" + two + "**", two + "-"]:
            self.assertEqual(len(self.routes(pasted)[0]), 2, pasted)
        both = "FAT2-70170-warrior-A-0a " + ROUTE_CODE   # a build code beside it is left to the build reader
        self.assertEqual(len(self.routes(both)[0]), 1)
        self.assertTrue(L.eval("function(t) return FA.GearCode.Find(t) end")(both))
        self.assertFalse(L.eval("function(t) return FA.GearCode.Find(t) end")("FAT2-70170-warrior-A-0a"))

    def test_write_refuses_what_the_code_cant_carry(self):
        write = L.eval("function(r) return FA.GearCode.Write(r) end")
        for pieces, why in [([(14776336, 13, "back", ("drop", 1, 1))], "item id"), ([(5, 0, "back", ("drop", 1, 1))], "no level"),
                            ([(5, 61, "back", ("drop", 1, 1))], "no level"), ([(5, 13, "tabard", ("drop", 1, 1))], "slot"),
                            ([(5, 13, "back", ("vendor", 1))], "somewhere"), ([(5, 13, "back", ("drop", 238328, 1))], "source id")]:
            code, err = write(L.eval(lua_route(pieces)))
            self.assertIsNone(code, pieces)
            self.assertIn(why, err)
        self.assertIn("no class", write(L.eval("{ cls = 'knight', spec = 0, side = 'alliance', pieces = {} }"))[1])
        self.assertIn("no spec", write(L.eval("{ cls = 'warrior', spec = 3, side = 'alliance', pieces = {} }"))[1])

    def test_too_many_pieces_are_cut(self):
        pieces = [(100 + i, 1 + i % 60, "back", ("quest", 7)) for i in range(125)]
        code = L.eval("function(r) return FA.GearCode.Write(r) end")(L.eval(lua_route(pieces)))
        routes, notes = self.routes(code)
        self.assertEqual(len(routes[0][3]), 120)
        self.assertEqual(notes, ["A route has 120 pieces at most, so the last 5 of route 1 were left out."])

    def test_errors(self):
        def say(text):
            r, e, _ = self.read(text)
            self.assertIsNone(r, text)
            return e
        self.assertIn("Paste a gear code", say(""))
        self.assertIn("isn't a gear code", say("hello"))
        self.assertIn("isn't a gear code", say("FAT2-70170-warrior-A-0a"))
        self.assertIn("isn't a gear code", say("FAG0-warrior-0-alliance-18wxddd0Nr0Ul"))
        self.assertIn("newer version", say("FAG2-warrior-0-alliance-18wxddd0Nr0Ul"))
        for bad in ["FAG1-", "FAG1-warrior", "FAG1-warrior-0", "FAG1-knight-0-alliance-18wxddd0Nr0Ul", "FAG1-warrior-3-alliance-18wxddd0Nr0Ul",
                    "FAG1-warrior-0-neutral-18wxddd0Nr0Ul", "FAG1-warrior-0-alliance-18wx.ddd"]:
            self.assertRegex(say(bad), r"Route 1 .* doesn't read", bad)
        self.assertEqual(say("FAG1-warrior-0-alliance-"), "Route 1 of that code has no pieces.")
        for cut in ["FAG1-warrior-0-alliance-18wxddd0Nr0U", "FAG1-warrior-0-alliance-18wxd", "FAG1-warrior-0-alliance-18wxddd0Nr0Ul1aOreoqp4"]:
            self.assertRegex(say(cut), r"Piece \d of route 1 .* cut off", cut)
        self.assertRegex(say("FAG1-warrior-0-alliance-18wxddd0Nr0Ul1aOreoqp4J192Ehbd00H09"), r"Piece 3 of route 1 .* cut off")
        for bad in ["FAG1-warrior-0-alliance-18wxdzd0Nr0Ul", "FAG1-warrior-0-alliance-18wxdxd0Nr0Ul", "FAG1-warrior-0-alliance-0000ddd0Nr0Ul", "FAG1-warrior-0-alliance-18wx0dd0Nr0Ul"]:
            self.assertRegex(say(bad), r"Piece 1 of route 1 .* doesn't read", bad)   # a slot past q, a level past 60, item 0, level 0


class Gear(unittest.TestCase):
    def setUp(self):
        L.run("RESET('traits')")

    def add(self, text):
        return L.eval("function(t) return FA.Gear.Add((assert(FA.GearCode.Read(t)))) end")(text)

    def test_add_find_and_forget(self):
        self.assertEqual(self.add(ROUTE_CODE + " FAG1-warrior-1-horde-18wxddd0Nr0Ul FAG1-mage-0-alliance-18wxddd0Nr0Ul"), (2, 1))
        kept = L.eval("function() local out = {} for _, r in ipairs(FA.Gear.RoutesFor('warrior')) do out[#out + 1] = r.spec .. '/' .. r.side .. ':' .. #r.pieces end return table.concat(out, ' ') end")
        self.assertEqual(kept(), "0/alliance:6 1/horde:1")
        self.assertEqual(self.add("FAG1-warrior-0-alliance-18wxddd0Nr0Ul"), (1, 0))   # the same spec and side again replaces it
        self.assertEqual(kept(), "0/alliance:1 1/horde:1")
        self.assertTrue(L.eval("FA.Gear.Forget('warrior', 1, 'horde')"))
        self.assertFalse(L.eval("FA.Gear.Forget('warrior', 1, 'horde')"))
        self.assertEqual(kept(), "0/alliance:1")
        self.assertEqual(L.eval("#FA.Gear.RoutesFor('mage')"), 1)

    def test_the_spec_is_the_builds_heaviest_tree(self):
        spec = L.eval("function(picks) return FA.Gear.BuildSpec({ picks = picks }) end")
        self.assertEqual(spec("010101" + "1212"), 0)
        self.assertEqual(spec("0101" + "121212" + "2b"), 1)
        self.assertEqual(spec("2b2b2b"), 2)
        self.assertIsNone(spec("0101" + "1212"))   # a tie
        self.assertIsNone(spec(""))
        self.assertIsNone(spec("zz"))
        self.assertIsNone(L.eval("FA.Gear.BuildSpec(nil)"))
        # the character's: the build it follows, or the one it chose
        self.assertEqual(L.eval("function() return FA.Gear.Spec() end")(), (None, None))
        L.run("FA.AddBuilds(assert(FA.Code.Read('FAT1-warrior-Fury-1212120101'))); FA.SetActive(1)")
        self.assertEqual(L.eval("function() return FA.Gear.Spec() end")(), (1, "build"))
        L.run("FA.Gear.SetSpec(2)")
        self.assertEqual(L.eval("function() return FA.Gear.Spec() end")(), (2, "chosen"))
        L.run("FA.Gear.SetSpec(nil)")
        self.assertEqual(L.eval("function() return FA.Gear.Spec() end")(), (1, "build"))
        self.assertEqual(L.eval("FA.Gear.SpecName(1)"), "Fury")
        L.run("API = 'none'; FA.Talents.Forget()")
        self.assertEqual(L.eval("FA.Gear.SpecName(1)"), "spec 2")
        L.run("API = 'traits'; FA.Talents.Forget()")

    def test_the_characters_route(self):
        why = L.eval("function() local r, why = FA.Gear.Route(); return r and 'route' or why end")
        self.assertIn("No gear route for this class yet", why())
        self.add(ROUTE_CODE)
        self.assertIn("Pick a spec", why())
        L.run("FA.Gear.SetSpec(1)")
        self.assertIn("No Fury route for Alliance here yet", why())
        L.run("FA.Gear.SetSpec(0)")
        self.assertEqual(why(), "route")
        L.run("FACTION = 'Horde'")
        self.assertIn("No Arms route for Horde", why())
        L.run("FACTION = nil")
        self.assertIn("hasn't said which side", why())
        self.assertEqual(L.eval("FA.Gear.Side()"), None)
        L.run("FACTION = 'Horde'")
        self.assertEqual(L.eval("FA.Gear.Side()"), "horde")

    def test_owned_is_what_is_worn_and_carried(self):
        L.run("EQUIPPED = { [1] = 6686, [16] = 6687 }; BAGS = { [0] = { 1156, nil, 7003 }, [3] = { [16] = 2262 } }")
        owned = L.eval("function() local out = {} for id in pairs(FA.Gear.Owned()) do out[#out + 1] = id end table.sort(out) return table.concat(out, ' ') end")
        self.assertEqual(owned(), "1156 2262 6686 6687 7003")
        L.run("EQUIPPED, BAGS = {}, {}")
        self.assertEqual(owned(), "")

    # A made-up route: two one-handers and a shield, then a two-hander at 20 that puts the shield away, a second shield at
    # 23, and a head piece at 30
    PLAN = [(11, 10, "mainhand", ("quest", 1)), (12, 12, "offhand", ("drop", 36, 2747)), (13, 15, "mainhand", ("drop", 36, 2745)),
            (14, 20, "mainhand", ("quest", 2)), (15, 23, "offhand", ("quest", 3)), (16, 30, "head", ("drop", 43, 585))]

    def plan(self, level):
        return L.eval("function(route, level) local p = FA.Gear.Plan(route, level); local out = { worn = p.worn, had = p.had, get = {}, coming = {}, slots = {} } "
                      "for i, x in ipairs(p.get) do out.get[i] = x.id end for i, x in ipairs(p.coming) do out.coming[i] = x.id end "
                      "for slot, s in pairs(p.slots) do if s.now or s.next then out.slots[slot] = (s.now and s.now.id or '-') .. '/' .. (s.next and s.next.id or '-') .. (s.had and ' had' or '') end end return out end")(
            L.eval(lua_route(self.PLAN)), level)

    def slots(self, p):
        return dict(p.slots.items())

    def test_next_pieces_at_a_level(self):
        L.run("ITEMS = { [14] = { 'Big Axe', 'INVTYPE_2HWEAPON' }, [11] = { 'Sword', 'INVTYPE_WEAPON' } }")
        p = self.plan(9)
        self.assertEqual((p.worn, p.had, list(p.get.values()), list(p.coming.values())), (0, 0, [], [11, 12, 13, 14, 15, 16]))
        self.assertEqual(self.slots(p), {"mainhand": "-/11", "offhand": "-/12", "head": "-/16"})
        p = self.plan(12)
        self.assertEqual(self.slots(p), {"mainhand": "11/13", "offhand": "12/15", "head": "-/16"})
        self.assertEqual((list(p.get.values()), list(p.coming.values()), p.worn), ([11, 12], [13, 14, 15, 16], 2))
        p = self.plan(15)
        self.assertEqual(self.slots(p)["mainhand"], "13/14")
        # the two-hander at 20 puts the shield away, until the next shield at 23
        p = self.plan(21)
        self.assertEqual(self.slots(p), {"mainhand": "14/-", "offhand": "-/15", "head": "-/16"})
        self.assertEqual((list(p.get.values()), p.worn), ([14], 1))
        p = self.plan(23)
        self.assertEqual(self.slots(p), {"mainhand": "14/-", "offhand": "15/-", "head": "-/16"})
        p = self.plan(60)
        self.assertEqual(self.slots(p), {"mainhand": "14/-", "offhand": "15/-", "head": "16/-"})
        self.assertEqual((list(p.get.values()), list(p.coming.values())), ([14, 15, 16], []))
        # a main hand the game hasn't loaded yet counts as one-handed, so the shield shows
        L.run("ITEMS = {}")
        self.assertEqual(self.slots(self.plan(21))["offhand"], "12/15")

    def test_had_is_worn_or_carried(self):
        L.run("ITEMS = { [14] = { 'Big Axe', 'INVTYPE_2HWEAPON' } }; EQUIPPED = { [16] = 14 }; BAGS = { [0] = { 16 } }")
        p = self.plan(60)
        self.assertEqual(self.slots(p), {"mainhand": "14/- had", "offhand": "15/-", "head": "16/- had"})
        self.assertEqual((p.worn, p.had, list(p.get.values())), (3, 2, [15]))
        # the sets can be given, as the panel's tests do
        given = L.eval("function(route) local p = FA.Gear.Plan(route, 60, { [15] = true }, function() return false end); return p.had, p.slots.offhand.had, p.slots.mainhand.had end")(L.eval(lua_route(self.PLAN)))
        self.assertEqual(given, (1, True, False))

    def test_where_a_piece_comes_from(self):
        text = L.eval("function(p, names) return FA.Gear.SourceText(p, names) end")
        drop = L.eval("{ from = { 'drop', 36, 2747 } }")
        quest = L.eval("{ from = { 'quest', 1275 } }")
        names = L.eval("{ dungeon = function(id) return id == 36 and 'Deadmines' or nil end, npc = function(id) return id == 2747 and 'Edwin VanCleef' or nil end, quest = function(id) return 'The Defias Brotherhood' end }")
        self.assertEqual(text(drop, names), "Deadmines: Edwin VanCleef")
        self.assertEqual(text(quest, names), "Quest: The Defias Brotherhood")
        self.assertEqual(text(L.eval("{ from = { 'drop', 3065, 3493 } }"), names), "dungeon 3065: NPC 3493")
        # without the game's names (none of its lookups here), the ids
        self.assertEqual(text(drop, None), "dungeon 36: NPC 2747")
        self.assertEqual(text(quest, None), "Quest: #1275")
        self.assertEqual(text(L.eval("{ from = { 'vendor', 1 } }"), None), "?")


UI_STUB = r"""
-- Any frame: every method answers a new frame, except the few whose answers get used as numbers, text or flags. What the
-- addon sets is kept for the tests to read: text, shown, size, alpha, vertex colour, texture, anchors, scripts, and the
-- frames and regions a frame has (children, regions), so an overlay on a talent's button can be found.
local ANSWERS = { GetFrameLevel = 1, GetWidth = 400, GetText = "", GetChecked = true, GetID = 1 }
SHOWN, POPUPS, HOOKS = {}, {}, {}
local frame
local function keep(field) return function(self, ...) rawset(self, field, (...)) end end
local function region(self)
  local r = frame()
  rawset(r, "parent", self)
  self.regions[#self.regions + 1] = r
  return r
end
frame = function(name)
  local f = { name = name, children = {}, regions = {}, points = {} }
  return setmetatable(f, { __index = function(t, k)
    if ANSWERS[k] ~= nil then return function() return ANSWERS[k] end end
    if k == "IsShown" then return function(self) return rawget(self, "shown") ~= false end end
    if k == "SetText" then return keep("text") end
    if k == "SetAlpha" then return keep("alpha") end
    if k == "SetTexture" then return keep("texture") end
    if k == "SetHeight" then return keep("height") end
    if k == "SetWidth" then return keep("width") end
    if k == "SetFrameLevel" then return keep("level") end
    if k == "SetVertexColor" then return function(self, r, g, b) rawset(self, "color", { r, g, b }) end end
    if k == "SetColorTexture" then return function(self, r, g, b) rawset(self, "texture", "color"); rawset(self, "color", { r, g, b }) end end
    if k == "SetSize" then return function(self, w, h) rawset(self, "width", w); rawset(self, "height", h) end end
    if k == "SetShown" then return function(self, on) rawset(self, "shown", on and true or false) end end
    if k == "SetPoint" then return function(self, ...) self.points[#self.points + 1] = { ... } end end
    if k == "ClearAllPoints" then return function(self) rawset(self, "points", {}) end end
    if k == "CreateTexture" or k == "CreateFontString" then return region end
    if k == "Enable" then return function(self) rawset(self, "enabled", true) end end
    if k == "Disable" then return function(self) rawset(self, "enabled", false) end end
    if k == "Show" then return function(self) rawset(self, "shown", true) end end
    if k == "Hide" then return function(self) rawset(self, "shown", false) end end
    if k == "SetScript" then return function(self, event, fn) local s = rawget(self, "scripts") or {}; rawset(self, "scripts", s); s[event] = fn end end
    if k == "HookScript" then return function(self, event, fn) HOOKS[#HOOKS + 1] = fn end end
    return function() return frame() end
  end })
end
CreateFrame = function(kind, name, parent)
  local f = frame(name)
  rawset(f, "kind", kind)
  if parent then rawset(f, "parent", parent); parent.children[#parent.children + 1] = f end
  if name then _G[name] = f end
  return f
end
UIParent, GameTooltip, ChatFontNormal = frame("UIParent"), frame("GameTooltip"), frame()
-- the tooltip keeps what was put in it: TIP = { owner, spell, text, lines = { ... }, shown }
TIP = { lines = {} }
GameTooltip.SetOwner = function(_, owner) TIP = { owner = owner, lines = {} } end
GameTooltip.SetSpellByID = function(_, id) TIP.spell = id end
GameTooltip.SetText = function(_, text) TIP.text = text end
GameTooltip.AddLine = function(_, text) TIP.lines[#TIP.lines + 1] = text end
GameTooltip.Show = function() TIP.shown = true end
GameTooltip.Hide = function() TIP.shown = false end
UISpecialFrames = {}
tinsert = table.insert
local hook = hooksecurefunc
hooksecurefunc = function(a, b, c) HOOKS[#HOOKS + 1] = c or b; return hook(a, b, c) end
StaticPopup_Show = function(which, text, _, data) POPUPS[#POPUPS + 1] = { which = which, text = text, data = data } end
PlayerSpellsFrame = frame("PlayerSpellsFrame")
PlayerSpellsFrame.TalentsFrame = frame("TalentsFrame")
-- the talent window's buttons are pooled: one a node, the same each time it's asked for. LIT is the node last asked for.
BUTTONS = {}
PlayerSpellsFrame.TalentsFrame.GetTalentButtonByNodeID = function(self, nodeID)
  LIT = nodeID
  BUTTONS[nodeID] = BUTTONS[nodeID] or frame()
  return BUTTONS[nodeID]
end
Settings = { RegisterCanvasLayoutCategory = function() return frame() end, RegisterAddOnCategory = function() end, OpenToCategory = function() end }
-- the captions the slider template gives its slider (the template names them $parentLow and so on): the first slider's
-- are here and the second's aren't, so the settings page is tried with a template that has them and one that doesn't
ForeverArmouryStripPastLow, ForeverArmouryStripPastHigh, ForeverArmouryStripPastText = frame(), frame(), frame()
-- the Legacy window: its tree panel shows one tree (LSHOWN_TREE) and has a button for that tree's perks only, pooled by
-- node as the talent window's are; LBUTTONS[node] is the button. ToggleLegacySystemUI opens or closes the window.
LegacySystemFrame = frame("LegacySystemFrame")
LegacySystemFrame.TreePage = { LegacyTreeTraitPanel = frame("LegacyTreeTraitPanel") }
LBUTTONS, LSHOWN_TREE = {}, 1187
LegacySystemFrame.TreePage.LegacyTreeTraitPanel.GetTalentButtonByNodeID = function(self, nodeID)
  for _, p in ipairs(FA.Legacy.PERKS) do
    if p.node == nodeID and p.tree == LSHOWN_TREE then LBUTTONS[nodeID] = LBUTTONS[nodeID] or frame(); return LBUTTONS[nodeID] end
  end
  return nil
end
ToggleLegacySystemUI = function()
  LTOGGLED = (LTOGGLED or 0) + 1
  if LegacySystemFrame.shown == false then LegacySystemFrame:Show() else LegacySystemFrame:Hide() end
end
CharacterFrame = frame("CharacterFrame")
ToggleCharacter = function() TOGGLED = (TOGGLED or 0) + 1 end
"""


def lua_table(d):
    """A dict of perk name -> rank as the Lua table literal the stub's LPLAN and LSET take."""
    return "{ " + ", ".join('["%s"] = %d' % (k, v) for k, v in d.items()) + " }"


SAMPLE = "FAL1-70425-Gatherer%27s%20Path-150000000051000000030001000"   # forever-armoury PR 1585, byte for byte
SAMPLE_RANKS = "150000000051000000030001000"
SAMPLE_2 = "FAL1-70425-Second-" + "0" * 19 + "1" + "0" * 7                                      # Gourmand, one rank
GATHERER = {"Master Chef": 1, "Working Overtime": 5, "Well Rested": 5, "Talented": 1, "Gourmand": 3, "The Quick and the Dead": 1}


class LegacyCode(unittest.TestCase):
    """LegacyCode.lua: a Legacy plan code as the site's public/content/legacy-code.js writes it (forever-armoury #1566)."""

    def setUp(self):
        L.run("RESET('traits')")

    def read(self, text):
        return L.eval("""function(t)
          local plans, err, notes = FA.LegacyCode.Read(t)
          if not plans then return nil, err, '' end
          local out = {}
          for i, p in ipairs(plans) do out[i] = p.name .. '|' .. p.ranks .. '|' .. p.build end
          return table.concat(out, '\\n'), nil, table.concat(notes, '\\n')
        end""")(text)

    def plans(self, text):
        got, err, notes = self.read(text)
        self.assertIsNone(err, text)
        return got.split("\n"), notes

    def error(self, text):
        got, err, _ = self.read(text)
        self.assertIsNone(got, text)
        return err

    def write(self, name, ranks=SAMPLE_RANKS, build=None):
        return L.eval("function(name, ranks, build) return FA.LegacyCode.Write({ { name = name, ranks = ranks } }, build) end")(name, ranks, build)

    def test_the_sites_sample_reads_and_writes_byte_for_byte(self):
        self.assertEqual(self.plans(SAMPLE), (["Gatherer's Path|" + SAMPLE_RANKS + "|70425"], ""))
        self.assertEqual(self.write("Gatherer's Path"), SAMPLE)
        write = L.eval("function(t) return FA.LegacyCode.Write(assert(FA.LegacyCode.Read(t))) end")
        self.assertEqual(write(SAMPLE), SAMPLE)

    def test_round_trips_names_and_an_empty_plan(self):
        for name in ["Gatherer's Path", "", "Mage's build, 31/0/20!", "Ünïcödé 🙂 名前", "a" * 40, "50% crit", "-leading-dashes-", "dots.in.name", "  Two   words "]:
            code = self.write(name)
            self.assertRegex(code, r"^FAL1-70425-[A-Za-z0-9%]*-[0-9a-z]{27}$", name)
            self.assertEqual(self.plans(code), (["%s|%s|70425" % (" ".join(name.split()), SAMPLE_RANKS)], ""), name)
        empty = "0" * 27
        self.assertEqual(self.write("", empty), "FAL1-70425--" + empty)
        self.assertEqual(self.plans("FAL1-70425--" + empty), (["|" + empty + "|70425"], ""))
        # every character a chat would format comes out as %XX, and a name with spaces keeps one
        code = self.write("*bold* _it_ ||spoil|| `c` [a](b) https://a.b/c é 🙂")
        self.assertRegex(code, r"^FAL1-70425-[A-Za-z0-9%]*-[0-9a-z]{27}$")

    def test_write_with_a_build(self):
        self.assertEqual(self.write("A", SAMPLE_RANKS, 70001), "FAL1-70001-A-" + SAMPLE_RANKS)
        self.assertEqual(self.plans("FAL1-70001-A-" + SAMPLE_RANKS)[0], ["A|" + SAMPLE_RANKS + "|70001"])
        write = L.eval("function(a, b) return FA.LegacyCode.Write({ { name = 'A', ranks = a }, { name = 'B', ranks = b } }) end")
        self.assertEqual(write(SAMPLE_RANKS, "0" * 27), "FAL1-70425-A-" + SAMPLE_RANKS + ".B-" + "0" * 27)

    def test_the_writer_refuses_ranks_without_the_shape(self):
        for bad in ["", "0" * 26, "0" * 28, "A" * 27, "0" * 26 + "-", "0" * 26 + "%"]:
            code, why = L.eval("function(r) return FA.LegacyCode.Write({ { name = 'A', ranks = r } }) end")(bad)
            self.assertIsNone(code, bad)
            self.assertIn("doesn't have 27 ranks", why)

    def test_a_long_name_is_cut_to_40_characters_with_a_note(self):
        got, notes = self.plans("FAL1-70425-" + "a" * 50 + "-" + SAMPLE_RANKS)
        self.assertEqual(got, ["a" * 40 + "|" + SAMPLE_RANKS + "|70425"])
        self.assertEqual(notes, "The name of plan 1 was cut to 40 characters.")
        self.assertEqual(self.plans("FAL1-70425-" + "%C3%A9" * 50 + "-" + SAMPLE_RANKS)[0], ["é" * 40 + "|" + SAMPLE_RANKS + "|70425"])
        self.assertEqual(self.plans("FAL1-70425-" + "a" * 40 + "-" + SAMPLE_RANKS)[1], "")
        self.assertEqual(self.write("a" * 60), "FAL1-70425-" + "a" * 40 + "-" + SAMPLE_RANKS)

    def test_a_paste_around_the_code(self):
        for pasted in [SAMPLE, "  " + SAMPLE + "\n", "`" + SAMPLE + "`", "here: " + SAMPLE + ". Enjoy!", "<" + SAMPLE + ">", "\"" + SAMPLE + "\"",
                       "Plan\n" + SAMPLE + "\nthanks", "**" + SAMPLE + "**", "here it is - " + SAMPLE + "-", SAMPLE + ".-.-"]:
            self.assertEqual(self.plans(pasted)[0], ["Gatherer's Path|" + SAMPLE_RANKS + "|70425"], pasted)

    def test_several_plans_in_one_code_or_in_a_paste(self):
        fisher = "0000" + "5" + "0" * 22
        one = "FAL1-70425-Gatherer%27s%20Path-" + SAMPLE_RANKS + ".Fisher-" + fisher + "." + "-" + "0" * 27
        self.assertEqual(self.plans(one)[0], ["Gatherer's Path|%s|70425" % SAMPLE_RANKS, "Fisher|%s|70425" % fisher, "|%s|70425" % ("0" * 27)])
        two = SAMPLE + " and\n" + "FAL1-70001-Fisher-" + fisher
        self.assertEqual(self.plans(two)[0], ["Gatherer's Path|%s|70425" % SAMPLE_RANKS, "Fisher|%s|70001" % fisher])

    def test_a_code_from_another_build_reads_and_carries_its_build(self):
        # the ranks of another build can't be checked against this one's perks
        over = "9" * 27
        self.assertEqual(self.plans("FAL1-70001-Old-" + over)[0], ["Old|" + over + "|70001"])
        self.assertEqual(self.plans("FAL1-12345678-Old-" + SAMPLE_RANKS)[0], ["Old|%s|12345678" % SAMPLE_RANKS])

    def test_a_rank_past_what_its_perk_takes_is_refused_for_the_build_the_addon_knows(self):
        err = self.error("FAL1-70425-Over-" + "6" + "0" * 26)
        self.assertEqual(err, "Plan 1 of that code has more ranks of Master Chef than the perk takes (5). Copy the whole code again.")
        # Bartering (the third) takes 2; the most of every perk is fine
        self.assertIn("Bartering", self.error("FAL1-70425-Over-00" + "3" + "0" * 24))
        full = L.eval("function() local out = {} for i, p in ipairs(FA.Legacy.PERKS) do out[i] = string.format('%d', p.max) end return table.concat(out) end")()
        self.assertEqual(self.plans("FAL1-70425-Full-" + full)[0], ["Full|%s|70425" % full])

    def test_errors_say_why(self):
        say = self.error
        self.assertIn("Paste a Legacy plan code", say(""))
        self.assertIn("Paste a Legacy plan code", say("  \n"))
        self.assertIn("isn't a Legacy plan code", say("hello there"))
        self.assertIn("isn't a Legacy plan code", say("https://foreverarmoury.app/legacy/" + SAMPLE_RANKS))
        self.assertIn("isn't a Legacy plan code", say("FAT3-70170-warrior-Arms-0a-0"))
        self.assertIn("isn't a Legacy plan code", say("FAL-Gatherer-" + SAMPLE_RANKS))
        self.assertIn("isn't a Legacy plan code", say("FAL0-70425--" + SAMPLE_RANKS))
        self.assertIn("newer version", say("FAL2-70425--" + SAMPLE_RANKS))
        self.assertIn("newer version", say("FAL999-70425--" + SAMPLE_RANKS))
        for bad in ["FAL1-", "FAL1-70425", "FAL1-Gatherer-" + SAMPLE_RANKS, "FAL1-x-Gatherer-" + SAMPLE_RANKS, "FAL1-123456789-A-" + SAMPLE_RANKS,
                    "FAL1-70425-Gatherer", "FAL1-70425-" + SAMPLE_RANKS]:
            self.assertRegex(say(bad), r"doesn't read.*cut off", bad)
        whole = SAMPLE
        self.assertRegex(say(whole[:-1]), r"Plan 1 .* doesn't read.*cut off")          # one rank short
        self.assertRegex(say(whole[:-12]), r"Plan 1 .* doesn't read")                  # cut off in the ranks
        self.assertRegex(say(whole[:whole.index("-", 6) + 4]), r"doesn't read")        # cut off in the name
        self.assertRegex(say(whole + "0"), r"Plan 1 .* doesn't read")                  # one rank too many
        self.assertRegex(say("FAL1-70425-Gatherer-" + SAMPLE_RANKS.upper().replace("0", "Z")), r"Plan 1 .* doesn't read")
        self.assertRegex(say(whole + ".Fisher"), r"Plan 2 .* doesn't read")
        self.assertRegex(say(whole + ".Fisher-" + SAMPLE_RANKS + "0"), r"Plan 2 .* doesn't read")
        self.assertRegex(say(whole + "..Fisher-" + SAMPLE_RANKS), r"Plan 2 .* doesn't read")
        for bad in ["Gath%2", "Ga%ZZth", "%FF%FE", "%C3"]:
            self.assertRegex(say("FAL1-70425-" + bad + "-" + SAMPLE_RANKS), r"name of plan 1 .* cut off", bad)
        # a good plan after a bad one in a paste doesn't hide it
        self.assertRegex(say(whole[:-1] + " " + whole), r"Plan 1 .* doesn't read")

    def test_find_says_whether_a_text_has_a_legacy_code(self):
        find = L.eval("function(t) return FA.LegacyCode.Find(t) end")
        self.assertTrue(find("see " + SAMPLE))
        self.assertTrue(find("FAL9-"))
        self.assertFalse(find("FAT3-70170-warrior-A-0a-0 FAG1-warrior-0"))
        self.assertFalse(find(""))

    def test_a_long_run_of_dots_reads_at_once(self):
        timed = L.eval("function(t) local c = os.clock(); local p, e = FA.LegacyCode.Read(t); return p and #p, e, os.clock() - c end")
        n, err, seconds = timed(SAMPLE + "." * 200000)
        self.assertEqual(n, 1)
        self.assertLess(seconds, 1)
        n, err, seconds = timed("FAL1-" + ".-" * 100000 + "a")
        self.assertIsNone(n)
        self.assertLess(seconds, 1)

    def test_names_encode_the_same_under_every_locale(self):
        # %w follows the C locale: under a UTF-8 one it takes bytes above 127 for letters (as BuildCode's test says)
        before = locale.setlocale(locale.LC_CTYPE)
        tried = []
        try:
            for name in ["C", "en_US.UTF-8", "C.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8", "ja_JP.UTF-8"]:
                try:
                    locale.setlocale(locale.LC_CTYPE, name)
                except locale.Error:
                    continue
                tried.append(name)
                self.assertEqual(self.write("Ünï 名"), "FAL1-70425-%C3%9Cn%C3%AF%20%E5%90%8D-" + SAMPLE_RANKS, name)
                self.assertEqual(self.plans(SAMPLE + "—and more")[0], ["Gatherer's Path|%s|70425" % SAMPLE_RANKS], name)
        finally:
            locale.setlocale(locale.LC_CTYPE, before)
        self.assertIn("C", tried)


class Legacy(unittest.TestCase):
    """Legacy.lua: the account's plans, where it is on one, and Apply across the three Legacy trees' configs."""

    def setUp(self):
        L.run("RESET('traits'); LEGACY_ON = true")

    def steps(self, byName, build=70425):
        """The steps Progress lists for a plan, a line each: tree, perk and the rank it makes."""
        return L.eval("""function(build)
          local p, why = FA.Legacy.Progress({ name = 'P', ranks = LPLAN(%s), build = build })
          if not p then return nil, why end
          local out = {}
          for i, s in ipairs(p.steps) do out[i] = s.tree.name:sub(1, 3) .. ' ' .. s.name .. ' ' .. s.rank end
          return table.concat(out, '\\n'), p.over, #p.blocked
        end""" % lua_table(byName))(build)

    def apply(self, byName, build=70425):
        return L.eval("function(build) return FA.ApplyLegacy({ name = 'P', id = 1, ranks = LPLAN(%s), build = build }) end" % lua_table(byName))(build)

    def log(self):
        return [v for _, v in sorted(L.eval("LOG").items())]

    def account(self):
        """The account's committed ranks by perk name, those above 0."""
        return {k: v for k, v in L.eval("function() local out = {} for _, p in ipairs(FA.Legacy.PERKS) do if (LEG[p.node] or 0) > 0 then out[p.name] = LEG[p.node] end end return out end")().items()}

    # ---- the perks
    def test_the_table_is_of_the_sites_build_and_order(self):
        self.assertEqual(L.eval("FA.Legacy.BUILD"), 70425)
        self.assertEqual(L.eval("FA.Legacy.CLIENT"), "1.60.1.70425")
        self.assertEqual(L.eval("#FA.Legacy.PERKS"), 27)
        names = L.eval("function() local out = {} for i, p in ipairs(FA.Legacy.PERKS) do out[i] = p.name end return out end")()
        at = lambda i: names[i]
        # the sample plan's places, as the site's own test checks them in the data
        self.assertEqual([at(1), at(2), at(11), at(12), at(20), at(24)], ["Master Chef", "Working Overtime", "Well Rested", "Talented", "Gourmand", "The Quick and the Dead"])
        trees = L.eval("function() local out = {} for i, p in ipairs(FA.Legacy.PERKS) do out[i] = p.tree end return table.concat(out, ',') end")()
        self.assertEqual(trees, ",".join(["1187"] * 9 + ["1188"] * 9 + ["1189"] * 9))
        # nodes, max ranks and the locked ones (the game's "Unknown" perks)
        node = lambda i: L.eval("FA.Legacy.PERKS[%d].node" % i)
        self.assertEqual([node(1), node(2), node(12), node(19), node(27)], [110289, 110290, 110298, 110319, 110314])
        self.assertEqual(L.eval("FA.Legacy.PERKS[12].node"), L.eval("FA.TALENTED_NODE"))   # the perk the addon reads for the first level
        self.assertEqual(sum(L.eval("FA.Legacy.PERKS[%d].max" % i) for i in range(1, 28)), 5 + 5 + 2 + 1 + 5 + 3 + 1 + 1 + 2 + 2 + 5 + 5 + 1 + 1 + 5 + 3 + 1 + 2 + 5 + 3 + 2 + 1 + 1 + 2 + 1 + 5 + 5)
        self.assertEqual([i for i in range(1, 28) if L.eval("FA.Legacy.PERKS[%d].locked" % i)], [7, 8, 13, 14, 22, 23])
        # a perk's prerequisite is another perk of its tree
        self.assertEqual(L.eval("FA.Legacy.PERKS[4].afterIndex"), 3)    # Dedicated Study after Bartering
        self.assertEqual(L.eval("FA.Legacy.PERKS[12].afterIndex"), 11)  # Talented after Well Rested
        self.assertIsNone(L.eval("FA.Legacy.PERKS[1].afterIndex"))

    # ---- the plans kept for the account
    def test_plans_are_kept_for_the_account_and_one_is_followed(self):
        L.run("FA.Legacy.Add({ { name = 'A', ranks = LPLAN({ ['Working Overtime'] = 5 }), build = 70425 }, { name = 'B', ranks = LPLAN({}), build = 70001 } })")
        self.assertEqual(L.eval("#FA.Legacy.Plans()"), 2)
        self.assertEqual(L.eval("FA.Legacy.Plans()[1].id"), 1)
        L.run("FA.Legacy.SetActive(2)")
        self.assertEqual(L.eval("FA.Legacy.Active().name"), "B")
        # pasting a plan again as the site has it now updates its build and keeps its id, and the follow
        L.run("FA.Legacy.Add({ { name = 'B', ranks = LPLAN({}), build = 70425 } })")
        self.assertEqual((L.eval("#FA.Legacy.Plans()"), L.eval("FA.Legacy.Active().build"), L.eval("FA.Legacy.Active().id")), (2, 70425, 2))
        # the same ranks under another name is another plan
        L.run("FA.Legacy.Add({ { name = 'C', ranks = LPLAN({}), build = 70425 } })")
        self.assertEqual(L.eval("#FA.Legacy.Plans()"), 3)
        self.assertTrue(L.eval("FA.Legacy.Forget(2)"))
        self.assertIsNone(L.eval("FA.Legacy.Active()"))
        self.assertFalse(L.eval("FA.Legacy.Forget(99)"))
        self.assertEqual(L.eval("FA.Legacy.Plans()[2].name"), "C")

    def test_plans_are_account_wide_not_a_classes(self):
        L.run("FA.Legacy.Add({ { name = 'A', ranks = LPLAN({}), build = 70425 } }); FA.class = 'mage'")
        self.assertEqual(L.eval("#FA.Legacy.Plans()"), 1)
        L.run("FA.class = 'warrior'")

    def test_saved_plans_that_are_damaged_are_dropped_or_repaired_at_load(self):
        ranks = SAMPLE_RANKS
        L.run("""FA.db.legacy = {
          'junk', { name = 'Short', ranks = '0101', build = 70425 }, { name = 'Caps', ranks = '%s', build = 70425 },
          { name = 5, ranks = '%s', build = 'x', id = 4 }, { name = 'Dup', ranks = '%s', build = 70001, id = 4 }, { name = 'Fine', ranks = '%s', build = 70425, id = 9 } }
          FA.db.legacyFollow = 9; FA.db.nextId = 2""" % ("A" * 27, ranks, ranks, ranks))
        dropped, repaired = L.eval("function() return FA.Legacy.Repair() end")()
        self.assertEqual((dropped, repaired), (3, 2))
        names = [(p.name, p.build) for p in L.eval("FA.db.legacy").values()]
        self.assertEqual(names, [("", 0), ("Dup", 70001), ("Fine", 70425)])
        ids = [p.id for p in L.eval("FA.db.legacy").values()]
        self.assertEqual(len(set(ids)), 3)
        self.assertGreater(L.eval("FA.db.nextId"), max(ids))
        self.assertEqual(L.eval("FA.db.legacyFollow"), 9)
        L.run("FA.db.legacyFollow = 777; FA.Legacy.Repair()")
        self.assertIsNone(L.eval("FA.db.legacyFollow"))
        # at load, FA.Init says so
        L.run("PRINTED = ''; ForeverArmouryDB = { legacy = { 'junk', { name = 'A', ranks = '%s', build = 70425 } } }; FA.Init()" % ranks)
        self.assertIn("Your saved Legacy plans were damaged: dropped 1 saved Legacy plan it couldn't read, and repaired 1 saved Legacy plan with a missing name, build or id.", L.eval("PRINTED"))
        L.run("ForeverArmouryDB = { legacy = 5 }; FA.Init()")
        self.assertEqual(L.eval("#FA.db.legacy"), 0)

    def test_export_gives_a_code_a_build(self):
        self.assertIsNone(L.eval("FA.Legacy.Export()"))
        L.run("""FA.Legacy.Add({ { name = "Gatherer's Path", ranks = '%s', build = 70425 }, { name = 'Old', ranks = LPLAN({}), build = 70001 },
          { name = 'Second', ranks = LPLAN({ Gourmand = 1 }), build = 70425 } })""" % SAMPLE_RANKS)
        lines = L.eval("FA.Legacy.Export()").split("\n")
        self.assertEqual(lines, [SAMPLE + ".Second-" + "0" * 19 + "1" + "0" * 7, "FAL1-70001-Old-" + "0" * 27])
        # and it reads back as the plans that were kept
        got = L.eval("function(t) local plans = FA.LegacyCode.Read(t); return #plans end")("\n".join(lines))
        self.assertEqual(got, 3)

    # ---- where the account is on a plan
    def test_a_plan_from_nothing_lists_every_rank_in_an_order_the_game_takes(self):
        L.run("LEGACY_ON = true")
        steps, over, blocked = self.steps(GATHERER)
        self.assertEqual(steps.split("\n"),
                         ["Pro Working Overtime 1", "Pro Working Overtime 2", "Pro Working Overtime 3", "Pro Working Overtime 4", "Pro Working Overtime 5", "Pro Master Chef 1",   # Master Chef wants 5 points on the tree first
                          "Adv Well Rested 1", "Adv Well Rested 2", "Adv Well Rested 3", "Adv Well Rested 4", "Adv Well Rested 5", "Adv Talented 1",                            # and Talented a full Well Rested
                          "Res Gourmand 1", "Res Gourmand 2", "Res Gourmand 3", "Res The Quick and the Dead 1"])
        self.assertEqual((over, blocked), (0, 0))
        p = L.eval("""function() local p = FA.Legacy.Progress({ ranks = LPLAN({ ['Master Chef'] = 1, ['Working Overtime'] = 5 }), build = 70425 })
          return p.wanted, p.had, p.spent, p.perks[1].want, p.perks[2].want, p.perks[2].have end""")()
        self.assertEqual(p, (6, 0, 0, 1, 5, 0))

    def test_a_perk_waits_for_its_points_and_rows_come_in_order(self):
        # Bartering (row 2) wants 5 points on the tree first, which Working Overtime gives; Bountiful Harvest (row 3) wants none
        steps, _, blocked = self.steps({"Working Overtime": 5, "Bountiful Harvest": 2, "Bartering": 2})
        self.assertEqual(steps.split("\n"), ["Pro Working Overtime %d" % n for n in range(1, 6)] + ["Pro Bartering 1", "Pro Bartering 2", "Pro Bountiful Harvest 1", "Pro Bountiful Harvest 2"])
        self.assertEqual(blocked, 0)
        # Dedicated Study wants a full Bartering and 10 points on the tree
        # Dedicated Study (row 2) wants a full Bartering and 10 points on the tree's other perks: it comes the moment they are
        # there, ahead of the rest of Bountiful Harvest (row 3), which has been taking the points meanwhile
        steps, _, blocked = self.steps({"Working Overtime": 5, "Bountiful Harvest": 5, "Bartering": 2, "Dedicated Study": 1})
        lines = steps.split("\n")
        self.assertEqual(lines[lines.index("Pro Bountiful Harvest 3") + 1:], ["Pro Dedicated Study 1", "Pro Bountiful Harvest 4", "Pro Bountiful Harvest 5"])
        self.assertEqual(blocked, 0)

    def test_a_part_done_plan_lists_what_is_left(self):
        L.run("LSET({ ['Working Overtime'] = 5, ['Well Rested'] = 2 })")
        steps, over, blocked = self.steps(GATHERER)
        lines = steps.split("\n")
        self.assertEqual(lines[0], "Pro Master Chef 1")
        self.assertEqual(lines[1:4], ["Adv Well Rested 3", "Adv Well Rested 4", "Adv Well Rested 5"])
        self.assertEqual(len(lines), 16 - 7)
        # more than the plan has: counted, never taken back
        L.run("LSET({ ['Reinforce'] = 3, ['Field Guide'] = 1 })")
        steps, over, blocked = self.steps(GATHERER)
        self.assertEqual(over, 4)
        self.assertEqual(len(steps.split("\n")), 9)
        # a plan that is done has no steps
        L.run("LSET({ ['Master Chef'] = 1, ['Well Rested'] = 5, ['Talented'] = 1, ['Gourmand'] = 3, ['The Quick and the Dead'] = 1 })")
        self.assertEqual(self.steps(GATHERER)[0], "")

    def test_a_plan_that_cant_be_bought_as_it_stands_says_so(self):
        # Master Chef wants 5 points on the tree first, which the plan doesn't give; Talented wants a full Well Rested
        blocked = L.eval("""function() local p = FA.Legacy.Progress({ ranks = LPLAN({ ['Master Chef'] = 1, ['Talented'] = 1, ['Well Rested'] = 2 }), build = 70425 })
          local out = {} for i, b in ipairs(p.blocked) do out[i] = FA.Legacy.PERKS[b.perk].name .. ': ' .. b.why end
          return table.concat(out, '|'), #p.steps end""")()
        self.assertEqual(blocked, ("Master Chef: the plan has too few points in Professions before it|Talented: the plan doesn't fill Well Rested first", 2))
        # a perk the game doesn't sell yet (one of the Unknown ones)
        ranks = "0" * 6 + "1" + "0" * 20
        blocked = L.eval("function(r) local p = FA.Legacy.Progress({ ranks = r, build = 70425 }); return FA.Legacy.PERKS[p.blocked[1].perk].node, p.blocked[1].why, #p.steps end")(ranks)
        self.assertEqual(blocked, (113508, "the game doesn't sell it yet", 0))

    def test_a_plan_from_another_build_is_shown_and_never_followed(self):
        steps, why = self.steps(GATHERER, 70001)
        self.assertIsNone(steps)
        self.assertIn("client build 70001", why)
        self.assertIn("70425", why)
        _, why = self.steps(GATHERER, 0)
        self.assertIn("client build unknown", why)
        self.assertTrue(L.eval("FA.Legacy.Differs({ build = 70001 })"))
        self.assertFalse(L.eval("FA.Legacy.Differs({ build = 70425 })"))
        ok, said = self.apply(GATHERER, 70001)
        self.assertFalse(ok)
        self.assertIn("70001", said)
        self.assertEqual(self.log(), [])

    def test_the_game_hasnt_given_the_trees_yet(self):
        L.run("LEGACY_ON = false")
        steps, why = self.steps(GATHERER)
        self.assertIsNone(steps)
        self.assertIn("hasn't given the Legacy trees yet", why)
        L.run("LEGACY_ON = true; local f = C_Traits.GetNodeInfo; C_Traits.GetNodeInfo = function(c, n) if n == 110298 then return nil end return f(c, n) end; SAVED = f")
        steps, why = self.steps(GATHERER)
        L.run("C_Traits.GetNodeInfo = SAVED")
        self.assertIsNone(steps)
        self.assertIn("doesn't know the Legacy perk Talented (node 110298)", why)

    # ---- the points
    def test_the_points_and_the_cap_come_from_the_games_currency(self):
        self.assertEqual(L.eval("function() return FA.Legacy.Points() end")(), (16, 16))
        L.run("LPOINTS, LCAP = 7, 20")
        self.assertEqual(L.eval("function() local a, c = FA.Legacy.Points(); return a .. '/' .. c end")(), "7/20")
        L.run("LPOINTS = nil")   # the game says nothing
        self.assertEqual(L.eval("function() local a, c = FA.Legacy.Points(); return a == nil and c == nil end")(), True)
        L.run("LEGACY_ON = false")
        self.assertEqual(L.eval("function() local a, c = FA.Legacy.Points(); return a == nil and c == nil end")(), True)

    def plan_size(self, byName=GATHERER):
        return L.eval("function() local list, p, held = FA.Legacy.Plan({ ranks = LPLAN(%s), build = 70425 }); return list and #list, list and held, (not list) and p or nil end" % lua_table(byName))()

    def test_the_points_available_stop_the_list(self):
        self.assertEqual(self.plan_size(), (16, 0, None))
        L.run("LPOINTS = 4")
        self.assertEqual(self.plan_size(), (4, 12, None))
        L.run("LPOINTS = 0")
        self.assertEqual(self.plan_size(), (None, None, "You have no Legacy points to spend."))
        # the game saying nothing: the cap alone limits it, and the game turns down what it won't sell
        L.run("LPOINTS = nil")
        self.assertEqual(self.plan_size(), (16, 0, None))

    def test_the_cap_stops_the_list(self):
        L.run("LSET({ ['Bountiful Harvest'] = 5, ['Thrill of Adventure'] = 5, ['Reinforce'] = 5 }); LPOINTS = 16")   # 15 spent elsewhere
        self.assertEqual(self.plan_size(), (1, 15, None))
        L.run("LSET({ ['Diplomat'] = 1 })")
        self.assertEqual(self.plan_size(), (None, None, "You have spent the seasonal cap of 16 Legacy points."))
        # the cap is the game's when it says one
        L.run("LCAP = 18")
        self.assertEqual(self.plan_size()[0:2], (2, 14))
        L.run("LCAP = nil")   # not told: the table's 16
        self.assertEqual(self.plan_size(), (None, None, "You have spent the seasonal cap of 16 Legacy points."))

    def test_nothing_to_buy_says_why(self):
        L.run("LSET({ ['Master Chef'] = 1, ['Working Overtime'] = 5, ['Well Rested'] = 5, ['Talented'] = 1, ['Gourmand'] = 3, ['The Quick and the Dead'] = 1 })")
        self.assertEqual(self.plan_size(), (None, None, "Every rank of this plan is bought."))
        got = self.plan_size({"Master Chef": 1})[2]
        self.assertEqual(got, "Every rank of this plan is bought.")   # Master Chef is had; the rest is empty
        L.run("LEG = {}")
        self.assertIn("Master Chef, the plan has too few points", self.plan_size({"Master Chef": 1})[2])

    # ---- Apply
    def test_apply_buys_a_plan_from_nothing_tree_by_tree(self):
        ok, said = self.apply(GATHERER)
        self.assertTrue(ok)
        self.assertEqual(said, "Working Overtime x5, Master Chef, Well Rested x5, Talented, Gourmand x3, The Quick and the Dead")
        log = self.log()
        self.assertEqual(log, ["buy Working Overtime"] * 5 + ["buy Master Chef", "commit 1187"] + ["buy Well Rested"] * 5 + ["buy Talented", "commit 1188"] +
                         ["buy Gourmand"] * 3 + ["buy The Quick and the Dead", "commit 1189"])
        self.assertEqual(self.account(), GATHERER)
        self.assertEqual(L.eval("LAVAILABLE()"), 0)
        # the plan is done: nothing more to buy
        self.assertEqual(self.apply(GATHERER), (False, "Every rank of this plan is bought."))

    def test_apply_buys_what_a_part_done_plan_still_needs(self):
        L.run("LSET({ ['Working Overtime'] = 5, ['Well Rested'] = 2 }); LPOINTS = 9")
        ok, said = self.apply(GATHERER)
        self.assertTrue(ok)
        self.assertEqual(said, "Master Chef, Well Rested x3, Talented, Gourmand x3, The Quick and the Dead")
        self.assertEqual(self.account(), GATHERER)

    def test_apply_stops_at_the_points_available_and_the_cap(self):
        L.run("LPOINTS = 7")
        ok, said = self.apply(GATHERER)
        self.assertTrue(ok)
        self.assertEqual(said, "Working Overtime x5, Master Chef, Well Rested")   # the first seven, in order
        self.assertEqual(self.account(), {"Working Overtime": 5, "Master Chef": 1, "Well Rested": 1})
        self.assertEqual(L.eval("LAVAILABLE()"), 0)
        # under the cap: 12 spent elsewhere, 4 left of it, and 9 points to spend
        L.run("LEG = {}; LOG = {}; LSET({ ['Diplomat'] = 5, ['Thrill of Adventure'] = 5, ['Reinforce'] = 2 }); LPOINTS = 9")
        ok, said = self.apply(GATHERER)
        self.assertTrue(ok)
        self.assertEqual(said, "Working Overtime x4")
        self.assertEqual(self.account()["Working Overtime"], 4)
        self.assertEqual(self.log(), ["buy Working Overtime"] * 4 + ["commit 1187"])   # no tree past the first was touched

    def test_a_refused_purchase_rolls_back_that_tree_only(self):
        L.run("LREFUSE = 110298")   # the game turns down Talented
        ok, said = self.apply(GATHERER)
        self.assertFalse(ok)
        self.assertIn("The game wouldn't take Talented rank 1 (Adventure). Nothing was bought in Adventure.", said)
        self.assertIn("Bought: Working Overtime x5, Master Chef, Gourmand x3, The Quick and the Dead.", said)
        self.assertEqual(self.account(), {"Working Overtime": 5, "Master Chef": 1, "Gourmand": 3, "The Quick and the Dead": 1})
        log = self.log()
        self.assertEqual(log[log.index("refused Talented") + 1], "rollback 1188")
        self.assertNotIn("commit 1188", log)
        self.assertIn("commit 1187", log)
        self.assertIn("commit 1189", log)
        self.assertIsNone(L.eval("LSTAGED[202]"))
        # a rank counted in the message: the second of a perk with more than one
        L.run("LEG = {}; LOG = {}; LPOINTS = 16; LREFUSE = 110301")   # Well Rested
        ok, said = self.apply(GATHERER)
        self.assertIn("The game wouldn't take Well Rested rank 1 (Adventure)", said)

    def test_a_commit_the_game_turns_down_is_rolled_back(self):
        L.run("LFAIL_COMMIT = true")   # every tree's
        ok, said = self.apply(GATHERER)
        self.assertFalse(ok)
        self.assertEqual(said.count("Nothing was bought in"), 3)
        self.assertIn("The game wouldn't apply the Professions perks. Nothing was bought in Professions.", said)
        self.assertEqual(self.account(), {})
        self.assertEqual([x for x in self.log() if x.startswith("rollback")], ["rollback 1187", "rollback 1188", "rollback 1189"])
        self.assertEqual(L.eval("next(LSTAGED)"), None)
        # one tree's alone
        L.run("LOG = {}; LFAIL_COMMIT = 202")
        ok, said = self.apply(GATHERER)
        self.assertFalse(ok)
        self.assertIn("Adventure perks", said)
        self.assertNotIn("Professions perks", said)
        self.assertEqual(self.account(), {"Working Overtime": 5, "Master Chef": 1, "Gourmand": 3, "The Quick and the Dead": 1})
        self.assertIn("Bought: Working Overtime x5, Master Chef, Gourmand x3, The Quick and the Dead.", said)

    def test_a_commit_the_game_fails_after_it_started_is_rolled_back_by_the_event(self):
        L.run("LFAIL_COMMIT = 'late'")   # the cast starts; nothing is applied
        ok, said = self.apply({"Working Overtime": 2})
        self.assertTrue(ok)   # started
        self.assertEqual(L.eval("LSTAGED[201][110290]"), 2)
        L.run("PRINTED = ''; EVENT('CONFIG_COMMIT_FAILED', 201); FLUSH()")
        self.assertIsNone(L.eval("LSTAGED[201]"))
        self.assertEqual(self.log()[-1], "rollback 1187")
        self.assertIn("The game didn't apply the Legacy perks, so they were rolled back. Nothing was bought.", L.eval("PRINTED"))
        # an event for a config the addon didn't commit, or after the game said yes, is the game's
        L.run("PRINTED = ''; LOG = {}; EVENT('CONFIG_COMMIT_FAILED', 201); EVENT('CONFIG_COMMIT_FAILED', 202); EVENT('CONFIG_COMMIT_FAILED')")
        self.assertEqual(self.log(), [])
        self.assertNotIn("Legacy perks", L.eval("PRINTED"))
        L.run("LFAIL_COMMIT = false; LOG = {}")
        ok, said = self.apply({"Working Overtime": 2})
        L.run("EVENT('TRAIT_CONFIG_UPDATED', 201); PRINTED = ''; EVENT('CONFIG_COMMIT_FAILED', 201)")
        self.assertEqual([x for x in self.log() if x.startswith("rollback")], [])
        self.assertNotIn("Legacy perks", L.eval("PRINTED"))
        # no config in the event: the commit in flight is the one
        L.run("LFAIL_COMMIT = 'late'; LOG = {}")
        self.apply({"Well Rested": 1})
        L.run("PRINTED = ''; EVENT('CONFIG_COMMIT_FAILED')")
        self.assertEqual(self.log()[-1], "rollback 1188")
        self.assertIn("The game didn't apply the Legacy perks", L.eval("PRINTED"))

    def test_a_commit_the_game_fails_inside_the_call_is_said_by_apply(self):
        L.run("LFAIL_COMMIT = 'now'; PRINTED = ''")
        ok, said = self.apply({"Working Overtime": 2})
        self.assertFalse(ok)
        self.assertIn("The game wouldn't apply the Professions perks. Nothing was bought in Professions.", said)
        self.assertEqual(self.log()[-1], "rollback 1187")
        self.assertNotIn("Legacy perks, so they were rolled back", L.eval("PRINTED"))   # apply says it, the event doesn't say it twice
        self.assertIsNone(L.eval("LSTAGED[201]"))

    def test_apply_refuses_in_combat(self):
        L.run("COMBAT = true")
        ok, said = self.apply(GATHERER)
        self.assertEqual((ok, said), (False, "You can't change Legacy perks in combat."))
        self.assertEqual(self.log(), [])

    def test_apply_leaves_the_legacy_windows_own_staged_changes_alone(self):
        L.run("LSTAGED[202] = { [110301] = 1 }")   # a rank bought in the window and not applied
        ok, said = self.apply(GATHERER)
        self.assertEqual((ok, said), (False, "The Legacy window has changes waiting. Apply or undo them there first."))
        self.assertEqual(self.log(), [])
        self.assertEqual(L.eval("LSTAGED[202][110301]"), 1)   # and not rolled back

    def test_apply_with_no_plan_to_buy_buys_nothing(self):
        ok, said = self.apply({})
        self.assertEqual((ok, said), (False, "Every rank of this plan is bought."))
        self.assertEqual(self.log(), [])

    def test_a_missing_trait_function_is_said_not_an_error(self):
        L.run("SAVED = C_Traits.ConfigHasStagedChanges; C_Traits.ConfigHasStagedChanges = nil")
        self.assertFalse(L.eval("FA.Legacy.HasStaged()"))   # nothing to ask: the game's own refusals roll back
        L.run("C_Traits.ConfigHasStagedChanges = SAVED")


class UI(unittest.TestCase):
    """TalentUI.lua and GearUI.lua run against a mock of the frame API: every path draws without a Lua error."""

    @classmethod
    def setUpClass(cls):
        L.run("RESET('traits')")
        L.run(UI_STUB)
        for name in ("TalentUI.lua", "GearUI.lua", "LegacyUI.lua"):
            L.run("""
              local f = assert(io.open(ROOT .. '/%s', 'rb')); local src = f:read('*a'); f:close()
              assert((loadstring or load)(src, '@%s'))('ForeverArmoury', FA)
            """ % (name, name))
        L.run("FA.HookTalentFrame(); FA.HookCharacterFrame(); FA.HookLegacyFrame(); FA.SetupOptions()")

    def setUp(self):
        L.run("RESET('traits'); POPUPS = {}; LIT = nil; LSHOWN_TREE = 1187; LegacySystemFrame:Show(); FA.Refresh(); FA.RefreshLegacy()")   # the refresh puts out what a test left lit

    def panel(self, key):
        return L.eval("function(k) local p = ForeverArmouryTalentPanel; if k == 'status' then return p.status.text end "
                      "if k == 'apply' then return p.apply.text, p.apply.enabled, p.apply.why end end")(key)

    def test_no_builds(self):
        L.run("FA.Refresh()")
        self.assertIn("No builds for this class yet", self.panel("status"))
        self.assertEqual(self.panel("apply")[1], False)

    def test_import_follow_light_and_apply(self):
        ok, said = L.eval("function(t) return FA.ImportText(t) end")("FAT1-warrior-Arms-" + GATED)
        self.assertTrue(ok)
        self.assertIn("1 Warrior build imported. Following Arms.", said)
        L.run("PLAYER.level = 12; FA.Talents.Forget(); FA.Refresh()")
        self.assertIn("Next: |cffffd100Deflection|r 1/5 (Arms), now.", self.panel("status"))
        self.assertEqual(L.eval("LIT"), L.eval("NODE(1, 1)"))
        text, enabled, why = self.panel("apply")
        self.assertEqual((text, enabled, why), ("Apply 3 points", True, "Deflection x3"))
        L.run("FA.AskApply()")
        popup = L.eval("POPUPS[1]")
        self.assertEqual(popup.which, "FOREVERARMOURY_APPLY")
        self.assertIn("Spend 3 points as Arms says?", popup.text)
        L.run("StaticPopupDialogs.FOREVERARMOURY_APPLY.OnAccept(nil, POPUPS[1].data)")
        self.assertEqual(L.eval("FA.Talents.Spent()"), 3)
        self.assertIn("Spent as Arms says: Deflection x3.", L.eval("PRINTED"))
        L.run("FA.Refresh()")
        text, enabled, why = self.panel("apply")
        self.assertEqual((text, enabled), ("Apply", False))
        self.assertEqual(why, "Your next point comes at level 13.")

    def rows(self):
        return L.eval("function() local out = {} for i, r in ipairs(ForeverArmouryTalentPanel.rows) do out[i] = (r.shown and (r.text.text or '') or false) end return out end")()

    def controls(self):
        return L.eval("function() local p = ForeverArmouryTalentPanel; return p.up.shown, p.up.enabled, p.down.shown, p.down.enabled, p.more.text end")()

    def test_the_build_list_scrolls_to_every_build(self):
        names = ["B%d" % n for n in range(1, 26)]
        L.run("FA.char.buildsOpen = true")   # picking a build closes the list unless it was opened on purpose
        L.run("FA.ImportText('" + " ".join("FAT1-warrior-%s-01%02x" % (n, i) for i, n in enumerate(names)) + "')")
        self.assertEqual(L.eval("#FA.BuildsFor('warrior')"), 25)
        rows = lambda: [r for r in L.eval("function() local out = {} for i, r in ipairs(ForeverArmouryTalentPanel.rows) do out[i] = r.text.text end return out end")().values()]
        self.assertEqual(rows(), names[:10])
        self.assertEqual(self.controls(), (True, False, True, True, "1-10 of 25"))     # at the top: up is off
        press = lambda key: L.run("local b = ForeverArmouryTalentPanel.%s; b.scripts.OnClick(b)" % key)
        press("down")
        self.assertEqual(rows(), names[9:19])                                          # a page, one row kept to read by
        self.assertEqual(self.controls(), (True, True, True, True, "10-19 of 25"))
        press("down"); press("down")
        self.assertEqual(rows(), names[15:25])                                         # as far as it goes: the 25th is a row
        self.assertEqual(self.controls(), (True, True, True, False, "16-25 of 25"))
        # a row picked from down there is the build under it
        L.run("local r = ForeverArmouryTalentPanel.rows[10]; r.scripts.OnClick(r)")
        self.assertEqual(L.eval("FA.ActiveBuild().name"), "B25")
        press("up")
        self.assertEqual(rows(), names[6:16])
        # the mouse wheel moves it a row
        L.run("local p = ForeverArmouryTalentPanel; p.scripts.OnMouseWheel(p, -1)")
        self.assertEqual(rows()[0], "B8")
        L.run("local p = ForeverArmouryTalentPanel; p.scripts.OnMouseWheel(p, 1); p.scripts.OnMouseWheel(p, 1); p.scripts.OnMouseWheel(p, 1)")
        self.assertEqual(rows()[0], "B5")
        L.run("for i = 1, 20 do local p = ForeverArmouryTalentPanel; p.scripts.OnMouseWheel(p, 1) end")
        self.assertEqual(rows(), names[:10])                                           # not past the top
        self.assertEqual(self.controls()[1], False)
        # forgetting builds from the end brings the list back up, and 10 or fewer need no arrows
        L.run("FA.ScrollBuilds(100)")
        self.assertEqual(rows()[0], "B16")
        L.run("for i = 25, 13, -1 do FA.ForgetBuild('warrior', i) end; FA.Refresh()")
        self.assertEqual(rows(), names[2:12])
        self.assertEqual(self.controls(), (True, True, True, False, "3-12 of 12"))
        L.run("FA.ForgetBuild('warrior', 11); FA.ForgetBuild('warrior', 12); FA.Refresh()")
        self.assertEqual(rows(), names[:10])
        self.assertEqual(self.controls()[0:3:2], (False, False))
        self.assertEqual(L.eval("ForeverArmouryTalentPanel.more.shown"), False)

    def test_an_eleventh_build_is_reachable(self):
        L.run("FA.char.buildsOpen = true")
        L.run("FA.ImportText('" + " ".join("FAT1-warrior-B%d-01%02x" % (i, i) for i in range(1, 12)) + "')")
        self.assertEqual(L.eval("ForeverArmouryTalentPanel.rows[10].text.text"), "B10")
        L.run("FA.ScrollBuilds(1)")
        self.assertEqual(L.eval("ForeverArmouryTalentPanel.rows[10].text.text"), "B11")
        L.run("local r = ForeverArmouryTalentPanel.rows[10]; r.scripts.OnClick(r)")
        self.assertEqual(L.eval("FA.ActiveBuild().name"), "B11")

    def test_a_colour_escape_in_a_name_is_drawn_as_typed(self):
        L.run("FA.char.buildsOpen = true")
        L.run("FA.ImportText('FAT1-warrior-A%7CcffFF0000Red%7Cr-" + GATED + "')")
        self.assertEqual(L.eval("FA.ActiveBuild().name"), "A|cffFF0000Red|r")
        self.assertEqual(L.eval("ForeverArmouryTalentPanel.rows[1].text.text"), "A||cffFF0000Red||r")
        self.assertIn("Following A||cffFF0000Red||r.", L.eval("PRINTED"))
        L.run("PLAYER.level = 12; FA.Talents.Forget(); FA.AskApply()")
        self.assertIn("Spend 3 points as A||cffFF0000Red||r says?", L.eval("POPUPS[1].text"))
        L.run("StaticPopupDialogs.FOREVERARMOURY_APPLY.OnAccept(nil, POPUPS[1].data)")
        self.assertIn("Spent as A||cffFF0000Red||r says", L.eval("PRINTED"))
        L.run("FA.ImportText('FAT1-warrior-%7CHplain%7Ch-0a')")
        self.assertEqual(L.eval("ForeverArmouryTalentPanel.rows[2].text.text"), "||Hplain||h")

    def test_an_unnamed_build_is_called_unnamed(self):
        L.run("FA.char.buildsOpen = true")
        ok, said = L.eval("function(t) return FA.ImportText(t) end")("FAT1-warrior--" + GATED)
        self.assertIn("Following Unnamed.", said)
        self.assertEqual(L.eval("ForeverArmouryTalentPanel.rows[1].text.text"), "Unnamed")
        L.run("local r = ForeverArmouryTalentPanel.rows[1]; r.forget.scripts.OnClick({ GetParent = function() return r end })")
        self.assertEqual(L.eval("POPUPS[1].which"), "FOREVERARMOURY_FORGET")
        self.assertEqual(L.eval("POPUPS[1].text"), "Unnamed")   # the %s of "Forget the build %s on this account?"
        L.run("PRINTED = ''; SlashCmdList.FOREVERARMOURY('list')")
        self.assertIn("> Unnamed (13 points)", L.eval("PRINTED"))

    def test_an_import_before_login_works(self):
        L.run("FA.class = nil; ForeverArmouryDB, ForeverArmouryCharDB = nil, nil; FA.Init()")   # ADDON_LOADED, not yet PLAYER_LOGIN
        ok, said = L.eval("function(t) return FA.ImportText(t) end")("FAT1-warrior-Arms-" + GATED)
        self.assertTrue(ok)
        self.assertIn("1 Warrior build imported. Following Arms.", said)

    def test_the_apply_button_follows_combat(self):
        L.run("FA.ImportText('FAT1-warrior-Arms-" + GATED + "'); PLAYER.level = 12; FA.Talents.Forget(); FA.Refresh()")
        self.assertEqual(self.panel("apply"), ("Apply 3 points", True, "Deflection x3"))
        # the fight starts: the button waits for the frame, then says why not
        L.run("COMBAT = true; EVENT('PLAYER_REGEN_DISABLED')")
        self.assertEqual(self.panel("apply")[1], True)
        L.run("FLUSH()")
        self.assertEqual(self.panel("apply"), ("Apply", False, "You can't change talents in combat."))
        self.assertIn("Next: |cffffd100Deflection|r", self.panel("status"))   # the rest of the panel is as it was
        L.run("COMBAT = false; EVENT('PLAYER_REGEN_ENABLED'); FLUSH()")
        self.assertEqual(self.panel("apply"), ("Apply 3 points", True, "Deflection x3"))
        L.run("COMBAT = true; EVENT('ACTIVE_COMBAT_CONFIG_CHANGED'); FLUSH()")
        self.assertEqual(self.panel("apply")[1], False)
        L.run("COMBAT = false; FA.Refresh()")

    def test_off_build_points_show_the_swap(self):
        L.run("FA.ImportText('FAT1-warrior-Arms-" + GATED + "'); TREE[3][1][4] = 2; FA.Talents.Forget(); FA.Refresh()")
        status = self.panel("status")
        self.assertIn("2 points aren't in this build|r (Shield Specialization x2).", status)
        self.assertIn("Reset your talents at a class trainer", status)
        self.assertEqual(self.panel("apply")[1], False)

    # ---- the strip of icons beside the talent window (#1562) and its hover (#1563)
    def strip(self):
        """What the strip shows, an icon a line: kind, talent and rank, then | and its level badge (@), label under it ([]), check (v), gold border and alpha."""
        text = L.eval("""function()
          local out = {}
          for i, ic in ipairs(ForeverArmouryTalentStrip.icons) do
            if ic.entry and ic.shown then
              local e, rank = ic.entry, ic.rank.text or ''
              local decor = {}
              if ic.level.shown then decor[#decor + 1] = '@' .. ic.level.text end
              if ic.label.shown then decor[#decor + 1] = '[' .. ic.label.text .. ']' end
              if ic.check.shown then decor[#decor + 1] = 'v' end
              if ic.edge.shown then decor[#decor + 1] = 'edge' end
              if ic.tex.alpha ~= 1 then decor[#decor + 1] = 'a=' .. ic.tex.alpha end
              out[#out + 1] = e.kind .. ' ' .. e.talent.name .. (rank ~= '' and (' ' .. rank) or '') .. '|' .. table.concat(decor, ' ')
            end
          end
          return table.concat(out, '\\n')
        end""")()
        return text.split("\n") if text else []

    def follow(self, level=60, ranks=()):
        """Imports GATED, follows it, and sets the character to a level with ranks: (tree, index, rank) triples."""
        L.run("FA.ImportText('FAT1-warrior-Arms-" + GATED + "'); PLAYER.level = %d" % level)
        for tab, index, rank in ranks:
            L.run("TREE[%d][%d][4] = %d" % (tab, index, rank))
        L.run("FA.Talents.Forget(); FA.Refresh()")

    MID = ((1, 1, 5), (1, 3, 2))   # Deflection 5/5, Tactical Mastery 2/5: seven points of the build's thirteen

    def more(self):
        return L.eval("ForeverArmouryTalentStrip.more.shown"), L.eval("ForeverArmouryTalentStrip.more.count")

    def test_no_strip_without_a_build(self):
        L.run("FA.Refresh()")
        self.assertFalse(L.eval("ForeverArmouryTalentStrip.shown"))
        L.run("FA.ImportText('FAT1-warrior-Arms-" + GATED + " FAT1-warrior-Fury-0101')")
        self.assertIsNone(L.eval("FA.ActiveBuild()"))   # two builds: none followed yet
        self.assertFalse(L.eval("ForeverArmouryTalentStrip.shown"))
        self.assertTrue(L.eval("ForeverArmouryTalentPanel.points[1][2] == PlayerSpellsFrame"))   # the panel is against the window
        L.run("FA.SetActive(FA.BuildsFor('warrior')[1].id); FA.Refresh()")
        self.assertTrue(L.eval("ForeverArmouryTalentStrip.shown"))
        # the strip is 48 wide against the window's right edge, and the panel against the strip's
        self.assertEqual(L.eval("ForeverArmouryTalentStrip.width"), 48)
        self.assertEqual(L.eval("ForeverArmouryTalentStrip.points[1][2] == PlayerSpellsFrame and ForeverArmouryTalentStrip.points[1][3]"), "TOPRIGHT")
        self.assertEqual(L.eval("ForeverArmouryTalentStrip.points[2][2] == PlayerSpellsFrame and ForeverArmouryTalentStrip.points[2][3]"), "BOTTOMRIGHT")
        self.assertTrue(L.eval("ForeverArmouryTalentPanel.points[1][2] == ForeverArmouryTalentStrip"))
        L.run("FA.SetActive(nil); FA.Refresh()")
        self.assertFalse(L.eval("ForeverArmouryTalentStrip.shown"))
        self.assertEqual(L.eval("#ForeverArmouryTalentPanel.points"), 1)   # moved, not added to
        self.assertTrue(L.eval("ForeverArmouryTalentPanel.points[1][2] == PlayerSpellsFrame"))

    def test_strip_at_no_points(self):
        self.follow()
        self.assertEqual(self.strip(), [
            "next Deflection 1/5|[Now] edge",
            "coming Deflection 2/5|@11", "coming Deflection 3/5|@12", "coming Deflection 4/5|@13",
            "coming Deflection 5/5|@14", "coming Tactical Mastery 1/5|@15"])
        self.assertEqual(self.more(), (True, 7))   # thirteen points: one next, five coming, seven more
        # the icon and name are the game's
        self.assertEqual(L.eval("ForeverArmouryTalentStrip.icons[1].tex.texture"), L.eval("NODE(1, 1) * 10"))
        self.assertTrue(L.eval("ForeverArmouryTalentStrip.icons[1].glow.shown"))
        self.assertFalse(L.eval("ForeverArmouryTalentStrip.icons[2].glow.shown"))

    def test_strip_mid_build(self):
        self.follow(16, self.MID)
        self.assertEqual(self.strip(), [
            "taken Deflection 5/5|v a=0.45", "taken Tactical Mastery 1/5|v a=0.45", "taken Tactical Mastery 2/5|v a=0.45",
            "next Tactical Mastery 3/5|[L17] edge",   # the level isn't here yet: its level, not Now
            "coming Tactical Mastery 4/5|@18", "coming Tactical Mastery 5/5|@19", "coming Sweeping Strikes|@20",
            "coming Cruelty 1/5|@21", "coming Cruelty 2/5|@22"])   # a talent with one rank has no r/m
        self.assertEqual(self.more(), (False, 0))
        # the level comes: Now
        L.run("PLAYER.level = 17; FA.Refresh()")
        self.assertIn("next Tactical Mastery 3/5|[Now] edge", self.strip())

    def test_strip_of_a_finished_build(self):
        self.follow(60, ((1, 1, 5), (1, 3, 5), (1, 5, 1), (2, 2, 2)))
        self.assertEqual(self.strip(), ["taken Sweeping Strikes|v a=0.45", "taken Cruelty 1/5|v a=0.45", "taken Cruelty 2/5|v a=0.45"])
        self.assertEqual(self.more(), (False, 0))
        self.assertIn("Every point of this build is spent.", self.panel("status"))
        self.assertFalse(any("Now" in line for line in self.strip()))

    def test_strip_of_a_build_off_its_order(self):
        self.follow(60, ((1, 1, 2), (3, 4, 1)))   # Deflection 2, and Last Stand, which the build doesn't have
        lines = self.strip()
        self.assertEqual(lines[:3], ["taken Deflection 1/5|v a=0.45", "taken Deflection 2/5|v a=0.45", "next Deflection 3/5|[L12] edge"])
        self.assertEqual(len(lines), 8)   # two taken, the next, five coming
        self.assertFalse(any("Last Stand" in line for line in lines))
        self.assertIn("1 point isn't in this build", self.panel("status"))

    def test_the_strip_follows_the_character(self):
        self.follow(12)
        self.assertEqual(self.strip()[0], "next Deflection 1/5|[Now] edge")
        L.run("FA.AskApply(); StaticPopupDialogs.FOREVERARMOURY_APPLY.OnAccept(nil, POPUPS[1].data)")
        self.assertEqual(L.eval("FA.Talents.Spent()"), 3)
        L.run("FLUSH(); FA.Refresh()")
        self.assertEqual(self.strip()[:4], ["taken Deflection 1/5|v a=0.45", "taken Deflection 2/5|v a=0.45", "taken Deflection 3/5|v a=0.45",
                                            "next Deflection 4/5|[L13] edge"])
        # a level up and an event: one redraw a frame, with the new level
        L.run("PLAYER.level = 13; EVENT('PLAYER_LEVEL_UP'); FLUSH()")
        self.assertEqual(self.strip()[3], "next Deflection 4/5|[Now] edge")
        # the other spec: the strip follows the one that's active
        L.run("SPEC.groups = 2; OTHER[NODE(1, 1)] = 5; SPEC.active = 2; EVENT('ACTIVE_TALENT_GROUP_CHANGED'); FLUSH()")
        self.assertEqual(self.strip()[0:3], ["taken Deflection 3/5|v a=0.45", "taken Deflection 4/5|v a=0.45", "taken Deflection 5/5|v a=0.45"])
        self.assertEqual(self.strip()[3], "next Tactical Mastery 1/5|[L15] edge")   # level 13: its point is at 15

    def test_the_strip_counts_are_settings(self):
        self.assertEqual(L.eval("FA.db.strip.past"), 3)
        self.assertEqual(L.eval("FA.db.strip.coming"), 5)
        self.follow(16, self.MID)
        L.run("FA.db.strip.past, FA.db.strip.coming = 1, 2; FA.Refresh()")
        self.assertEqual([line.split("|")[0] for line in self.strip()], ["taken Tactical Mastery 2/5", "next Tactical Mastery 3/5", "coming Tactical Mastery 4/5", "coming Tactical Mastery 5/5"])
        self.assertEqual(self.more(), (True, 3))
        L.run("FA.db.strip.past, FA.db.strip.coming = 0, 0; FA.Refresh()")
        self.assertEqual([line.split("|")[0] for line in self.strip()], ["next Tactical Mastery 3/5"])
        self.assertEqual(self.more(), (True, 5))
        # more than the strip has room for is the most it has, and fewer than none is none
        L.run("FA.db.strip.past, FA.db.strip.coming = 99, -4; FA.Refresh()")
        self.assertEqual([line.split("|")[0] for line in self.strip()], ["taken Deflection 3/5", "taken Deflection 4/5", "taken Deflection 5/5", "taken Tactical Mastery 1/5", "taken Tactical Mastery 2/5", "next Tactical Mastery 3/5"])
        L.run("FA.db.strip.past, FA.db.strip.coming = 99, 99; FA.Refresh()")
        self.assertEqual(len(self.strip()), 11)   # five taken, the next, and the five the build has left
        self.assertEqual((L.eval("FA.StripCount('past')"), L.eval("FA.StripCount('coming')")), (5, 8))
        # a saved value that isn't a number is replaced by the default at load; one that is is kept
        L.run("ForeverArmouryDB = { strip = { past = 'x', coming = 2 } }; FA.Init()")
        self.assertEqual((L.eval("FA.db.strip.past"), L.eval("FA.db.strip.coming")), (3, 2))
        L.run("ForeverArmouryDB = { strip = 7 }; FA.Init()")
        self.assertEqual((L.eval("FA.db.strip.past"), L.eval("FA.db.strip.coming")), (3, 5))

    def test_the_settings_page_sets_the_counts(self):
        self.follow(16, self.MID)
        L.run("local s = ForeverArmouryStripPast; s.scripts.OnValueChanged(s, 1); s = ForeverArmouryStripComing; s.scripts.OnValueChanged(s, 2)")
        self.assertEqual((L.eval("FA.db.strip.past"), L.eval("FA.db.strip.coming")), (1, 2))
        self.assertEqual(len(self.strip()), 4)
        self.assertEqual(L.eval("ForeverArmouryStripPast.kind"), "Slider")

    def test_the_sliders_caption_themselves(self):
        self.assertEqual(L.eval("ForeverArmouryStripPastLow.text"), "0")
        self.assertEqual(L.eval("ForeverArmouryStripPastHigh.text"), "5")
        self.assertEqual(L.eval("ForeverArmouryStripPastText.text"), "Taken points shown")
        self.assertIsNone(L.eval("rawget(_G, 'ForeverArmouryStripComingLow')"))   # no captions to set: the page still built

    def test_the_overlays_follow_a_recycled_buttons_level(self):
        self.follow(16, self.MID)
        self.hover(self.icon("coming", "Cruelty", "1/5"))
        level = lambda tab, i, kind: L.eval("function(node, kind) for _, c in ipairs(BUTTONS[node].children) do if (rawget(c.regions[1], 'color') and 'hover' or 'glow') == kind then return c.level end end end")(L.eval("NODE(%d, %d)" % (tab, i)), kind)
        self.assertEqual((level(2, 2, "hover"), level(1, 3, "glow")), (6, 6))   # the hover's and the next talent's glow: the button's level and five
        L.run("for _, b in pairs(BUTTONS) do b.GetFrameLevel = function() return 10 end end; FA.Refresh()")
        self.assertEqual((level(2, 2, "hover"), level(1, 3, "glow")), (15, 15))   # the game gave the buttons new levels
        L.run("for _, b in pairs(BUTTONS) do b.GetFrameLevel = nil end")

    def test_an_icon_the_game_has_not_given_is_a_question_mark(self):
        L.run("DEFS[NODE(1, 1)] = { overrideName = 'Plain' }")   # a definition with a name and neither icon nor spell
        self.follow()
        self.assertEqual(L.eval("ForeverArmouryTalentStrip.icons[1].tex.texture"), "Interface\\Icons\\INV_Misc_QuestionMark")
        self.assertEqual(L.eval("ForeverArmouryTalentStrip.icons[6].tex.texture"), L.eval("NODE(1, 3) * 10"))   # the others have theirs
        L.run("local ic = ForeverArmouryTalentStrip.icons[1]; ic.scripts.OnEnter(ic)")
        self.assertEqual((L.eval("TIP.text"), L.eval("TIP.spell")), ("Plain", None))   # no spell: the name
        L.run("DEFS[NODE(1, 1)] = nil; FA.Talents.Forget(); FA.Refresh(); local ic = ForeverArmouryTalentStrip.icons[1]; ic.scripts.OnEnter(ic)")
        self.assertEqual(L.eval("TIP.text"), "Unknown talent")

    def icon(self, kind, name, rank):
        for i, line in enumerate(self.strip(), 1):
            if line.split("|")[0] == "%s %s %s" % (kind, name, rank):
                return i
        self.fail("no %s %s %s in %s" % (kind, name, rank, self.strip()))

    def hover(self, i, event="OnEnter"):
        L.run("local ic = ForeverArmouryTalentStrip.icons[%d]; ic.scripts.%s(ic)" % (i, event))

    def overlays(self, tab, index):
        """The addon's overlays on a talent's button in the tree: "glow=true hover=false", the next-talent glow and the hover's."""
        return L.eval("""function(node)
          local b = BUTTONS[node]; local out = {}
          for _, c in ipairs(b and b.children or {}) do out[#out + 1] = (rawget(c.regions[1], 'color') and 'hover=' or 'glow=') .. tostring(c.shown) end
          table.sort(out)
          return table.concat(out, ' ')
        end""")(L.eval("NODE(%d, %d)" % (tab, index)))

    def test_hover_lights_the_talent_and_leaves_the_next_ones_glow(self):
        self.follow(16, self.MID)
        self.assertEqual(self.overlays(1, 3), "glow=true")        # Tactical Mastery is next
        self.assertEqual(self.overlays(2, 2), "")                  # Cruelty has nothing
        self.hover(self.icon("coming", "Cruelty", "1/5"))
        self.assertEqual(self.overlays(2, 2), "hover=true")
        self.assertEqual(self.overlays(1, 3), "glow=true")        # the next stays lit
        # the overlay is a blue of the addon's own, not the glow's
        self.assertEqual(L.eval("BUTTONS[NODE(2, 2)].children[1].regions[1].color[3]"), 1)
        self.hover(self.icon("coming", "Cruelty", "1/5"), "OnLeave")
        self.assertEqual(self.overlays(2, 2), "hover=false")
        self.assertEqual(self.overlays(1, 3), "glow=true")
        # the next one's own icon lights its button over the glow, and leaving leaves the glow
        self.hover(self.icon("next", "Tactical Mastery", "3/5"))
        self.assertEqual(self.overlays(1, 3), "glow=true hover=true")
        self.hover(self.icon("next", "Tactical Mastery", "3/5"), "OnLeave")
        self.assertEqual(self.overlays(1, 3), "glow=true hover=false")
        # one overlay at a time
        self.hover(self.icon("taken", "Deflection", "5/5"))
        self.hover(self.icon("coming", "Cruelty", "2/5"))
        self.assertEqual((self.overlays(1, 1), self.overlays(2, 2)), ("glow=false hover=false", "hover=true"))   # Deflection had the glow once, in an earlier test

    def test_hover_writes_nothing_on_the_games_button(self):
        self.follow(16, self.MID)
        self.hover(self.icon("coming", "Cruelty", "1/5"))
        self.hover(self.icon("next", "Tactical Mastery", "3/5"))
        # the button has only what the mock gave it, and our overlay is a child frame of ours
        keys = L.eval("function() local out = {} for k in pairs(BUTTONS[NODE(2, 2)]) do out[#out + 1] = k end table.sort(out) return table.concat(out, ',') end")()
        self.assertEqual(keys, "children,points,regions")
        self.assertTrue(L.eval("BUTTONS[NODE(2, 2)].children[1].parent == BUTTONS[NODE(2, 2)]"))

    def test_hover_shows_the_talents_tooltip(self):
        self.follow(16, self.MID)
        i = self.icon("coming", "Cruelty", "1/5")
        self.hover(i)
        self.assertTrue(L.eval("TIP.owner == ForeverArmouryTalentStrip.icons[%d]" % i))
        self.assertEqual(L.eval("TIP.spell"), L.eval("NODE(2, 2) * 10"))   # the trait definition's spell
        self.assertEqual(list(L.eval("TIP.lines").values()), ["Level 21 · Rank 1 of 5"])
        self.assertTrue(L.eval("TIP.shown"))
        self.hover(i, "OnLeave")
        self.assertFalse(L.eval("TIP.shown"))
        # a taken rank says so
        self.hover(self.icon("taken", "Tactical Mastery", "2/5"))
        self.assertEqual(list(L.eval("TIP.lines").values()), ["Level 16 · Rank 2 of 5", "Taken"])
        self.assertEqual(L.eval("TIP.spell"), L.eval("NODE(1, 3) * 10"))

    def test_hover_survives_a_redraw_and_ends_with_the_strip(self):
        self.follow(16, self.MID)
        self.hover(self.icon("coming", "Cruelty", "1/5"))
        L.run("FA.Refresh()")   # the game redraws its window while the mouse is on the icon
        self.assertEqual(self.overlays(2, 2), "hover=true")
        self.assertTrue(L.eval("TIP.shown"))
        L.run("FA.SetActive(nil); FA.Refresh()")   # the build is let go with the mouse still there
        self.assertEqual(self.overlays(2, 2), "hover=false")
        self.assertFalse(L.eval("TIP.shown"))
        self.assertFalse(L.eval("ForeverArmouryTalentStrip.shown"))
        self.follow(16, self.MID)
        L.run("FA.SetActive(FA.BuildsFor('warrior')[1].id); FA.Refresh()")
        self.hover(self.icon("coming", "Cruelty", "1/5"))
        L.run("FA.SetPart('plan', false)")
        self.assertEqual(self.overlays(2, 2), "hover=false")
        L.run("FA.SetPart('plan', true)")

    # ---- the panel's build list as a section
    def header(self):
        return L.eval("function() local h = ForeverArmouryTalentPanel.header; return h.text.text, h.sign.texture end")()

    def listed(self):
        return L.eval("function() local n = 0 for _, r in ipairs(ForeverArmouryTalentPanel.rows) do if r.shown then n = n + 1 end end return n end")()

    def height(self):
        return L.eval("ForeverArmouryTalentPanel.height")

    PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"

    def test_the_build_list_is_open_until_a_build_is_followed(self):
        L.run("FA.Refresh()")
        self.assertEqual(self.header(), ("Builds (0)", self.MINUS))
        L.run("FA.ImportText('FAT1-warrior-Arms-" + GATED + " FAT1-warrior-Fury-0101 FAT1-warrior-Prot-0a')")
        self.assertEqual(self.header(), ("Builds (3)", self.MINUS))   # a new user sees the list
        self.assertEqual(self.listed(), 3)
        self.assertEqual(self.height(), 152 + 3 * 21 + 50)
        # picking one closes it, to the followed build's name
        L.run("local r = ForeverArmouryTalentPanel.rows[2]; r.scripts.OnClick(r)")
        self.assertEqual(L.eval("FA.ActiveBuild().name"), "Fury")
        self.assertEqual(self.header(), ("Fury", self.PLUS))
        self.assertEqual(self.listed(), 0)
        self.assertEqual(self.height(), 202)
        self.assertFalse(L.eval("ForeverArmouryTalentPanel.up.shown"))
        self.assertIn("Next:", self.panel("status"))   # the status and Apply stay
        self.assertEqual(self.panel("apply")[0], "Apply 2 points")

    def test_the_header_opens_and_closes_the_list_for_the_character(self):
        L.run("FA.ImportText('FAT1-warrior-Arms-" + GATED + " FAT1-warrior-Fury-0101')")
        L.run("FA.SetActive(FA.BuildsFor('warrior')[1].id); FA.Refresh()")
        self.assertEqual((self.header(), self.listed()), (("Arms", self.PLUS), 0))
        self.assertIsNone(L.eval("FA.char.buildsOpen"))   # nobody has chosen: the default is derived
        press = lambda: L.run("local h = ForeverArmouryTalentPanel.header; h.scripts.OnClick(h)")
        press()
        self.assertEqual((self.header(), self.listed(), self.height()), (("Builds (2)", self.MINUS), 2, 152 + 2 * 21 + 50))
        self.assertTrue(L.eval("FA.char.buildsOpen"))
        # open on purpose, it stays open when another build is picked
        L.run("local r = ForeverArmouryTalentPanel.rows[2]; r.scripts.OnClick(r)")
        self.assertEqual((self.header()[0], self.listed()), ("Builds (2)", 2))
        press()
        self.assertEqual((self.header(), self.listed()), (("Fury", self.PLUS), 0))
        self.assertEqual(L.eval("FA.char.buildsOpen"), False)
        # closed on purpose, it stays closed with no build followed: the header says how many there are
        L.run("FA.SetActive(nil); FA.Refresh()")
        self.assertEqual((self.header(), self.listed()), (("Builds (2)", self.PLUS), 0))
        # another character has its own
        L.run("ForeverArmouryCharDB = {}; FA.char = ForeverArmouryCharDB; FA.Refresh()")
        self.assertEqual((self.header(), self.listed()), (("Builds (2)", self.MINUS), 2))

    def test_the_collapsed_header_names_the_build_as_typed(self):
        L.run("FA.ImportText('FAT1-warrior-A%7CcffFF0000Red%7Cr-" + GATED + " FAT1-warrior--0a')")   # one named with a colour escape, one not at all
        L.run("FA.SetActive(FA.BuildsFor('warrior')[1].id); FA.Refresh()")
        self.assertEqual(self.header()[0], "A||cffFF0000Red||r")
        L.run("FA.SetActive(FA.BuildsFor('warrior')[2].id); FA.Refresh()")
        self.assertEqual(self.header()[0], "Unnamed")

    def test_a_long_list_collapses_with_its_arrows(self):
        L.run("FA.ImportText('" + " ".join("FAT1-warrior-B%d-01%02x" % (n, n) for n in range(1, 26)) + "')")
        self.assertEqual((self.header()[0], self.listed(), self.height()), ("Builds (25)", 10, 152 + 210 + 22 + 50))
        self.assertTrue(L.eval("ForeverArmouryTalentPanel.down.shown"))
        L.run("local r = ForeverArmouryTalentPanel.rows[3]; r.scripts.OnClick(r)")
        self.assertEqual((self.header()[0], self.listed(), self.height()), ("B3", 0, 202))
        self.assertFalse(L.eval("ForeverArmouryTalentPanel.down.shown"))
        self.assertFalse(L.eval("ForeverArmouryTalentPanel.more.shown"))
        L.run("local h = ForeverArmouryTalentPanel.header; h.scripts.OnClick(h)")
        self.assertEqual((self.listed(), L.eval("ForeverArmouryTalentPanel.down.shown")), (10, True))

    def test_import_errors_and_export(self):
        ok, err = L.eval("function(t) return FA.ImportText(t) end")("nonsense")
        self.assertFalse(ok)
        self.assertIn("isn't a build code", err)
        L.run("FA.ImportText('FAT1-warrior-Arms-0101.mage-Frost-0a'); FA.OpenImport(FA.ExportCode())")
        self.assertEqual(L.eval("ForeverArmouryImportText.text"), "FAT3-0-warrior-Arms-0101-0")

    def test_the_part_switch_hides_the_panel(self):
        L.run("FA.SetPart('plan', false)")
        self.assertFalse(L.eval("ForeverArmouryTalentPanel.shown"))
        L.run("FA.SetPart('plan', true)")
        self.assertTrue(L.eval("ForeverArmouryTalentPanel.shown"))

    def test_slash_commands_run(self):
        for cmd in ["", "help", "list", "export", "import", "apply", "plan off", "plan on", "gear", "gear off", "gear", "gear on", "options", "debug"]:
            L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")(cmd)
        self.assertIn("Leveling gear off.", L.eval("PRINTED"))
        self.assertIn("The leveling gear part is off.", L.eval("PRINTED"))
        self.assertEqual(L.eval("TOGGLED"), 1)   # the second /fa gear found the part off

    # ---- the gear panel
    def gear(self):
        return L.eval("function() local p = ForeverArmouryGearPanel; local rows = {} for i, r in ipairs(p.rows) do if r.shown then rows[i] = (r.slot.text or '') .. ' ' .. (r.item.text or '') .. ' ' .. (r.state.text or '') .. ' | ' .. (r.from.text or '') end end "
                      "return p.shown, p.status.text, p.spec.text, rows end")()

    def test_gear_panel_without_a_route(self):
        L.run("FA.RefreshGear()")
        shown, status, spec, rows = self.gear()
        self.assertTrue(shown)
        self.assertIn("No gear route for this class yet", status)
        self.assertEqual(spec, "Pick a spec")
        self.assertEqual(len(rows), 0)

    def test_one_paste_imports_a_build_and_a_route(self):
        ok, said = L.eval("function(t) return FA.ImportText(t) end")("FAT1-warrior-Arms-" + GATED + "\n" + ROUTE_CODE)
        self.assertTrue(ok)
        self.assertEqual(said, "1 Warrior build imported. Following Arms. 1 Warrior gear route imported.")   # the build followed first, so the route has its spec
        L.run("PLAYER.level = 14; ITEMS = { [271097] = { 'Spiritwraith Drape', 'INVTYPE_CLOAK' }, [279895] = { 'Ironforge Greathammer', 'INVTYPE_2HWEAPON' } }; "
              "EQUIPPED = { [15] = 271097 }; FA.RefreshGear()")
        shown, status, spec, rows = self.gear()
        self.assertEqual(spec, "Build: Arms")
        self.assertIn("Arms, Alliance, level 14: 1 of 5 pieces of your level had.", status)
        self.assertIn("To get now, then what's coming:", status)
        rows = [rows[i] for i in sorted(rows.keys())]
        self.assertEqual(len(rows), 5)   # four to get, one coming
        self.assertEqual(rows[0], "Hands |cff808080item 270231|r |cffff8080get|r | dungeon 3065: NPC 3495")   # not loaded yet: its id
        self.assertIn("Main hand |cffffffff|Hitem:279895::::::::60:::::|h[Ironforge Greathammer]|h|r |cffff8080get|r | Quest: #96393", rows)
        self.assertEqual(rows[4], "Neck |cff808080item 273088|r at 17 | dungeon 43: NPC 585")
        # with everything of its level had, and at 60 with the whole route
        L.run("EQUIPPED = { [15] = 271097, [10] = 270231, [7] = 270260, [8] = 270229, [16] = 279895 }; FA.RefreshGear()")
        self.assertIn("Nothing to get at this level. Coming next:", self.gear()[1])
        L.run("PLAYER.level = 60; BAGS = { [0] = { 273088 } }; FA.RefreshGear()")
        self.assertIn("Every piece of the route is yours.", self.gear()[1])
        self.assertEqual(len(self.gear()[3]), 0)

    def test_the_spec_button_cycles_and_the_part_switch_hides_the_panel(self):
        L.run("FA.ImportText('" + ROUTE_CODE + "')")
        self.assertIn("Follow a build, or pick the route's spec", L.eval("PRINTED"))
        self.assertEqual(self.gear()[2], "Pick a spec")
        press = L.eval("function() FA.CycleGearSpec(); return ForeverArmouryGearPanel.spec.text, ForeverArmouryGearPanel.status.text end")
        self.assertEqual(press()[0], "Spec: Arms")
        self.assertIn("Arms, Alliance, level 60", self.gear()[1])
        self.assertEqual(press()[0], "Spec: Fury")
        self.assertIn("No Fury route for Alliance here yet", self.gear()[1])
        self.assertEqual(press()[0], "Spec: Protection")
        self.assertEqual(press()[0], "Pick a spec")
        L.run("FA.SetPart('gear', false)")
        self.assertFalse(L.eval("ForeverArmouryGearPanel.shown"))
        L.run("FA.SetPart('gear', true)")
        self.assertTrue(L.eval("ForeverArmouryGearPanel.shown"))
        L.run("CharacterFrame.IsShown = function() return false end; FA.RefreshGear()")
        self.assertFalse(L.eval("ForeverArmouryGearPanel.shown"))
        L.run("CharacterFrame.IsShown = nil; FA.RefreshGear()")
        self.assertTrue(L.eval("ForeverArmouryGearPanel.shown"))

    # ---- the Legacy panel
    def legacy(self):
        """What the Legacy panel says: shown, status, Apply's text, whether it's enabled and its tooltip, the plan rows and the perk rows."""
        return L.eval("""function()
          local p = ForeverArmouryLegacyPanel
          local plans, perks = {}, {}
          for i, r in ipairs(p.rows) do if r.shown then plans[#plans + 1] = (r.mark.shown and '> ' or '  ') .. r.text.text end end
          for i, r in ipairs(p.perks) do if r.shown then perks[#perks + 1] = r.name.text .. ' ' .. (r.ranks.text or '') end end
          return p.shown, p.status.text, p.apply.text, p.apply.enabled, p.apply.why, table.concat(plans, '\\n'), table.concat(perks, '\\n')
        end""")()

    def lit(self):
        """The perks whose button has our glow showing, by name."""
        return sorted(L.eval("""function()
          local out = {}
          for _, p in ipairs(FA.Legacy.PERKS) do
            local b = LBUTTONS[p.node]
            if b then for _, c in ipairs(b.children) do if c.shown then out[#out + 1] = p.name end end end
          end
          return out
        end""")().values())

    def test_legacy_panel_without_plans(self):
        shown, status, apply, enabled, why, plans, perks = self.legacy()
        self.assertTrue(shown)
        self.assertIn("Pick a plan to follow.", status)
        self.assertIn("Legacy points: not told by the game, cap 16.", status)   # the trees are not there (no configs)
        self.assertEqual((apply, enabled, why, plans, perks), ("Apply", False, "Pick a plan to follow first.", "", ""))
        self.assertEqual(L.eval("ForeverArmouryLegacyPanel.plansHeader.text"), "Plans (0)")
        # it sits beside the Legacy window
        self.assertTrue(L.eval("ForeverArmouryLegacyPanel.points[1][2] == LegacySystemFrame"))
        self.assertEqual(L.eval("ForeverArmouryLegacyPanel.points[1][3]"), "TOPRIGHT")

    def test_import_follow_light_and_apply_a_legacy_plan(self):
        L.run("LEGACY_ON = true")
        ok, said = L.eval("function(t) return FA.ImportText(t) end")(SAMPLE)
        self.assertTrue(ok)
        self.assertEqual(said, "1 Legacy plan imported for the account. Following Gatherer's Path.")
        shown, status, apply, enabled, why, plans, perks = self.legacy()
        self.assertEqual(plans, "> Gatherer's Path")
        self.assertIn("Following |cffffd100Gatherer's Path|r.", status)
        self.assertIn("Legacy points: 16 available, 0 of 16 spent.", status)
        self.assertIn("Next: |cffffd100Working Overtime|r 1/5 (Professions).", status)
        self.assertEqual((apply, enabled), ("Apply 16 ranks", True))
        self.assertEqual(why, "Working Overtime x5, Master Chef, Well Rested x5, Talented, Gourmand x3, The Quick and the Dead")
        # the perks the plan wants, in the trees' order; the next of the tree is gold, and the rest white
        self.assertEqual(perks.split("\n"), [
            "|cffffffffMaster Chef|r |cffffffff0/1|r", "|cffffd100Working Overtime|r |cffffd1000/5|r", "|cffffffffWell Rested|r |cffffffff0/5|r",
            "|cffffffffTalented|r |cffffffff0/1|r", "|cffffffffGourmand|r |cffffffff0/3|r", "|cffffffffThe Quick and the Dead|r |cffffffff0/1|r"])
        # the tree shown is Professions: its next perk is lit, the other trees' have no button
        self.assertEqual(self.lit(), ["Working Overtime"])
        L.run("LSHOWN_TREE = 1188; FA.RefreshLegacy()")
        self.assertEqual(self.lit(), ["Well Rested"])
        L.run("LSHOWN_TREE = 1189; FA.RefreshLegacy()")
        self.assertEqual(self.lit(), ["Gourmand"])
        # Apply: one confirm naming the perks, then the buying
        L.run("FA.AskApplyLegacy()")
        popup = L.eval("POPUPS[1]")
        self.assertEqual(popup.which, "FOREVERARMOURY_LEGACY_APPLY")
        self.assertEqual(popup.text, "Buy 16 Legacy ranks as Gatherer's Path says?\n\nWorking Overtime x5, Master Chef, Well Rested x5, Talented, Gourmand x3, The Quick and the Dead")
        self.assertEqual(L.eval("#LOG"), 0)   # nothing is bought before the confirm
        L.run("StaticPopupDialogs.FOREVERARMOURY_LEGACY_APPLY.OnAccept(nil, POPUPS[1].data)")
        self.assertIn("Bought as Gatherer's Path says: Working Overtime x5", L.eval("PRINTED"))
        self.assertEqual(L.eval("LEG[110290]"), 5)
        shown, status, apply, enabled, why, plans, perks = self.legacy()
        self.assertIn("Every rank of this plan is bought.", status)
        self.assertIn("Legacy points: 0 available, 16 of 16 spent.", status)
        self.assertEqual((apply, enabled, why), ("Apply", False, "Every rank of this plan is bought."))
        self.assertTrue(all("|cff40ff40" in line for line in perks.split("\n")))
        self.assertEqual(self.lit(), [])

    def test_the_apply_button_follows_the_points_the_window_and_combat(self):
        L.run("LEGACY_ON = true; FA.ImportText('%s'); LPOINTS = 4; FA.RefreshLegacy()" % SAMPLE)
        text, enabled, why = self.legacy()[2:5]
        self.assertEqual((text, enabled), ("Apply 4 ranks", True))
        self.assertEqual(why, "Working Overtime x4\n12 more when you have the points.")
        L.run("LPOINTS = 0; FA.RefreshLegacy()")
        self.assertEqual(self.legacy()[2:5], ("Apply", False, "You have no Legacy points to spend."))
        L.run("LPOINTS = 16; COMBAT = true; EVENT('PLAYER_REGEN_DISABLED'); FLUSH()")
        self.assertEqual(self.legacy()[2:5], ("Apply", False, "You can't change Legacy perks in combat."))
        self.assertIn("Next: |cffffd100Working Overtime|r", self.legacy()[1])   # the rest of the panel is as it was
        L.run("COMBAT = false; EVENT('PLAYER_REGEN_ENABLED'); FLUSH(); LSTAGED[202] = { [110301] = 1 }; FA.RefreshLegacy()")
        self.assertEqual(self.legacy()[2:5], ("Apply", False, "The Legacy window has changes waiting. Apply or undo them there first."))
        L.run("LSTAGED = {}; EVENT('TRAIT_NODE_CHANGED'); FLUSH()")
        self.assertEqual(self.legacy()[2:4], ("Apply 16 ranks", True))
        # pressing Apply with nothing to buy says why in chat and opens no confirm
        L.run("LPOINTS = 0; POPUPS = {}; PRINTED = ''; FA.AskApplyLegacy()")
        self.assertEqual(L.eval("#POPUPS"), 0)
        self.assertIn("You have no Legacy points to spend.", L.eval("PRINTED"))

    def test_a_refused_buy_is_said_in_chat_and_the_panel_follows(self):
        L.run("LEGACY_ON = true; LREFUSE = 110298; FA.ImportText('%s'); FA.AskApplyLegacy()" % SAMPLE)
        L.run("StaticPopupDialogs.FOREVERARMOURY_LEGACY_APPLY.OnAccept(nil, POPUPS[1].data)")
        printed = L.eval("PRINTED")
        self.assertIn("The game wouldn't take Talented rank 1 (Adventure). Nothing was bought in Adventure.", printed)
        self.assertIn("Bought: Working Overtime x5, Master Chef, Gourmand x3, The Quick and the Dead.", printed)
        self.assertIn("Next: |cffffd100Well Rested|r 1/5 (Adventure).", self.legacy()[1])

    def test_a_plan_from_another_build_is_shown_and_never_bought(self):
        L.run("LEGACY_ON = true")
        ok, said = L.eval("function(t) return FA.ImportText(t) end")("FAL1-70001-Old-" + SAMPLE_RANKS)
        self.assertTrue(ok)
        self.assertIn("1 Legacy plan imported for the account. 1 is from another client build than the addon's Legacy perks (70425), so it is shown and never bought. Following Old.", said)
        shown, status, apply, enabled, why, plans, perks = self.legacy()
        self.assertEqual(plans, "> |cffff6060! |rOld")
        self.assertIn("client build 70001", status)
        self.assertEqual((apply, enabled), ("Apply", False))
        self.assertIn("client build 70001", why)
        # its perks show with the ranks wanted and no ranks had
        self.assertEqual(perks.split("\n")[0], "|cff909090Master Chef|r |cff9090901|r")
        self.assertEqual(self.lit(), [])
        L.run("POPUPS = {}; FA.AskApplyLegacy()")
        self.assertEqual(L.eval("#POPUPS"), 0)

    def test_the_plan_list_follows_forgets_and_scrolls(self):
        codes = " ".join("FAL1-70425-P%d-%s" % (n, "0" * 26 + str(n % 6)) for n in range(1, 9))
        L.run("FA.ImportText('%s')" % codes)
        self.assertEqual(L.eval("#FA.Legacy.Plans()"), 8)
        self.assertIsNone(L.eval("FA.Legacy.Active()"))   # eight at once: none is followed for the account
        plans = self.legacy()[5].split("\n")
        self.assertEqual(plans, ["  P1", "  P2", "  P3", "  P4", "  P5"])
        self.assertEqual(L.eval("ForeverArmouryLegacyPanel.more.text"), "1-5 of 8")
        self.assertEqual((L.eval("ForeverArmouryLegacyPanel.up.enabled"), L.eval("ForeverArmouryLegacyPanel.down.enabled")), (False, True))
        L.run("local r = ForeverArmouryLegacyPanel.rows[2]; r.scripts.OnClick(r)")
        self.assertEqual(L.eval("FA.Legacy.Active().name"), "P2")
        self.assertEqual(self.legacy()[5].split("\n")[1], "> P2")
        L.run("local r = ForeverArmouryLegacyPanel.rows[2]; r.scripts.OnClick(r)")   # a second press stops following it
        self.assertIsNone(L.eval("FA.Legacy.Active()"))
        L.run("local b = ForeverArmouryLegacyPanel.down; b.scripts.OnClick(b)")
        self.assertEqual(self.legacy()[5].split("\n"), ["  P4", "  P5", "  P6", "  P7", "  P8"])   # the page, 4 on; it stops at the end
        self.assertEqual(L.eval("ForeverArmouryLegacyPanel.more.text"), "4-8 of 8")
        L.run("local p = ForeverArmouryLegacyPanel; p.scripts.OnMouseWheel(p, 1)")
        self.assertEqual(self.legacy()[5].split("\n")[0], "  P3")
        # forgetting asks, and a colour escape in a name is drawn as typed
        L.run("FA.ImportText('FAL1-70425-A%7CcffFF0000Red%7Cr-" + SAMPLE_RANKS + "')")
        self.assertEqual(L.eval("FA.Legacy.Plans()[9].name"), "A|cffFF0000Red|r")
        L.run("FA.ScrollLegacy(100)")
        self.assertEqual(self.legacy()[5].split("\n")[-1], "  A||cffFF0000Red||r")
        L.run("local r = ForeverArmouryLegacyPanel.rows[5]; r.forget.scripts.OnClick({ GetParent = function() return r end })")
        self.assertEqual(L.eval("POPUPS[1].which"), "FOREVERARMOURY_FORGET_LEGACY")
        self.assertEqual(L.eval("POPUPS[1].text"), "A||cffFF0000Red||r")
        L.run("StaticPopupDialogs.FOREVERARMOURY_FORGET_LEGACY.OnAccept(nil, POPUPS[1].data)")
        self.assertEqual(L.eval("#FA.Legacy.Plans()"), 8)

    def test_a_perk_the_plan_cant_buy_is_red(self):
        L.run("LEGACY_ON = true; FA.ImportText('FAL1-70425-Odd-" + "1" + "0" * 26 + "')")
        shown, status, *_ = self.legacy()
        self.assertIn("Master Chef can't be bought: the plan has too few points in Professions before it.", status)
        self.assertEqual(self.legacy()[2:4], ("Apply", False))
        self.assertIn("|cffff6060Master Chef|r", self.legacy()[6])

    def test_ranks_the_account_has_beyond_the_plan_are_said(self):
        L.run("LEGACY_ON = true; LSET({ ['Reinforce'] = 3 }); FA.ImportText('%s')" % SAMPLE)
        self.assertIn("3 ranks aren't in this plan; Apply never takes points back.", self.legacy()[1])

    def test_the_legacy_panel_follows_the_window_and_the_part_switch(self):
        L.run("LegacySystemFrame:Hide(); FA.RefreshLegacy()")
        self.assertFalse(L.eval("ForeverArmouryLegacyPanel.shown"))
        L.run("LegacySystemFrame:Show(); FA.RefreshLegacy()")
        self.assertTrue(L.eval("ForeverArmouryLegacyPanel.shown"))
        L.run("FA.SetPart('legacy', false)")
        self.assertFalse(L.eval("ForeverArmouryLegacyPanel.shown"))
        self.assertTrue(L.eval("ForeverArmouryTalentPanel.shown"))   # the others are as they were
        L.run("FA.SetPart('legacy', true)")
        self.assertTrue(L.eval("ForeverArmouryLegacyPanel.shown"))
        self.assertTrue(L.eval("FA.PartOn('legacy')"))   # on by default
        self.assertEqual(L.eval("FA.PARTS[3].key"), "legacy")
        # the window loading later hooks it once
        hooks = L.eval("#HOOKS")
        L.run("EVENT('ADDON_LOADED', 'Blizzard_LegacySystem')")
        self.assertEqual(L.eval("#HOOKS"), hooks)

    def test_the_glow_waits_for_the_tree_to_show_its_button(self):
        L.run("LEGACY_ON = true; FA.ImportText('%s')" % SAMPLE)
        self.assertEqual(self.lit(), ["Working Overtime"])
        L.run("LBUTTONS[110290].shown = false; FA.RefreshLegacy()")   # a button the tree hides
        self.assertEqual(self.lit(), [])
        # no tree panel, or no tree page: no glow, no error
        L.run("LBUTTONS[110290].shown = true; SAVED = LegacySystemFrame.TreePage; LegacySystemFrame.TreePage = {}; FA.RefreshLegacy()")
        self.assertEqual(self.lit(), [])
        L.run("LegacySystemFrame.TreePage = false; FA.RefreshLegacy()")   # (the mock answers a function for a key that is nil)
        self.assertEqual(self.lit(), [])
        L.run("LegacySystemFrame.TreePage = SAVED; FA.RefreshLegacy()")
        self.assertEqual(self.lit(), ["Working Overtime"])

    def test_slash_legacy(self):
        L.run("LTOGGLED = 0; LegacySystemFrame:Show()")
        L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")("legacy")
        self.assertEqual(L.eval("LTOGGLED"), 1)
        self.assertFalse(L.eval("LegacySystemFrame.shown"))
        # opened again, it goes to the trees page (the game's event for it), once, not when it was already open
        L.run("EventRegistry = { TriggerEvent = function(_, name, id) PAGES = (PAGES or '') .. name .. id .. ' ' end }; PAGES = ''")
        L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")("legacy")
        self.assertEqual(L.eval("PAGES"), "Legacy.SelectPage3 ")
        L.run("EventRegistry = nil")
        self.assertEqual(L.eval("LTOGGLED"), 2)
        self.assertTrue(L.eval("ForeverArmouryLegacyPanel.shown"))
        L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")("legacy off")
        self.assertIn("Legacy plans off.", L.eval("PRINTED"))
        self.assertFalse(L.eval("ForeverArmouryLegacyPanel.shown"))
        L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")("legacy")
        self.assertIn("The Legacy plans part is off. /fa legacy on turns it on.", L.eval("PRINTED"))
        self.assertEqual(L.eval("LTOGGLED"), 2)
        L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")("legacy on")
        self.assertIn("Legacy plans on.", L.eval("PRINTED"))
        self.assertTrue(L.eval("FA.PartOn('legacy')"))
        # the game's opener doing nothing (the Legacy track hasn't begun): said
        L.run("SAVED = ToggleLegacySystemUI; ToggleLegacySystemUI = function() end; LegacySystemFrame:Hide(); PRINTED = ''")
        L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")("legacy")
        self.assertIn("The game didn't open the Legacy window.", L.eval("PRINTED"))
        # a client with no opener at all, and no window
        L.run("ToggleLegacySystemUI = nil; SAVEDF = LegacySystemFrame; LegacySystemFrame = nil; PRINTED = ''")
        L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")("legacy")
        self.assertIn("This client has no Legacy window to open.", L.eval("PRINTED"))
        L.run("ToggleLegacySystemUI = SAVED; LegacySystemFrame = SAVEDF")

    def test_one_paste_imports_a_build_and_a_legacy_plan(self):
        L.run("LEGACY_ON = true")
        ok, said = L.eval("function(t) return FA.ImportText(t) end")("FAT1-warrior-Arms-" + GATED + "\n" + SAMPLE)
        self.assertTrue(ok)
        self.assertEqual(said, "1 Warrior build imported. Following Arms. 1 Legacy plan imported for the account. Following Gatherer's Path.")
        # with a gear route too, and in that order
        ok, said = L.eval("function(t) return FA.ImportText(t) end")(ROUTE_CODE + " " + SAMPLE_2)
        self.assertEqual(said, "1 Warrior gear route imported. 1 Legacy plan imported for the account.")   # Second is a plan more: the one followed stays
        self.assertEqual(L.eval("FA.Legacy.Active().name"), "Gatherer's Path")

    def test_import_errors_name_the_legacy_code_pasted(self):
        imp = L.eval("function(t) return FA.ImportText(t) end")
        self.assertIn("isn't a build code", imp("nonsense")[1])
        self.assertIn("Plan 1 of that code doesn't read", imp("FAL1-70425-A-0101")[1])   # only a Legacy code: its error
        self.assertIn("newer version", imp("FAL2-70425-A-" + SAMPLE_RANKS)[1])
        self.assertIn("Build 1 of that code doesn't read", imp("FAT2-70170-warrior-A-0a0 FAL1-70425-A-0101")[1])   # both broken: the build code's error
        ok, said = imp("FAT1-warrior-Arms-0101 FAL1-70425-A-0101")   # the build reads, the plan doesn't: both said
        self.assertTrue(ok)
        self.assertIn("1 Warrior build imported.", said)
        self.assertIn("Plan 1 of that code doesn't read", said)
        self.assertEqual(L.eval("#FA.Legacy.Plans()"), 0)
        ok, said = imp("FAT1-warrior-Arms-0z " + SAMPLE)   # the plan reads, the build doesn't
        self.assertTrue(ok)
        self.assertIn("1 Legacy plan imported for the account.", said)
        self.assertIn("Build 1 of that code doesn't read", said)
        ok, said = imp("FAG1-warrior-0 " + SAMPLE)   # a broken gear route beside a good plan
        self.assertTrue(ok)
        self.assertIn("Route 1 of that code doesn't read", said)

    def test_export_puts_the_plans_in_the_box(self):
        L.run("PRINTED = ''")
        exportBtn = "for _, f in ipairs(ForeverArmouryLegacyPanel.children) do if f.kind == 'Button' and f.text == 'Export' then f.scripts.OnClick(f) end end"
        L.run(exportBtn)
        self.assertIn("No Legacy plans yet.", L.eval("PRINTED"))
        L.run("FA.ImportText('%s')" % SAMPLE)
        L.run(exportBtn)
        self.assertEqual(L.eval("ForeverArmouryImportText.text"), SAMPLE)
        self.assertIn("Every Legacy plan.", L.eval("ForeverArmouryImport.status.text"))
        # the box's own Export gives the class's builds and the account's plans, one a line
        L.run("FA.ImportText('FAT1-warrior-Arms-" + GATED + "')")
        L.run("for _, f in ipairs(ForeverArmouryImport.children) do if f.kind == 'Button' and f.text == 'Export' then f.scripts.OnClick(f) end end")
        text = L.eval("ForeverArmouryImportText.text")
        self.assertEqual(text.split("\n"), ["FAT3-0-warrior-Arms-" + GATED + "-0", SAMPLE])   # a FAT1 build is written with build 0
        self.assertIn("Every build of your class and every Legacy plan.", L.eval("ForeverArmouryImport.status.text"))

    def test_import_errors_name_the_code_pasted(self):
        imp = L.eval("function(t) return FA.ImportText(t) end")
        self.assertIn("isn't a build code", imp("nonsense")[1])
        self.assertIn("Route 1 of that code doesn't read", imp("FAG1-warrior-0")[1])
        self.assertIn("Build 1 of that code doesn't read", imp("FAT2-70170-warrior-A-0a0 FAG1-warrior-0")[1])   # both broken: the build code's error
        ok, said = imp("FAT1-warrior-Arms-0101 FAG1-warrior-0")   # the build reads, the route doesn't: both said
        self.assertTrue(ok)
        self.assertIn("1 Warrior build imported.", said)
        self.assertIn("Route 1 of that code doesn't read", said)
        ok, said = imp("FAT1-warrior-Arms-0z " + ROUTE_CODE)
        self.assertTrue(ok)
        self.assertIn("1 Warrior gear route imported.", said)
        self.assertIn("Build 1 of that code doesn't read", said)


if __name__ == "__main__":
    print("Lua runtime:", L.flavour, L.eval("_VERSION"))
    unittest.main(argv=sys.argv[:1], verbosity=1)
