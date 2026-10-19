--[[ The saved builds, the character's active one, where the character is on it, and what Apply and Swap do.

     FA.db.builds[class] is a list of { id, name, picks, build }: every build imported on this account, by class, with
     the game build its picks are from (false for a FAT1- code's, from before codes carried it), and FA.char.build is
     the id of the one this character follows. A build's points name a tree and a cell; Talents.lua
     says which of the game's talents sits there, so the addon ships no talent data. ]]

local _, FA = ...

function FA.BuildsFor(cls)
  local list = FA.db.builds[cls]
  if not list then list = {}; FA.db.builds[cls] = list end
  return list
end

--[[ Keeps the builds a code gave (FA.Code.Read), each with the game build it's from, so Export gives it back as it
     came. A build with the name of one already kept for its class replaces that one's points and build and keeps its
     id, so pasting a build again after changing it on the site updates it, and the characters following it stay on
     it. Answers how many were for this character's class, and how many for others. ]]
function FA.AddBuilds(builds)
  local mine, others = 0, 0
  for _, b in ipairs(builds) do
    local list, found = FA.BuildsFor(b.cls), nil
    for _, old in ipairs(list) do if old.name == b.name then found = old end end
    local build = b.build or false
    if found then found.picks, found.build = b.picks, build
    else
      list[#list + 1] = { id = FA.db.nextId, name = b.name, picks = b.picks, build = build }
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
     first of each comes; the site reads every code in a paste. A build kept before builds were (nil) is the game's. ]]
function FA.ExportCode()
  local groups, byBuild = {}, {}
  for _, b in ipairs(FA.BuildsFor(FA.class)) do
    if b.picks ~= "" then
      local build = b.build
      if build == nil then build = FA.Code.GameBuild() end
      local key = build == false and "FAT1" or build
      if not byBuild[key] then byBuild[key] = { build = build, builds = {} }; groups[#groups + 1] = byBuild[key] end
      local list = byBuild[key].builds
      list[#list + 1] = { cls = FA.class, name = b.name, picks = b.picks }
    end
  end
  if #groups == 0 then return nil end
  local codes = {}
  for i, g in ipairs(groups) do codes[i] = FA.Code.Write(g.builds, g.build) end
  return table.concat(codes, "\n")
end

--[[ Where a spec is on a build (the active spec without a view). Answers a table, or nil and why:
       next     the first point of the build not taken: { n, talent, rank, level }, talent being Talents.At's, rank the
                rank that point makes and level the level the build takes it at; nil once every point is taken
       left     every point not taken, in the build's order, each as next is
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
  local planned, byKey, taken, left = {}, {}, 0, {}
  local first = FA.FirstLevel()
  for n, p in ipairs(points) do
    local t = FA.Talents.At(p.tab, p.cell, view)
    if not t then return nil, "A talent in this build isn't in your talent trees. The site may be newer than this addon." end
    local key = p.tab * 100 + p.cell
    planned[key] = (planned[key] or 0) + 1
    byKey[key] = t
    if planned[key] <= t.rank then taken = taken + 1
    else left[#left + 1] = { n = n, talent = t, rank = planned[key], level = n + first - 1 } end
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
  return { next = left[1], left = left, extra = extra, points = #points, spent = spent, off = spent - taken,
    due = math.max(0, math.min(#points, level - first + 1)) }
end

--[[ What Apply would spend now: the build's points not taken, in order, as many as the character has unspent.
     Answers the list of talents and the progress, or nil and why. ]]
function FA.PlanApply(build)
  if FA.Talents.HasStaged() then return nil, FA.Talents.STAGED end
  local p, why = FA.Progress(build)
  if not p then return nil, why end
  if p.off > 0 then return nil, "You have " .. p.off .. (p.off == 1 and " point" or " points") .. " this build doesn't, so Apply can't follow it." end
  if not p.next then return nil, "Every point of this build is spent." end
  local unspent = FA.Talents.Unspent()
  if unspent == nil then unspent = math.max(0, p.due - p.spent) end
  if unspent <= 0 then
    return nil, p.next.level > (UnitLevel("player") or 1) and ("Your next point comes at level " .. p.next.level .. ".") or "You have no points to spend."
  end
  local list = {}
  for i = 1, math.min(unspent, #p.left) do list[i] = p.left[i].talent end
  return list, nil, p
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

--[[ Spends the points PlanApply chose, all or none. Answers true and what was spent, or false and why. ]]
function FA.Apply(build)
  local ok, why = FA.Talents.CanChange()
  if not ok then return false, why end
  local list
  list, why = FA.PlanApply(build)
  if not list then return false, why end
  ok, why = FA.Talents.Learn(list)
  if not ok then return false, why end
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
