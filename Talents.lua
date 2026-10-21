--[[ The game's talents, under the names the rest of the addon uses: three trees of cells, each cell a talent with a
     rank, the talent window to sit beside, and spending points.

     The Forever client (game type "camelot", 1.60.x) keeps its talents in the trait system that retail's talent trees
     use: one trait tree for the class, its three talent trees as groups of nodes, each node placed by posX and posY.
     The talent window is PlayerSpellsFrame.TalentsFrame (Blizzard_PlayerSpells, loaded on demand). A node's row and
     column come from its position, so the site's cell (tier - 1) * 4 + (column - 1) names the node without any talent
     data here. Points are staged with C_Traits.PurchaseRank and applied with C_ClassTalents.CommitConfig, as the
     window's own Apply button does; C_Traits.RollbackConfig drops what's staged. Each of the two specs (dual spec) has
     its own config. The old API (GetTalentInfo by tab and index, LearnTalent, TalentFrame) isn't in the Forever client
     at all, but a client that has it gets the same answers from it, so the rest of the addon has one path. A trait
     function the client lacks is said in chat once, by name, and answers nil, so the rest carries on without a Lua error.

     A view is one spec's talents: { trees = { { name, icon }, ... }, cells = { [tab] = { [cell] = talent } } }, a
     talent being { tab, cell, row, col, name, icon, rank, max, node }; rank is what's spent, staged points included, and
     node names it to the game (a node id, or a talent index). From the trait system a talent also has x and y, its
     node's position and spell, its definition's spell id (the strip's tooltip shows it), and the view has grid, each tree's { colStep, rowStep, originX, topY } it was sorted by, and
     dropped, each tree's nodes that didn't sort into a cell of their own: { { talent, why }, ... }. A node of the trait system
     is read whatever its maxRanks (the Forever client gives 0 for many): max is maxRanks, else totalMaxRanks, else its
     entry's, else nil; a node's tree is whichever of its groupIDs (the live client gives 3 to 7) is one of the trees' groups,
     and a node with none goes to a tree by its x. The view also has
     skipped, the nodes not read ({ info, skip } for a node the window skips too) and byPosition, each tree's count of
     nodes placed by x.

     FA.Talents.View([configID])     a spec's view (the active one's without a config), or nil before the game answers
     FA.Talents.Ready()              whether the active spec's view is in
     FA.Talents.Trees()              the active view's trees
     FA.Talents.At(tab, cell[, view]) a talent, or nil
     FA.Talents.Spent([view])        points spent in every tree
     FA.Talents.Unspent()            points the character has to spend, or nil when the game won't say
     FA.Talents.OtherSpec()          the inactive spec's view and its number (1 or 2), or nil without dual spec
     FA.Talents.SpecName(n)          a spec's name, "Primary" or "Secondary"
     FA.Talents.CanChange()          true, or false and why talents can't change now (combat)
     FA.Talents.Learn(list)          spends a rank in each talent of a list, in order, all or none: true, or false and why
     FA.Talents.CommitFailed(cfg)    CONFIG_COMMIT_FAILED: rolls back the addon's commit, true when it was the addon's
     FA.Talents.Committed(cfg)       TRAIT_CONFIG_UPDATED: the addon's commit went through
     FA.Talents.Applying()           whether the addon's commit is casting (its points staged, the game not yet answered)
     FA.Talents.Game(path, ...)      calls a function of the game by name ("C_Traits.GetNodeInfo"): nil, and one line in chat, if it has none
     FA.Talents.Forget()             drop what's cached: the next call asks the game again (called when points change)
     FA.Talents.Frame() / Window()   the talent window's frame and the window the panel sits on, once loaded
     FA.Talents.Button(t)            the window's button for a talent, or nil (the panel lights it)
     FA.Talents.Icon(t)              a talent's icon, or a question mark when the game has none yet
     FA.Talents.Toggle()             open or close the talent window
     FA.Talents.Loaded(name)         whether an ADDON_LOADED name is the talent UI's
     FA.Talents.Dump()               every talent by tree, row and column, with the positions and grid it came from and
                                     the nodes left out, as lines of text (/fa debug)
     FA.Talents.DumpNodes()          every node of the active config raw, with the tree it went to and why (/fa debug nodes) ]]

local _, FA = ...
local Talents = {}
FA.Talents = Talents

local views = {}   -- configID (or "legacy") -> view
local told = 0     -- how many talents that didn't sort chat was last told of: it's told again only when that changes

local missing = {}   -- the game functions chat has been told are missing, by name
--[[ Calls a function of the game's trait system by name ("C_Traits.GetNodeInfo") and answers what it does. One the
     client doesn't have answers nil, with one line in chat naming it (once), not a Lua error that stops the rest. ]]
local function game(path, ...)
  local ns, name = path:match("^(.-)%.(.+)$")
  local fn = _G[ns] and _G[ns][name]
  if type(fn) ~= "function" then
    if not missing[path] then
      missing[path] = true
      FA.Print("This client has no " .. path .. ", so the addon can't use it.")
    end
    return nil
  end
  return fn(...)
end
Talents.Game = game   -- the Legacy part (Legacy.lua) calls the same trait functions through it

local function hasTraits() return C_Traits and C_ClassTalents and C_ClassTalents.GetActiveConfigID and true or false end
--[[ The active spec's config. GetActiveConfigID can be nil early on, and the game's own window then takes the active
     spec group's combat config, so this does too. ]]
local function activeConfig()
  if not hasTraits() then return nil end
  local configID = game("C_ClassTalents.GetActiveConfigID")
  if not configID and C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetActiveSpecGroup then
    configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(C_SpecializationInfo.GetActiveSpecGroup())
  end
  return configID
end
local function treeOf(configID)
  local info = game("C_Traits.GetConfigInfo", configID)
  return info and info.treeIDs and info.treeIDs[1]
end

local function round(x) return math.floor(x + 0.5) end
local function num(x) return x == math.floor(x) and string.format("%d", x) or string.format("%.1f", x) end
--[[ The smallest gap between the distinct values in a list, the pitch of the grid they sit on (nil with fewer than two
     values to measure it by), then the first value and the last. ]]
local function pitch(values)
  local distinct, seen = {}, {}
  for _, v in ipairs(values) do if not seen[v] then seen[v] = true; distinct[#distinct + 1] = v end end
  table.sort(distinct)
  local step
  for i = 2, #distinct do local d = distinct[i] - distinct[i - 1]; if d > 0 and (not step or d < step) then step = d end end
  return step, distinct[1], distinct[#distinct]
end

--[[ Each tree's grid, from its own nodes: the pitch of its columns and rows, its leftmost and rightmost talent, and its
     topmost, which is tier 1, since every tree starts there. Each tree has its own, so a tree drawn on another spacing,
     or a node off its tree's grid, only touches that tree. A tree with one column or one row has no pitch of its own
     and takes that of the tree with the most talents that has one (borrowed, for /fa debug). ]]
local function grids(nodes, count)
  local xs, ys, out = {}, {}, {}
  for t = 1, count do xs[t], ys[t] = {}, {} end
  for _, n in ipairs(nodes) do
    xs[n.tab][#xs[n.tab] + 1] = n.info.posX
    ys[n.tab][#ys[n.tab] + 1] = n.info.posY
  end
  for t = 1, count do
    local g = { size = #xs[t] }
    g.colStep, g.minX, g.maxX = pitch(xs[t])
    g.rowStep, g.topY = pitch(ys[t])
    out[t] = g
  end
  for _, k in ipairs({ { "colStep", "columns" }, { "rowStep", "rows" } }) do
    local key, said, from = k[1], k[2], nil
    for t = 1, count do if out[t][key] and (not from or out[t].size > from.size) then from = out[t] end end
    for t = 1, count do
      if not out[t][key] then out[t][key] = from and from[key] or 1; out[t].borrowed = (out[t].borrowed and out[t].borrowed .. " and " or "") .. said end
    end
  end
  return out
end

--[[ Where each tree's first column is, as grid's originX, and what said so, as grid's origin. A tree with talents in
     every column (or past them, with a stray node) starts at its leftmost one. A tree that leaves its first column
     empty would start a column late that way, so when two trees are full their spacing says where every tree starts;
     a lone short tree falls back to its leftmost talent. ]]
local function columnOrigins(grid)
  local full = {}
  for t, g in ipairs(grid) do
    if g.minX and round((g.maxX - g.minX) / g.colStep) >= 3 then full[#full + 1] = t; g.originX = g.minX; g.origin = "a full tree's leftmost talent" end
  end
  for t, g in ipairs(grid) do
    if g.minX and not g.originX then
      if #full >= 2 then
        local a, b = full[1], full[2]
        g.originX = grid[a].minX + (t - a) * (grid[b].minX - grid[a].minX) / (b - a)
        g.origin = "from the full trees' spacing"
      else
        g.originX = g.minX
        g.origin = "its leftmost talent"
      end
    end
  end
end

local function nodeNameAndIcon(configID, node)
  local entryID = node.entryIDs and node.entryIDs[1]
  local entry = entryID and game("C_Traits.GetEntryInfo", configID, entryID)
  local def = entry and entry.definitionID and game("C_Traits.GetDefinitionInfo", entry.definitionID)
  if not def then return nil, nil end
  local name = def.overrideName or (def.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(def.spellID))
  local icon = def.overrideIcon or (def.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(def.spellID))
  return name, icon, def.spellID
end

--[[ A talent's icon for the strip: the game's, or a question mark while the game has none yet. ]]
Talents.UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
function Talents.Icon(t) return t and t.icon or Talents.UNKNOWN_ICON end

--[[ ---- the trait system (the Forever client) ---- ]]
--[[ A talent's rank count. The Forever client's nodes don't all give maxRanks (some answer 0), so the count is maxRanks
     when it's above 0, else totalMaxRanks, else the first entry's maxRanks; nil when none says (the cell is drawn with
     a "?" where the count goes). ]]
local function maxRankOf(configID, node)
  if (node.maxRanks or 0) > 0 then return node.maxRanks end
  if (node.totalMaxRanks or 0) > 0 then return node.totalMaxRanks end
  local entryID = node.entryIDs and node.entryIDs[1]
  local entry = entryID and game("C_Traits.GetEntryInfo", configID, entryID)
  if entry and (entry.maxRanks or 0) > 0 then return entry.maxRanks end
  return nil
end

--[[ A tree for each node recs still has no tree for, by where it sits. The trees are thousands of x apart and a tree's
     columns 600, so the nodes that do have a group say each tree's x range, and a node without one goes to the tree
     whose range it falls in, else the nearest. When no node has a group, the x values are split into one run per tree
     at the widest gaps, left to right in the trees' order. Each rec says why it went where. ]]
local function placeByPosition(recs, count)
  local lo, hi = {}, {}
  for _, r in ipairs(recs) do
    if r.tab then
      local x = r.info.posX
      lo[r.tab], hi[r.tab] = math.min(lo[r.tab] or x, x), math.max(hi[r.tab] or x, x)
    end
  end
  local cuts
  if next(lo) == nil then
    local seen, xs = {}, {}
    for _, r in ipairs(recs) do
      if not r.skip and not seen[r.info.posX] then seen[r.info.posX] = true; xs[#xs + 1] = r.info.posX end
    end
    table.sort(xs)
    local gaps = {}
    for i = 2, #xs do gaps[#gaps + 1] = { size = xs[i] - xs[i - 1], at = xs[i] } end
    table.sort(gaps, function(a, b) return a.size > b.size end)
    cuts = {}
    for i = 1, math.min(count - 1, #gaps) do cuts[#cuts + 1] = gaps[i].at end
  end
  for _, r in ipairs(recs) do
    if not r.tab and not r.skip then
      local x = r.info.posX
      local groups = r.info.groupIDs and #r.info.groupIDs or 0
      local lack = (groups > 0 and (groups == 1 and "its group is not one of the tree's" or "none of its " .. groups .. " groups is one of the tree's") or "no group")
      if cuts then
        r.tab = 1
        for _, at in ipairs(cuts) do if x >= at then r.tab = r.tab + 1 end end
        r.why = lack .. ", and no node has one: split by the widest gaps in x"
      else
        local best, away
        for t = 1, count do
          if lo[t] then
            local d = x < lo[t] and lo[t] - x or x > hi[t] and x - hi[t] or 0
            if not away or d < away then best, away = t, d end
          end
        end
        r.tab = best
        r.why = lack .. ", so by x: " .. (away == 0 and "within" or "nearest to") .. " " .. num(lo[best]) .. " to " .. num(hi[best])
      end
      r.byPosition = true
    end
  end
end

--[[ Every node of a config's tree, as recs { info, tab, why, skip, byPosition }: tab is the display group (tree) it went
     to and why, skip being the reason a node is left unread. A node is left out only when the window would skip it
     (isVisible is false) or has no position to sort by. Answers the groups in order and the recs, or nil. ]]
local function readNodes(configID)
  local treeID = treeOf(configID)
  if not treeID then return nil end
  local groups = game("C_Traits.GetGroupDisplayInfoByTreeID", treeID)
  if not groups or #groups == 0 then return nil end
  table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
  local tabOf = {}
  for i, g in ipairs(groups) do tabOf[g.groupID] = i end
  local recs = {}
  for _, nodeID in ipairs(game("C_Traits.GetTreeNodes", treeID) or {}) do
    local n = game("C_Traits.GetNodeInfo", configID, nodeID)
    local rec = { info = n or { ID = nodeID } }
    if not n then rec.skip = "the game gave no information on it"
    elseif n.isVisible == false then rec.skip = "isVisible is false, which the window skips too"
    elseif not (n.posX and n.posY) then rec.skip = "no position"
    else
      --[[ the live client gives a node 3 to 7 groups, the tree's talent group being any of them: the one that is a display group
           names the tree; if the groups of two trees are among them, the first is taken and /fa debug nodes says so ]]
      local found, other = nil, nil
      for _, g in ipairs(n.groupIDs or {}) do
        if tabOf[g] then
          if not found then found = g elseif tabOf[g] ~= tabOf[found] then other = other or g end
        end
      end
      if found then
        rec.tab, rec.why = tabOf[found], "group " .. found .. (other and (", the first of its groups that is a tree's; group " .. other .. " is another tree's too") or "")
      end
    end
    recs[#recs + 1] = rec
  end
  placeByPosition(recs, #groups)
  return groups, recs
end

local function readTraits(configID)
  local groups, recs = readNodes(configID)
  if not groups then return nil end
  local out, nodes = { trees = {}, cells = {}, configID = configID, skipped = {}, byPosition = {} }, {}
  for i, g in ipairs(groups) do out.trees[i] = { name = g.displayName, icon = g.icon }; out.cells[i] = {}; out.byPosition[i] = 0 end
  for _, r in ipairs(recs) do
    if r.tab then
      nodes[#nodes + 1] = { tab = r.tab, info = r.info }
      if r.byPosition then out.byPosition[r.tab] = out.byPosition[r.tab] + 1 end
    else
      out.skipped[#out.skipped + 1] = r
    end
  end
  if #nodes == 0 then return nil end
  --[[ each tree's rows and columns from its own grid; a node that lands outside the four columns and seven rows a
       code's cell can name, or on a cell another node has, is left out and kept in dropped, to say so ]]
  local grid = grids(nodes, #out.trees)
  columnOrigins(grid)
  out.grid, out.dropped = grid, {}
  local left = 0
  for t = 1, #out.trees do out.dropped[t] = {} end
  for _, n in ipairs(nodes) do
    local g, x, y = grid[n.tab], n.info.posX, n.info.posY
    local col, row = round((x - g.originX) / g.colStep) + 1, round((y - g.topY) / g.rowStep) + 1
    local cell = (row - 1) * 4 + (col - 1)
    local name, icon, spell = nodeNameAndIcon(configID, n.info)
    local talent = { tab = n.tab, cell = cell, row = row, col = col, name = name, icon = icon, rank = n.info.ranksPurchased or 0,
      max = maxRankOf(configID, n.info), node = n.info.ID, x = x, y = y, spell = spell }
    local why, there = nil, out.cells[n.tab][cell]
    if col < 1 or col > 4 then why = "column " .. col .. ", outside the four"
    elseif row > 7 then why = "row " .. row .. ", below the seventh"
    elseif there then why = "on " .. row .. "," .. col .. " with " .. (there.name or "?") .. " (node " .. tostring(there.node) .. ")" end
    if why then
      out.dropped[n.tab][#out.dropped[n.tab] + 1] = { talent = talent, why = why }
      left = left + 1
    else
      out.cells[n.tab][cell] = talent
    end
  end
  if left > 0 and left ~= told then
    told = left
    FA.Print(left .. (left == 1 and " talent" or " talents") .. " didn't sort into the trees, so builds can't use " ..
      (left == 1 and "it" or "them") .. ". /fa debug lists " .. (left == 1 and "it" or "them") .. ".")
  end
  return out
end

--[[ ---- the old API, for a client that has it ---- ]]
local function readLegacy()
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return nil end
  local tabs = GetNumTalentTabs()
  if not tabs or tabs == 0 then return nil end
  local out = { trees = {}, cells = {} }
  for t = 1, tabs do
    local a, b = GetTalentTabInfo(t)
    out.trees[t] = { name = type(a) == "string" and a or b, icon = type(a) == "string" and b or nil }
    out.cells[t] = {}
    for i = 1, GetNumTalents(t) do
      local name, icon, tier, column, rank, max = GetTalentInfo(t, i)
      if tier and column then
        local cell = (tier - 1) * 4 + (column - 1)
        out.cells[t][cell] = { tab = t, cell = cell, row = tier, col = column, name = name, icon = icon, rank = rank or 0, max = max, node = i }
      end
    end
  end
  return out
end

function Talents.View(configID)
  configID = configID or activeConfig()
  if configID then
    if not views[configID] then views[configID] = readTraits(configID) end
    return views[configID]
  end
  if not views.legacy then views.legacy = readLegacy() end
  return views.legacy
end

function Talents.Ready() return Talents.View() ~= nil end
function Talents.Trees() local v = Talents.View(); return v and v.trees end
function Talents.At(tab, cell, view) view = view or Talents.View(); return view and view.cells[tab] and view.cells[tab][cell] end
function Talents.Spent(view)
  view = view or Talents.View()
  local spent = 0
  if not view then return 0 end
  for _, cells in pairs(view.cells) do for _, t in pairs(cells) do spent = spent + t.rank end end
  return spent
end
function Talents.Forget() views = {} end

function Talents.Unspent()
  local configID = activeConfig()
  if configID and C_Traits.GetTreeCurrencyInfo then
    local currencies = game("C_Traits.GetTreeCurrencyInfo", configID, treeOf(configID), false)
    if currencies and currencies[1] then return currencies[1].quantity or 0 end
  end
  if hasTraits() and C_ClassTalents.HasUnspentTalentPoints then
    local _, class, spec = C_ClassTalents.HasUnspentTalentPoints()
    return (class or 0) + (spec or 0)
  end
  if UnitCharacterPoints then return UnitCharacterPoints("player") or 0 end
  return nil
end

--[[ ---- the two specs ---- ]]
function Talents.SpecName(n) return n == 2 and (DUAL_SPEC_SECONDARY or "Secondary") or (DUAL_SPEC_PRIMARY or "Primary") end
function Talents.OtherSpec()
  if not (hasTraits() and C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and GetNumSpecGroups) then return nil end
  if (GetNumSpecGroups() or 1) < 2 then return nil end
  local other = C_SpecializationInfo.GetActiveSpecGroup() == 1 and 2 or 1
  local configID = game("C_SpecializationInfo.GetCombatConfigIDForSpecGroup", other)
  local view = configID and Talents.View(configID)
  if not view then return nil end
  return view, other
end

--[[ ---- spending points ---- ]]
--[[ Whether the talent window has points bought but not applied yet: the addon leaves those to the window. ]]
function Talents.HasStaged()
  local configID = activeConfig()
  return configID and C_Traits.ConfigHasStagedChanges and game("C_Traits.ConfigHasStagedChanges", configID) and true or false
end
Talents.STAGED = "The talent window has changes waiting. Apply or undo them there first."

--[[ Whether talents can change now, before anything is staged: not in combat. The game's own answer,
     C_ClassTalents.CanChangeTalents, is true only once changes are staged, so asked before it would always refuse;
     Learn asks it after the first point instead. ]]
function Talents.CanChange()
  if InCombatLockdown and InCombatLockdown() then return false, "You can't change talents in combat." end
  return true
end

--[[ With a point staged: true, or false and why when the game says the change can't be committed. ]]
local function canCommit()
  if not (hasTraits() and C_ClassTalents.CanChangeTalents) then return true end
  local canChange, canAdd, err = game("C_ClassTalents.CanChangeTalents")
  if canChange or canAdd then return true end
  local why = (err and err ~= "") and err or "You can't change talents right now."
  return false, why:find("[%.!?]$") and why or why .. "."
end

local committing   -- the config of the addon's commit while the game casts it, until it says how it went
local calling      -- inside CommitConfig, where the game can fail the commit before it answers

--[[ Stages a rank in each talent in order, then applies them all; if one can't be bought, none are. With the old
     API, which learns one point per server answer, only the first is learnt and the panel offers the next. ]]
function Talents.Learn(list)
  if #list == 0 then return false, "There's nothing to spend." end
  local configID = activeConfig()
  if configID then
    if Talents.HasStaged() then return false, Talents.STAGED end
    for i, t in ipairs(list) do
      if not game("C_Traits.PurchaseRank", configID, t.node) then
        game("C_Traits.RollbackConfig", configID)
        Talents.Forget()
        return false, "The game wouldn't take point " .. i .. " (" .. (t.name or "?") .. "). Nothing was spent."
      end
      if i == 1 then
        local ok, why = canCommit()
        if not ok then
          game("C_Traits.RollbackConfig", configID)
          Talents.Forget()
          return false, why .. " Nothing was spent."
        end
      end
    end
    --[[ true from CommitConfig only means the cast started: CommitFailed rolls back if the game fails it later ]]
    committing, calling = configID, true
    local started = game("C_ClassTalents.CommitConfig")
    calling = false
    if not started or committing ~= configID then
      if committing then game("C_Traits.RollbackConfig", configID) end
      committing = nil
      Talents.Forget()
      return false, "The game wouldn't apply the talents. Nothing was spent."
    end
    Talents.Forget()
    return true
  end
  if LearnTalent then
    LearnTalent(list[1].tab, list[1].node)
    Talents.Forget()
    return true
  end
  return false, "This client has no way for an addon to spend talent points."
end

function Talents.CommitFailed(configID)
  if not committing or (configID and configID ~= committing) then return false end
  game("C_Traits.RollbackConfig", committing)
  committing = nil
  Talents.Forget()
  return not calling   -- inside CommitConfig, Learn says it
end
function Talents.Committed(configID) if configID == committing then committing = nil end end
--[[ Whether the addon's own commit is casting: its points are staged and the game hasn't said how it went. Staged as well,
     so a TRAIT_CONFIG_UPDATED that never came can't leave this true for good. ]]
function Talents.Applying() return committing ~= nil and Talents.HasStaged() end

--[[ ---- the talent window ---- ]]
function Talents.Frame()
  if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then return PlayerSpellsFrame.TalentsFrame end
  return _G.TalentFrame
end
function Talents.Window() return PlayerSpellsFrame or _G.TalentFrame end
function Talents.Loaded(name) return name == "Blizzard_PlayerSpells" or name == "Blizzard_TalentUI" end

function Talents.Button(t)
  local f = Talents.Frame()
  if not f or not t then return nil end
  if f.GetTalentButtonByNodeID then return f:GetTalentButtonByNodeID(t.node) end
  if PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) ~= t.tab then return nil end
  return _G["TalentFrameTalent" .. t.node]
end

function Talents.Toggle()
  if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then PlayerSpellsUtil.ToggleClassTalentFrame()
  elseif ToggleTalentFrame then ToggleTalentFrame() end
end

--[[ A talent as /fa debug says it: row,column (cell) name rank/max, then where its node is; a talent left out has no
     cell to name. ]]
local function line(x, out)
  return x.row .. "," .. x.col .. (out and "" or (" (" .. x.cell .. ")")) .. " " .. (x.name or "?") .. " " .. x.rank .. "/" .. (x.max or "?") ..
    (x.x and (" at " .. num(x.x) .. "," .. num(x.y) .. ", node " .. tostring(x.node)) or "")
end

function Talents.Dump()
  local v, lines = Talents.View(), {}
  if not v then return { "The game hasn't given its talents yet. Open the talent window and try again." } end
  local left = 0
  for t, tree in ipairs(v.trees) do
    lines[#lines + 1] = t .. ". " .. (tree.name or "?")
    local g = v.grid and v.grid[t]
    if g and g.originX then
      lines[#lines + 1] = "   columns " .. num(g.colStep) .. " apart from x " .. num(g.originX) .. " (" .. g.origin .. "), rows " ..
        num(g.rowStep) .. " apart from y " .. num(g.topY) .. (g.borrowed and (" (" .. g.borrowed .. " spaced as another tree's)") or "")
    end
    local byPosition = v.byPosition and v.byPosition[t] or 0
    if byPosition > 0 then
      lines[#lines + 1] = "   " .. byPosition .. (byPosition == 1 and " node" or " nodes") .. " here had no group the game's list knows, so went by position (/fa debug nodes says why)"
    end
    for cell = 0, 27 do
      local x = v.cells[t][cell]
      if x then lines[#lines + 1] = "   " .. line(x) end
    end
    for _, d in ipairs(v.dropped and v.dropped[t] or {}) do
      lines[#lines + 1] = "   left out: " .. line(d.talent, true) .. ": " .. d.why
      left = left + 1
    end
  end
  for _, r in ipairs(v.skipped or {}) do
    lines[#lines + 1] = "left unread: node " .. tostring(r.info.ID) .. " at " .. (r.info.posX and (num(r.info.posX) .. "," .. num(r.info.posY)) or "no position") .. ": " .. r.skip
  end
  if v.grid then
    lines[#lines + 1] = left == 0 and "Every talent has a cell of its own." or (left .. (left == 1 and " talent" or " talents") .. " left out, marked above.")
  end
  return lines
end

--[[ Every node of the active config as the game gives it, one line each, and the tree the addon gave it and why: the raw
     fields that decide a talent's place (/fa debug nodes). ]]
local function groupList(ids, named)
  if not ids or #ids == 0 then return "" end
  local out = {}
  for i, g in ipairs(ids) do out[i] = tostring(g) .. (named[g] and ("=" .. named[g]) or "") end
  return " [" .. table.concat(out, " ") .. "]"
end

function Talents.DumpNodes()
  local configID = activeConfig()
  local groups, recs
  if configID then groups, recs = readNodes(configID) end
  if not recs then return { "The game hasn't given its talents yet. Open the talent window and try again." } end
  local lines = { #recs .. (#recs == 1 and " node" or " nodes") .. " in config " .. tostring(configID) .. "'s tree; in groupIDs a tree's group is marked with its name." }
  local named = {}
  for _, g in ipairs(groups) do named[g.groupID] = g.displayName or "?" end
  for _, r in ipairs(recs) do
    local n = r.info
    local to = r.tab and ("tree " .. r.tab .. " " .. (groups[r.tab].displayName or "?") .. " (" .. r.why .. ")") or ("not read: " .. r.skip)
    lines[#lines + 1] = "node " .. tostring(n.ID) .. " posX " .. tostring(n.posX) .. " posY " .. tostring(n.posY) ..
      " maxRanks " .. tostring(n.maxRanks) .. " totalMaxRanks " .. tostring(n.totalMaxRanks) ..
      " groupIDs " .. (n.groupIDs and #n.groupIDs or "nil") .. groupList(n.groupIDs, named) .. " entryIDs " .. (n.entryIDs and #n.entryIDs or "nil") ..
      " isVisible " .. tostring(n.isVisible) .. " type " .. tostring(n.type) .. " subTreeID " .. tostring(n.subTreeID) .. " -> " .. to
  end
  return lines
end
