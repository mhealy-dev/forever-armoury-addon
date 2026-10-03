--[[ The game's talents, under the names the rest of the addon uses: three trees of cells, each cell a talent with a
     rank, the talent window to sit beside, and spending points.

     The Forever client (game type "camelot", 1.60.x) keeps its talents in the trait system that retail's talent trees
     use: one trait tree for the class, its three talent trees as groups of nodes, each node placed by posX and posY.
     The talent window is PlayerSpellsFrame.TalentsFrame (Blizzard_PlayerSpells, loaded on demand). A node's row and
     column come from its position, so the site's cell (tier - 1) * 4 + (column - 1) names the node without any talent
     data here. Points are staged with C_Traits.PurchaseRank and applied with C_ClassTalents.CommitConfig, as the
     window's own Apply button does; C_Traits.RollbackConfig drops what's staged. Each of the two specs (dual spec) has
     its own config. The old API (GetTalentInfo by tab and index, LearnTalent, TalentFrame) isn't in the Forever client
     at all, but a client that has it gets the same answers from it, so the rest of the addon has one path.

     A view is one spec's talents: { trees = { { name, icon }, ... }, cells = { [tab] = { [cell] = talent } } }, a
     talent being { tab, cell, row, col, name, icon, rank, max, node }; rank is what's spent, staged points included, and
     node names it to the game (a node id, or a talent index).

     FA.Talents.View([configID])     a spec's view (the active one's without a config), or nil before the game answers
     FA.Talents.Ready()              whether the active spec's view is in
     FA.Talents.Trees()              the active view's trees
     FA.Talents.At(tab, cell[, view]) a talent, or nil
     FA.Talents.Spent([view])        points spent in every tree
     FA.Talents.Unspent()            points the character has to spend, or nil when the game won't say
     FA.Talents.OtherSpec()          the inactive spec's view and its number (1 or 2), or nil without dual spec
     FA.Talents.SpecName(n)          a spec's name, "Primary" or "Secondary"
     FA.Talents.CanChange()          true, or false and why talents can't change now (combat, ...)
     FA.Talents.Learn(list)          spends a rank in each talent of a list, in order, all or none: true, or false and why
     FA.Talents.Forget()             drop what's cached: the next call asks the game again (called when points change)
     FA.Talents.Frame() / Window()   the talent window's frame and the window the panel sits on, once loaded
     FA.Talents.Button(t)            the window's button for a talent, or nil (the panel lights it)
     FA.Talents.Toggle()             open or close the talent window
     FA.Talents.Loaded(name)         whether an ADDON_LOADED name is the talent UI's
     FA.Talents.Dump()               every talent by tree, row and column, as lines of text (/fa debug) ]]

local _, FA = ...
local Talents = {}
FA.Talents = Talents

local views = {}   -- configID (or "legacy") -> view

local function hasTraits() return C_Traits and C_ClassTalents and C_ClassTalents.GetActiveConfigID and true or false end
local function activeConfig() return hasTraits() and C_ClassTalents.GetActiveConfigID() or nil end
local function treeOf(configID)
  local info = C_Traits.GetConfigInfo(configID)
  return info and info.treeIDs and info.treeIDs[1]
end

local function round(x) return math.floor(x + 0.5) end
--[[ The smallest gap between the distinct values in a list: the pitch of the grid they sit on, and the first value. ]]
local function pitch(values)
  local distinct, seen = {}, {}
  for _, v in ipairs(values) do if not seen[v] then seen[v] = true; distinct[#distinct + 1] = v end end
  table.sort(distinct)
  local step
  for i = 2, #distinct do local d = distinct[i] - distinct[i - 1]; if d > 0 and (not step or d < step) then step = d end end
  return step or 1, distinct[1]
end

--[[ Where each tree's first column is. A tree with talents in every column starts at its leftmost one. A tree that
     leaves its first column empty would start a column late that way, so when two trees are full their spacing says
     where every tree starts; a lone short tree falls back to its leftmost talent. ]]
local function columnOrigins(nodes, step)
  local minX, maxX, origins = {}, {}, {}
  for _, n in ipairs(nodes) do
    local t, x = n.tab, n.info.posX
    if not minX[t] or x < minX[t] then minX[t] = x end
    if not maxX[t] or x > maxX[t] then maxX[t] = x end
  end
  local full = {}
  for t, x in pairs(minX) do if round((maxX[t] - x) / step) == 3 then full[#full + 1] = t; origins[t] = x end end
  table.sort(full)
  for t, x in pairs(minX) do
    if not origins[t] then
      if #full >= 2 then
        local a, b = full[1], full[2]
        origins[t] = minX[a] + (t - a) * (minX[b] - minX[a]) / (b - a)
      else
        origins[t] = x
      end
    end
  end
  return origins
end

local function nodeNameAndIcon(configID, node)
  local entryID = node.entryIDs and node.entryIDs[1]
  local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
  local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
  if not def then return nil, nil end
  local name = def.overrideName or (def.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(def.spellID))
  local icon = def.overrideIcon or (def.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(def.spellID))
  return name, icon
end

--[[ ---- the trait system (the Forever client) ---- ]]
local function readTraits(configID)
  local treeID = treeOf(configID)
  if not treeID then return nil end
  local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
  if not groups or #groups == 0 then return nil end
  table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
  local out, tabOf = { trees = {}, cells = {}, configID = configID }, {}
  for i, g in ipairs(groups) do out.trees[i] = { name = g.displayName, icon = g.icon }; out.cells[i] = {}; tabOf[g.groupID] = i end
  local nodes = {}
  for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
    local n = C_Traits.GetNodeInfo(configID, nodeID)
    local tab = n and n.groupIDs and n.groupIDs[1] and tabOf[n.groupIDs[1]]
    if tab and n.maxRanks and n.maxRanks > 0 then nodes[#nodes + 1] = { tab = tab, info = n } end
  end
  if #nodes == 0 then return nil end
  --[[ the pitch of the columns and of the rows, from the whole tree; the first row is the topmost talent anywhere,
       since every tree starts at tier 1, and each tree's first column is as columnOrigins finds it ]]
  local xs, ys = {}, {}
  for _, n in ipairs(nodes) do xs[#xs + 1] = n.info.posX; ys[#ys + 1] = n.info.posY end
  local colStep = pitch(xs)
  local rowStep, topY = pitch(ys)
  local origins = columnOrigins(nodes, colStep)
  for _, n in ipairs(nodes) do
    local col, row = round((n.info.posX - origins[n.tab]) / colStep) + 1, round((n.info.posY - topY) / rowStep) + 1
    if col >= 1 and col <= 4 and row >= 1 then
      local name, icon = nodeNameAndIcon(configID, n.info)
      out.cells[n.tab][(row - 1) * 4 + (col - 1)] = { tab = n.tab, cell = (row - 1) * 4 + (col - 1), row = row, col = col,
        name = name, icon = icon, rank = n.info.ranksPurchased or 0, max = n.info.maxRanks, node = n.info.ID }
    end
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
    local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeOf(configID), false)
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
  local configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(other)
  local view = configID and Talents.View(configID)
  if not view then return nil end
  return view, other
end

--[[ ---- spending points ---- ]]
--[[ Whether the talent window has points bought but not applied yet: the addon leaves those to the window. ]]
function Talents.HasStaged()
  local configID = activeConfig()
  return configID and C_Traits.ConfigHasStagedChanges and C_Traits.ConfigHasStagedChanges(configID) and true or false
end
Talents.STAGED = "The talent window has changes waiting. Apply or undo them there first."

function Talents.CanChange()
  if InCombatLockdown and InCombatLockdown() then return false, "You can't change talents in combat." end
  if hasTraits() and C_ClassTalents.CanChangeTalents then
    local canChange, canAdd, err = C_ClassTalents.CanChangeTalents()
    if not canChange and not canAdd then return false, (err and err ~= "") and err or "You can't change talents right now." end
  end
  return true
end

--[[ Stages a rank in each talent in order, then applies them all; if one can't be bought, none are. With the old
     API, which learns one point per server answer, only the first is learnt and the panel offers the next. ]]
function Talents.Learn(list)
  if #list == 0 then return false, "There's nothing to spend." end
  local configID = activeConfig()
  if configID then
    if Talents.HasStaged() then return false, Talents.STAGED end
    for i, t in ipairs(list) do
      if not C_Traits.PurchaseRank(configID, t.node) then
        C_Traits.RollbackConfig(configID)
        Talents.Forget()
        return false, "The game wouldn't take point " .. i .. " (" .. (t.name or "?") .. "). Nothing was spent."
      end
    end
    if not C_ClassTalents.CommitConfig() then
      C_Traits.RollbackConfig(configID)
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

function Talents.Dump()
  local v, lines = Talents.View(), {}
  if not v then return { "The game hasn't given its talents yet. Open the talent window and try again." } end
  for t, tree in ipairs(v.trees) do
    lines[#lines + 1] = t .. ". " .. (tree.name or "?")
    for cell = 0, 27 do
      local x = v.cells[t][cell]
      if x then lines[#lines + 1] = "   " .. x.row .. "," .. x.col .. " (" .. cell .. ") " .. (x.name or "?") .. " " .. x.rank .. "/" .. (x.max or "?") end
    end
  end
  return lines
end
