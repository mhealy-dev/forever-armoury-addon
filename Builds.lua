--[[ The saved builds, the character's active one, where the character is on it, and what Apply and Swap do.

     FA.db.builds[class] is a list of { id, name, picks, build, talented }: every build imported on this account, by
     class, with the game build its picks are from (false for a FAT1- code's, from before codes carried it) and the
     build's own rank of the Legacy perk Talented (0 to 5; nil for a build kept before codes carried it, which is
     written as 0), and FA.char.build is the id of the one this character follows. A build's points name a tree and a cell; Talents.lua
     says which of the game's talents sits there, so the addon ships no talent data. ]]

local _, FA = ...

function FA.BuildsFor(cls)
  local list = FA.db.builds[cls]
  if not list then list = {}; FA.db.builds[cls] = list end
  return list
end

--[[ The saved builds as they load: a list per class of tables with picks that are text, which is what the rest of the
     addon counts on (picks that don't read are answered where they are used, and kept, since a newer addon may read
     what this one doesn't). One that isn't a table, or has no picks, is dropped; a name that isn't text is emptied, and
     an id that isn't a number or is another build's is given a new one. nextId is kept past every id, and the
     character's followed build is cleared when it is gone. Answers how many were dropped and how many repaired. ]]
function FA.RepairBuilds()
  local dropped, repaired, seen = 0, 0, {}
  local builds = FA.db.builds
  for cls, list in pairs(builds) do
    if type(cls) ~= "string" or type(list) ~= "table" then
      builds[cls] = nil
      dropped = dropped + 1
    else
      local kept = {}
      for _, b in ipairs(list) do
        if type(b) ~= "table" or type(b.picks) ~= "string" or b.picks == "" then
          dropped = dropped + 1
        else
          local fixed = false
          if type(b.name) ~= "string" then b.name = ""; fixed = true end
          if type(b.id) ~= "number" or seen[b.id] then b.id = nil; fixed = true else seen[b.id] = true end
          if b.build ~= nil and b.build ~= false and type(b.build) ~= "number" then b.build = nil; fixed = true end
          if b.talented ~= nil and not (type(b.talented) == "number" and b.talented % 1 == 0 and b.talented >= 0 and b.talented <= 5) then b.talented = nil; fixed = true end
          if fixed then repaired = repaired + 1 end
          kept[#kept + 1] = b
        end
      end
      builds[cls] = kept
    end
  end
  for _, list in pairs(builds) do
    for _, b in ipairs(list) do
      if not b.id then b.id = FA.db.nextId end
      FA.db.nextId = math.max(FA.db.nextId, b.id + 1)
    end
  end
  if FA.char.build and not FA.FindBuild(FA.class, FA.char.build) then FA.char.build = nil end
  return dropped, repaired
end

--[[ Keeps the builds a code gave (FA.Code.Read), each with the game build it's from and its Talented rank, so Export
     gives it back as it came (a FAT1- or FAT2- code's builds have rank 0). A build with the name and points of one
     already kept for its class updates that one's game build and rank and keeps its id, so pasting a build again, as the site has it now, leaves the characters following it on it; a build with
     the same name and other points is another build (two Arms, two unnamed). Answers how many were for this
     character's class, and how many for others. ]]
function FA.AddBuilds(builds)
  local mine, others = 0, 0
  for _, b in ipairs(builds) do
    local list, found = FA.BuildsFor(b.cls), nil
    for _, old in ipairs(list) do if old.name == b.name and old.picks == b.picks then found = old end end
    local build = b.build or false
    if found then found.build, found.talented = build, b.talented
    else
      list[#list + 1] = { id = FA.db.nextId, name = b.name, picks = b.picks, build = build, talented = b.talented }
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

--[[ The code for every build of this character's class with points, for the site's Import box; nil when there are none.
     A code carries one game build, so builds from different ones are a code each, a line each, in the order the
     first of each comes; the site reads every code in a paste. A build kept before builds were (nil) is the game's.
     Every code is a FAT3- one, a FAT1- build's with game build 0; a build with no rank is written with 0. ]]
function FA.ExportCode()
  local groups, byBuild = {}, {}
  for _, b in ipairs(FA.BuildsFor(FA.class)) do
    if b.picks ~= "" then
      local build = b.build
      if build == nil then build = FA.Code.GameBuild() end
      local key = build == false and "none" or build
      if not byBuild[key] then byBuild[key] = { build = build, builds = {} }; groups[#groups + 1] = byBuild[key] end
      local list = byBuild[key].builds
      list[#list + 1] = { cls = FA.class, name = b.name, picks = b.picks, talented = b.talented }
    end
  end
  if #groups == 0 then return nil end
  local codes = {}
  for i, g in ipairs(groups) do codes[i] = FA.Code.Write(g.builds, g.build) end
  return table.concat(codes, "\n")
end

--[[ How many points Apply would spend after the trainer's reset: all the points the character has, as the game counts
     them (spent and unspent, which a reset makes all unspent), as far as the build goes. Answers nil for a build that
     doesn't read. When the game won't say how many points there are, the character's level says. ]]
function FA.PointsAfterReset(build)
  local points = FA.Code.Points(build.picks)
  if not points then return nil end
  local unspent = FA.Talents.Unspent()
  local total = unspent and FA.Talents.Ready() and (FA.Talents.Spent() + unspent) or math.max(0, (UnitLevel("player") or 1) - FA.FirstLevel(build) + 1)
  return math.min(#points, total)
end

--[[ Where a pick is, as words: "Arms row 3, column 2" (a tree's name from the game, else its number). ]]
function FA.Where(tab, cell)
  local trees = FA.Talents.Trees()
  local tree = trees and trees[tab] and trees[tab].name
  return (tree or ("tree " .. tab)) .. " row " .. (math.floor(cell / 4) + 1) .. ", column " .. (cell % 4 + 1)
end

--[[ The picks of a build that no talent of the trees sits under, as a sentence ("5 points on 2 talents of this build aren't in
     your trees: Arms row 3, column 2; Fury row 1, column 1"): a talent with several ranks in the build is one cell, named
     once, at most three named; nil when there are none. ]]
function FA.UnplacedText(unplaced)
  if not unplaced or #unplaced == 0 then return nil end
  local cells, seen = {}, {}
  for _, u in ipairs(unplaced) do
    local key = u.tab * 100 + u.cell
    if not seen[key] then seen[key] = true; cells[#cells + 1] = FA.Where(u.tab, u.cell) end
  end
  local talents, points = #cells, #unplaced
  local shown = {}
  for i = 1, math.min(3, talents) do shown[i] = cells[i] end
  if talents > 3 then shown[#shown + 1] = "and " .. (talents - 3) .. " more" end
  return (points == talents and "" or (points .. " points on ")) .. talents ..
    (talents == 1 and " talent of this build isn't" or " talents of this build aren't") .. " in your trees: " .. table.concat(shown, "; ")
end

--[[ Where a spec is on a build (the active spec without a view). Answers a table, or nil and why:
       next     the first point of the build not taken: { n, talent, rank, level }, talent being Talents.At's, rank the
                rank that point makes and level the level the build takes it at; nil once every point is taken
       left     every point not taken, in the build's order, each as next is
       taken    every point of the build the spec has, in the build's order, each as next is (the strip's past)
       unplaced the picks no talent of the view sits under (the site may be newer than this addon, or the game's nodes
                didn't sort): { { n, tab, cell, level }, ... }; the build goes on without them
       blocked  the first of those, which Apply stops at; nil when there are none
       extra    the talents with more ranks than the build gives them: { { talent, over }, ... }
       points   how many points the build has
       spent    how many points the spec has spent
       off      how many of those the build doesn't have (so the build can't be followed without a reset)
       due      how many of the build's points the character's level allows ]]
function FA.Progress(build, view)
  local points = FA.Code.Points(build.picks)
  if not points then return nil, "That build's code doesn't read." end
  view = view or FA.Talents.View()
  if not view then return nil, "The game hasn't given its talents yet. Open the talent window and try again." end
  local planned, taken, left, had, unplaced = {}, 0, {}, {}, {}
  local first = FA.FirstLevel(build)
  for n, p in ipairs(points) do
    local t = FA.Talents.At(p.tab, p.cell, view)
    if not t then
      unplaced[#unplaced + 1] = { n = n, tab = p.tab, cell = p.cell, level = n + first - 1 }
    else
      local key = p.tab * 100 + p.cell
      planned[key] = (planned[key] or 0) + 1
      local point = { n = n, talent = t, rank = planned[key], level = n + first - 1 }
      if planned[key] <= t.rank then taken = taken + 1; had[#had + 1] = point
      else left[#left + 1] = point end
    end
  end
  local extra = {}
  for tab, cells in pairs(view.cells) do
    for cell, t in pairs(cells) do
      local over = t.rank - (planned[tab * 100 + cell] or 0)
      if over > 0 then extra[#extra + 1] = { talent = t, over = over } end
    end
  end
  table.sort(extra, function(a, b) return a.talent.tab * 100 + a.talent.cell < b.talent.tab * 100 + b.talent.cell end)
  local spent = FA.Talents.Spent(view)
  local level = UnitLevel("player") or 1
  return { next = left[1], left = left, taken = had, unplaced = unplaced, blocked = unplaced[1], extra = extra, points = #points, spent = spent, off = spent - taken,
    due = math.max(0, math.min(#points, level - first + 1)) }
end

--[[ What the strip beside the talent window shows of a build's progress (Progress's answer): the last `past` points
     taken, the next, then up to `coming` more, each as { kind = "taken" | "next" | "coming", n, talent, rank, level }; the
     next also says now, whether its point can be spent (its level has come, and the spec has no point off the build).
     A pick no talent sits under is an entry of kind "unplaced" in its place in the order, with no talent and its tab and
     cell. Answers the list and how many points follow it. A build that's off its order shows the points Progress could place. ]]
function FA.StripPlan(p, past, coming)
  local out = {}
  local function add(kind, point)
    local e = { kind = kind, n = point.n, talent = point.talent, rank = point.rank, level = point.level, tab = point.tab, cell = point.cell }
    out[#out + 1] = e
    return e
  end
  --[[ the points before the next one (taken, and picks off the trees) and those after it, each in the build's order ]]
  local nextN = p.next and p.next.n or math.huge
  local before, after = {}, {}
  for _, point in ipairs(p.taken) do before[#before + 1] = { kind = "taken", point = point } end
  for _, point in ipairs(p.unplaced or {}) do
    local list = point.n < nextN and before or after
    list[#list + 1] = { kind = "unplaced", point = point }
  end
  for i = 2, #p.left do after[#after + 1] = { kind = "coming", point = p.left[i] } end
  local function byN(a, b) return a.point.n < b.point.n end
  table.sort(before, byN)
  table.sort(after, byN)
  for i = math.max(1, #before - past + 1), #before do add(before[i].kind, before[i].point) end
  if p.next then add("next", p.next).now = p.next.n <= p.due and p.off == 0 end
  for i = 1, math.min(#after, coming) do add(after[i].kind, after[i].point) end
  return out, math.max(0, #after - coming)
end

--[[ What Apply would spend now: the build's points not taken, in order, as many as the character has unspent (and no
     more than limit, when one is given: the strip's click takes one). A pick no talent of the trees sits under stops it:
     the points before that pick are spent, none after. Answers the list of talents, nil and the progress, and that
     pick when it cut the list short; or nil and why. ]]
function FA.PlanApply(build, limit)
  if FA.Talents.HasStaged() then return nil, FA.Talents.STAGED end
  local p, why = FA.Progress(build)
  if not p then return nil, why end
  if p.off > 0 then return nil, "You have " .. p.off .. (p.off == 1 and " point" or " points") .. " this build doesn't, so Apply can't follow it." end
  if not p.next then
    return nil, p.blocked and "Every point of this build that your trees have is spent." or "Every point of this build is spent."
  end
  local unspent = FA.Talents.Unspent()
  if unspent == nil then unspent = math.max(0, p.due - p.spent) end
  if unspent <= 0 then
    return nil, p.next.level > (UnitLevel("player") or 1) and ("Your next point comes at level " .. p.next.level .. ".") or "You have no points to spend."
  end
  local list, wanted = {}, math.min(unspent, #p.left, limit or math.huge)
  for i = 1, wanted do
    if p.blocked and p.left[i].n > p.blocked.n then break end
    list[i] = p.left[i].talent
  end
  if #list == 0 then
    return nil, "Apply stops at " .. FA.Where(p.blocked.tab, p.blocked.cell) .. ", a talent your trees don't have, so there is nothing to spend before it."
  end
  return list, nil, p, #list < wanted and p.blocked or nil
end

--[[ The talents of a list as a short line: "Deflection x3, Cruelty", in the order they come. ]]
function FA.Summary(list, limit)
  local order, count = {}, {}
  for _, t in ipairs(list) do
    local key = t.tab * 100 + t.cell
    if not count[key] then order[#order + 1] = t; count[key] = 0 end
    count[key] = count[key] + 1
  end
  local parts = {}
  for i, t in ipairs(order) do
    if limit and i > limit then parts[#parts + 1] = "and " .. (#order - limit) .. " more"; break end
    parts[#parts + 1] = (t.name or "?") .. (count[t.tab * 100 + t.cell] > 1 and (" x" .. count[t.tab * 100 + t.cell]) or "")
  end
  return table.concat(parts, ", ")
end

--[[ Spends the points PlanApply chose (the first `limit` of them, when one is given), all or none. Answers true and what
     was spent (and, when a pick off the trees cut it short, that pick as a third answer), or false and why. ]]
function FA.Apply(build, limit)
  local ok, why = FA.Talents.CanChange()
  if not ok then return false, why end
  local plan = { FA.PlanApply(build, limit) }   -- list, why, progress, the pick that stopped it
  local list, stopped = plan[1], plan[4]
  if not list then return false, plan[2] end
  ok, why = FA.Talents.Learn(list)
  if not ok then return false, why end
  if stopped then return true, FA.Summary(list), stopped end
  return true, FA.Summary(list)
end

--[[ What it takes to follow a build the active spec's points don't fit (Swap). Answers a sentence, or nil when the
     points fit and Apply continues it. ]]
function FA.SwapAdvice(build)
  local p = FA.Progress(build)
  if not p or p.off <= 0 then return nil end
  local other, n = FA.Talents.OtherSpec()
  if other then
    local q = FA.Progress(build, other)
    if q and q.off <= 0 then
      return "Your " .. FA.Talents.SpecName(n) .. " spec fits this build: activate it in the talent window, then Apply."
    end
  end
  return "Reset your talents at a class trainer, then Apply spends every point in order."
end
