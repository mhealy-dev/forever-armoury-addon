"""Checks the addon's pure parts, BuildCode.lua, Talents.lua and Builds.lua, in a Lua runtime with the game's talent
API stubbed: a build code read and written, the game's trait nodes turned into trees of cells, and the next-talent walk
over a made-up talent tree. Run with `python test/run.py` (needs `pip install lupa`). The game's Lua is 5.1; LuaJIT's is
used when lupa has it, else lupa's default."""
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

-- the trait system: node ids 101.., placed on a grid 600 apart, trees 4000 apart, the second tree listed first so
-- the group order comes from orderIndex, not the list
NODES, DEFS = {}, {}
local id = 100
for t, tab in ipairs(TREE) do for i, x in ipairs(tab) do
  id = id + 1
  NODES[id] = { tab = t, talent = x, posX = (t - 1) * 4000 + (x[3] - 1) * 600 + 300, posY = 1500 + (x[2] - 1) * 600 }
  DEFS[id] = { spellID = id * 10, overrideName = nil }
end end
-- Config 7 is the active spec: its committed ranks are TREE's, and STAGED holds what's bought but not applied. Config 8
-- is the other spec (dual spec), its ranks in OTHER. A rank can be bought with a point to spend, below the talent's
-- max, and with (tier - 1) * 5 points already in its tree, as the game's trees gate them.
STAGED, OTHER, LOG = {}, {}, {}
SPEC = { active = 1, groups = 1 }
COMBAT, FAIL_COMMIT = false, false
local function rankOf(configID, nodeID)
  if configID == 8 then return OTHER[nodeID] or 0 end
  return NODES[nodeID].talent[4] + (STAGED[nodeID] or 0)
end
local function spentIn(configID, tab)
  local s = 0
  for id, n in pairs(NODES) do if not tab or n.tab == tab then s = s + rankOf(configID, id) end end
  return s
end
function UNSPENT() return math.max(0, PLAYER.level - 9) - spentIn(7) end
C_ClassTalents = {
  GetActiveConfigID = function() if API ~= "traits" then return nil end return SPEC.active == 1 and 7 or 8 end,
  CommitConfig = function(saved)
    LOG[#LOG + 1] = "commit"
    if FAIL_COMMIT then return false end
    for id, n in pairs(STAGED) do NODES[id].talent[4] = NODES[id].talent[4] + n end
    STAGED = {}
    return true
  end,
  CanChangeTalents = function() return true, true, "" end,
}
C_SpecializationInfo = {
  GetActiveSpecGroup = function() return SPEC.active end,
  GetCombatConfigIDForSpecGroup = function(g) return g == 1 and 7 or 8 end,
}
function GetNumSpecGroups() return SPEC.groups end
function InCombatLockdown() return COMBAT end
C_Traits = {
  GetConfigInfo = function(configID) return { ID = configID, treeIDs = { 55 }, name = "Primary" } end,
  GetGroupDisplayInfoByTreeID = function(treeID)
    return { { groupID = 20, orderIndex = 2, displayName = "Fury", icon = 2 }, { groupID = 10, orderIndex = 1, displayName = "Arms", icon = 1 }, { groupID = 30, orderIndex = 3, displayName = "Protection", icon = 3 } }
  end,
  GetTreeNodes = function(treeID) local ids = {} for k in pairs(NODES) do ids[#ids + 1] = k end table.sort(ids) return ids end,
  GetNodeInfo = function(configID, nodeID)
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
C_Spell = { GetSpellName = function(spellID) return NODES[spellID / 10].talent[1] end, GetSpellTexture = function(spellID) return spellID end }

function UnitLevel() return PLAYER.level end
function GetBuildInfo() return "1.60.1.70170", "70170", "Oct  2 2026", 16001 end   -- the build a code carries (#1215)
function UnitClass() return "Warrior", PLAYER.class end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
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
ForeverArmouryDB, ForeverArmouryCharDB = nil, nil
FA.Init()
FA.class = "warrior"
function RESET(api)
  API = api or "traits"
  ForeverArmouryDB, ForeverArmouryCharDB = nil, nil; FA.Init(); FA.Talents.Forget(); PLAYER.level = 60
  for _, tab in ipairs(TREE) do for _, t in ipairs(tab) do t[4] = 0 end end
  STAGED, OTHER, LOG = {}, {}, {}
  SPEC.active, SPEC.groups, COMBAT, FAIL_COMMIT = 1, 1, false, false
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
        self.assertEqual(write("warrior", "Arms PvP", PICKS), "FAT2-70170-warrior-Arms%20PvP-" + PICKS)
        self.assertEqual(write("mage", "", "0a"), "FAT2-70170-mage--0a")
        for name in ["Arms PvP", "", "Mage's build, 31/0/20!", "Ünïcödé 🙂 名前", "a" * 40, "50% crit", "-leading-dashes-", "dots.in.name", "  Two   words "]:
            code = write("warrior", name, PICKS)
            self.assertRegex(code, r"^FAT2-70170-warrior-[A-Za-z0-9%]*-[0-9a-r]+$")
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
        self.assertIn("newer version", say("FAT3-70170-warrior-Arms-0a"))
        for bad in ["FAT2-", "FAT2-70170", "FAT2-warrior-Arms-0a", "FAT2-x-warrior-Arms-0a"]:
            self.assertRegex(say(bad), r"doesn't read", bad)
        for bad in ["FAT2-70170-warrior", "FAT2-70170-warrior-Arms", "FAT2-70170-knight-Arms-0a", "FAT2-70170-warrior-Arms-0a0", "FAT2-70170-warrior-Arms-3a", "FAT2-70170-warrior-Arms-0z", "FAT2-70170-warrior-Arms-" + "0a" * 52, "FAT1-", "FAT1-knight-Arms-0a"]:
            self.assertRegex(say(bad), r"Build 1 .* doesn't read", bad)
        self.assertRegex(say("FAT2-70170-warrior-Arms-0a.warrior-Fury"), r"Build 2 .* doesn't read")
        self.assertRegex(say("FAT2-70170-warrior-Arms-0a..warrior-Fury-1a"), r"Build 2")
        for bad in ["FAT2-70170-warrior-Ar%2-0a", "FAT2-70170-warrior-Ar%ZZms-0a"]:
            self.assertRegex(say(bad), r"name of build 1 .* cut off", bad)

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


class Builds(unittest.TestCase):
    def setUp(self):
        L.run("RESET('traits')")

    def test_add_find_forget_and_export(self):
        add = L.eval("function(text) local b = assert(FA.Code.Read(text)); return FA.AddBuilds(b) end")
        self.assertEqual(add("FAT1-warrior-Arms-0101.warrior-Fury-1a1a.mage-Frost-2b"), (2, 1))
        names = L.eval("function() local out = {} for _, b in ipairs(FA.BuildsFor('warrior')) do out[#out + 1] = b.id .. '=' .. b.name .. ':' .. b.picks end return table.concat(out, ' ') end")
        self.assertEqual(names(), "1=Arms:0101 2=Fury:1a1a")
        # the same name again replaces the points and keeps the id
        self.assertEqual(add("FAT1-warrior-Arms-010102"), (1, 0))
        self.assertEqual(names(), "1=Arms:010102 2=Fury:1a1a")
        self.assertEqual(L.eval("FA.ExportCode()"), "FAT2-70170-warrior-Arms-010102.warrior-Fury-1a1a")
        L.run("FA.SetActive(2)")
        self.assertEqual(L.eval("FA.ActiveBuild().name"), "Fury")
        self.assertTrue(L.eval("FA.ForgetBuild('warrior', 2)"))
        self.assertIsNone(L.eval("FA.ActiveBuild()"))
        self.assertEqual(names(), "1=Arms:010102")
        self.assertFalse(L.eval("FA.ForgetBuild('warrior', 9)"))

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


UI_STUB = r"""
-- Any frame: every method answers a new frame, except the few whose answers get used as numbers, text or flags.
local ANSWERS = { GetFrameLevel = 1, IsShown = true, GetWidth = 400, GetText = "", GetChecked = true, GetID = 1 }
SHOWN, POPUPS, HOOKS = {}, {}, {}
local function frame(name)
  local f = { name = name }
  return setmetatable(f, { __index = function(t, k)
    if ANSWERS[k] ~= nil then return function() return ANSWERS[k] end end
    if k == "SetText" then return function(self, text) rawset(self, "text", text) end end
    if k == "Enable" then return function(self) rawset(self, "enabled", true) end end
    if k == "Disable" then return function(self) rawset(self, "enabled", false) end end
    if k == "Show" then return function(self) rawset(self, "shown", true) end end
    if k == "Hide" then return function(self) rawset(self, "shown", false) end end
    if k == "HookScript" then return function(self, event, fn) HOOKS[#HOOKS + 1] = fn end end
    return function() return frame() end
  end })
end
CreateFrame = function(kind, name) local f = frame(name); if name then _G[name] = f end return f end
UIParent, GameTooltip, ChatFontNormal = frame("UIParent"), frame("GameTooltip"), frame()
UISpecialFrames = {}
tinsert = table.insert
hooksecurefunc = function(a, b, c) HOOKS[#HOOKS + 1] = c or b end
StaticPopup_Show = function(which, text, _, data) POPUPS[#POPUPS + 1] = { which = which, text = text, data = data } end
PlayerSpellsFrame = frame("PlayerSpellsFrame")
PlayerSpellsFrame.TalentsFrame = frame("TalentsFrame")
PlayerSpellsFrame.TalentsFrame.GetTalentButtonByNodeID = function(self, nodeID) LIT = nodeID; return frame() end
Settings = { RegisterCanvasLayoutCategory = function() return frame() end, RegisterAddOnCategory = function() end, OpenToCategory = function() end }
"""


class UI(unittest.TestCase):
    """TalentUI.lua run against a mock of the frame API: every path draws without a Lua error."""

    @classmethod
    def setUpClass(cls):
        L.run("RESET('traits')")
        L.run(UI_STUB)
        L.run("""
          local f = assert(io.open(ROOT .. '/TalentUI.lua', 'rb')); local src = f:read('*a'); f:close()
          assert((loadstring or load)(src, '@TalentUI.lua'))('ForeverArmoury', FA)
        """)
        L.run("FA.HookTalentFrame(); FA.SetupOptions()")

    def setUp(self):
        L.run("RESET('traits'); POPUPS = {}; LIT = nil")

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

    def test_off_build_points_show_the_swap(self):
        L.run("FA.ImportText('FAT1-warrior-Arms-" + GATED + "'); TREE[3][1][4] = 2; FA.Talents.Forget(); FA.Refresh()")
        status = self.panel("status")
        self.assertIn("2 points aren't in this build|r (Shield Specialization x2).", status)
        self.assertIn("Reset your talents at a class trainer", status)
        self.assertEqual(self.panel("apply")[1], False)

    def test_import_errors_and_export(self):
        ok, err = L.eval("function(t) return FA.ImportText(t) end")("nonsense")
        self.assertFalse(ok)
        self.assertIn("isn't a build code", err)
        L.run("FA.ImportText('FAT1-warrior-Arms-0101.mage-Frost-0a'); FA.OpenImport(FA.ExportCode())")
        self.assertEqual(L.eval("ForeverArmouryImportText.text"), "FAT2-70170-warrior-Arms-0101")

    def test_the_part_switch_hides_the_panel(self):
        L.run("FA.SetPart('plan', false)")
        self.assertFalse(L.eval("ForeverArmouryTalentPanel.shown"))
        L.run("FA.SetPart('plan', true)")
        self.assertTrue(L.eval("ForeverArmouryTalentPanel.shown"))

    def test_slash_commands_run(self):
        for cmd in ["", "help", "list", "export", "import", "apply", "plan off", "plan on", "options", "debug"]:
            L.eval("function(c) SlashCmdList.FOREVERARMOURY(c) end")(cmd)


if __name__ == "__main__":
    print("Lua runtime:", L.flavour, L.eval("_VERSION"))
    unittest.main(argv=sys.argv[:1], verbosity=1)
