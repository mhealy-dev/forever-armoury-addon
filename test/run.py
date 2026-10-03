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
C_ClassTalents = { GetActiveConfigID = function() if API ~= "traits" then return nil end return 7 end }
C_Traits = {
  GetConfigInfo = function(configID) return { ID = configID, treeIDs = { 55 }, name = "Primary" } end,
  GetGroupDisplayInfoByTreeID = function(treeID)
    return { { groupID = 20, orderIndex = 2, displayName = "Fury", icon = 2 }, { groupID = 10, orderIndex = 1, displayName = "Arms", icon = 1 }, { groupID = 30, orderIndex = 3, displayName = "Protection", icon = 3 } }
  end,
  GetTreeNodes = function(treeID) local ids = {} for k in pairs(NODES) do ids[#ids + 1] = k end table.sort(ids) return ids end,
  GetNodeInfo = function(configID, nodeID)
    local n = NODES[nodeID]
    return { ID = nodeID, posX = n.posX, posY = n.posY, groupIDs = { n.tab * 10 }, entryIDs = { nodeID * 2 }, ranksPurchased = n.talent[4], maxRanks = n.talent[5], activeRank = n.talent[4] }
  end,
  GetEntryInfo = function(configID, entryID) return { definitionID = entryID / 2, maxRanks = NODES[entryID / 2].talent[5] } end,
  GetDefinitionInfo = function(defID) return DEFS[defID] end,
}
C_Spell = { GetSpellName = function(spellID) return NODES[spellID / 10].talent[1] end, GetSpellTexture = function(spellID) return spellID end }

function UnitLevel() return PLAYER.level end
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
end
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
        self.assertEqual(write("warrior", "Arms PvP", PICKS), "FAT1-warrior-Arms%20PvP-" + PICKS)
        self.assertEqual(write("mage", "", "0a"), "FAT1-mage--0a")
        for name in ["Arms PvP", "", "Mage's build, 31/0/20!", "Ünïcödé 🙂 名前", "a" * 40, "50% crit", "-leading-dashes-", "dots.in.name", "  Two   words "]:
            code = write("warrior", name, PICKS)
            self.assertRegex(code, r"^FAT1-warrior-[A-Za-z0-9%]*-[0-9a-r]+$")
            builds, notes = self.builds(code)
            self.assertEqual(builds, [("warrior", " ".join(name.split()), PICKS)], name)
            self.assertEqual(notes, [])

    def test_several_builds_and_codes_in_a_text(self):
        two = "FAT1-warrior-Arms%20PvP-" + PICKS + ".warrior-Fury-1a1a1b"
        self.assertEqual(self.builds(two)[0], [("warrior", "Arms PvP", PICKS), ("warrior", "Fury", "1a1a1b")])
        for pasted in [two, "  " + two + "\n", "`" + two + "`", "here: " + two + ". Enjoy!", "<" + two + ">", "\"" + two + "\"", "**" + two + "**"]:
            self.assertEqual(len(self.builds(pasted)[0]), 2, pasted)
        both = "FAT1-warrior-A-0a and FAT1-mage-B-1b"
        self.assertEqual(self.builds(both)[0], [("warrior", "A", "0a"), ("mage", "B", "1b")])

    def test_empty_builds(self):
        self.assertEqual(self.builds("FAT1-warrior-Empty-.warrior-Fury-1a1a1b"), ([("warrior", "Fury", "1a1a1b")], ["Left out a build with no talent points."]))
        self.assertEqual(self.read("FAT1-warrior-Empty-")[1], "That build has no talent points.")
        self.assertEqual(self.read("FAT1-warrior-A-.warrior-B-")[1], "Those builds have no talent points.")

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
        self.assertIn("newer version", say("FAT2-warrior-Arms-0a"))
        for bad in ["FAT1-", "FAT1-warrior", "FAT1-warrior-Arms", "FAT1-knight-Arms-0a", "FAT1-warrior-Arms-0a0", "FAT1-warrior-Arms-3a", "FAT1-warrior-Arms-0z", "FAT1-warrior-Arms-" + "0a" * 52]:
            self.assertRegex(say(bad), r"Build 1 .* doesn't read", bad)
        self.assertRegex(say("FAT1-warrior-Arms-0a.warrior-Fury"), r"Build 2 .* doesn't read")
        self.assertRegex(say("FAT1-warrior-Arms-0a..warrior-Fury-1a"), r"Build 2")
        for bad in ["FAT1-warrior-Ar%2-0a", "FAT1-warrior-Ar%ZZms-0a"]:
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
        self.assertEqual(L.eval("FA.ExportCode()"), "FAT1-warrior-Arms-010102.warrior-Fury-1a1a")
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


if __name__ == "__main__":
    print("Lua runtime:", L.flavour, L.eval("_VERSION"))
    unittest.main(argv=sys.argv[:1], verbosity=1)
