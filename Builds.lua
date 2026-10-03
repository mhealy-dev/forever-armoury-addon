--[[ The saved builds, the character's active one, and where the character is on it.

     FA.db.builds[class] is a list of { id, name, picks }: every build imported on this account, by class, and
     FA.char.build is the id of the one this character follows. A build's points name a tree and a cell; Talents.lua
     says which of the game's talents sits there, so the addon ships no talent data. ]]

local _, FA = ...

function FA.BuildsFor(cls)
  local list = FA.db.builds[cls]
  if not list then list = {}; FA.db.builds[cls] = list end
  return list
end

--[[ Keeps the builds a code gave (FA.Code.Read). A build with the name of one already kept for its class replaces
     that one's points and keeps its id, so pasting a build again after changing it on the site updates it, and the
     characters following it stay on it. Answers how many were for this character's class, and how many for others. ]]
function FA.AddBuilds(builds)
  local mine, others = 0, 0
  for _, b in ipairs(builds) do
    local list, found = FA.BuildsFor(b.cls), nil
    for _, old in ipairs(list) do if old.name == b.name then found = old end end
    if found then found.picks = b.picks
    else
      list[#list + 1] = { id = FA.db.nextId, name = b.name, picks = b.picks }
      FA.db.nextId = FA.db.nextId + 1
    end
    if b.cls == FA.class then mine = mine + 1 else others = others + 1 end
  end
  return mine, others
end

function FA.FindBuild(cls, id)
  for i, b in ipairs(FA.BuildsFor(cls)) do if b.id == id then return b, i end end
  return nil
end

function FA.ForgetBuild(cls, id)
  local b, i = FA.FindBuild(cls, id)
  if not b then return false end
  table.remove(FA.BuildsFor(cls), i)
  if FA.char.build == id then FA.char.build = nil end
  return true
end

--[[ The build this character follows, or nil. ]]
function FA.ActiveBuild()
  return FA.char.build and FA.FindBuild(FA.class, FA.char.build) or nil
end
function FA.SetActive(id) FA.char.build = id end

--[[ The code for every build of this character's class with points, for the site's Import box; nil when there are none. ]]
function FA.ExportCode()
  local out = {}
  for _, b in ipairs(FA.BuildsFor(FA.class)) do
    if b.picks ~= "" then out[#out + 1] = { cls = FA.class, name = b.name, picks = b.picks } end
  end
  if #out == 0 then return nil end
  return FA.Code.Write(out)
end

--[[ Where the character is on a build. Answers a table, or nil and why:
       next     the first point of the build the character hasn't taken: { n, talent, rank, level }, talent being
                Talents.At's, rank the rank that point makes and level the level the build takes it at; nil once
                every point is taken
       points   how many points the build has
       spent    how many points the character has spent
       off      how many of those the build doesn't have (so the build can't be followed without a reset)
       due      how many of the build's points the character's level allows ]]
function FA.Progress(build)
  local points = FA.Code.Points(build.picks)
  if not points then return nil, "That build's code doesn't read." end
  if not FA.Talents.Ready() then return nil, "The game hasn't given its talents yet. Open the talent window and try again." end
  local planned, taken, nextPick = {}, 0, nil
  for n, p in ipairs(points) do
    local t = FA.Talents.At(p.tab, p.cell)
    if not t then return nil, "A talent in this build isn't in your talent trees. The site may be newer than this addon." end
    local key = p.tab * 100 + p.cell
    planned[key] = (planned[key] or 0) + 1
    if planned[key] <= t.rank then taken = taken + 1
    elseif not nextPick then nextPick = { n = n, talent = t, rank = planned[key], level = n + FA.FIRST_LEVEL - 1 } end
  end
  local spent = FA.Talents.Spent()
  local level = UnitLevel("player") or 1
  return { next = nextPick, points = #points, spent = spent, off = spent - taken, due = math.max(0, math.min(#points, level - FA.FIRST_LEVEL + 1)) }
end
