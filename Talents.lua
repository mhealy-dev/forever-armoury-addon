--[[ The game's talents, under the names the rest of the addon uses: three trees of cells, each cell a talent with a
     rank, and the talent window to sit beside.

     The Forever client (game type "camelot", 1.60.x) keeps its talents in the trait system that retail's talent trees
     use: one trait tree for the class, its three talent trees as groups of nodes, each node placed by posX and posY
     and spent into with C_Traits. The talent window is PlayerSpellsFrame.TalentsFrame (Blizzard_PlayerSpells, loaded
     on demand). A node's row and column come from its position: within each group, the distinct positions sort into
     columns and rows, so the site's cell (tier - 1) * 4 + (column - 1) names the node without any talent data here.
     The old API (GetTalentInfo by tab and index, TalentFrame) isn't in the Forever client at all, but a client that
     has it instead gets the same answers from it, so the rest of the addon needs no second path.

     FA.Talents.Ready()          whether the game has told us its talents yet
     FA.Talents.Trees()          { { name, icon }, ... } in the game's order, or nil
     FA.Talents.At(tab, cell)    the talent there: { tab, cell, name, icon, rank, max, node } or nil; rank is what's spent
                                 (staged purchases included), node names it to the game (a node id, or a talent index)
     FA.Talents.Spent()          points spent in every tree
     FA.Talents.Forget()         drop what's cached: the next call asks the game again (called when points change)
     FA.Talents.Frame()          the talent window's frame, once Blizzard's talent UI has loaded, or nil
     FA.Talents.Button(t)        the window's button for a talent, or nil (the panel lights it)
     FA.Talents.Toggle()         open or close the talent window
     FA.Talents.Loaded(name)     whether an ADDON_LOADED name is the talent UI's ]]

local _, FA = ...
local Talents = {}
FA.Talents = Talents

local cache   -- { trees = {...}, cells = { [tab] = { [cell] = talent } } }, or nil

local function hasTraits() return C_Traits and C_ClassTalents and C_ClassTalents.GetActiveConfigID end

--[[ ---- the trait system (the Forever client) ---- ]]
local function traitConfig()
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return nil end
  local info = C_Traits.GetConfigInfo(configID)
  local treeID = info and info.treeIDs and info.treeIDs[1]
  if not treeID then return nil end
  return configID, treeID
end

local function round(x) return math.floor(x + 0.5) end
--[[ The smallest gap between the distinct values in a list: the pitch of the grid they sit on. ]]
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

local function readTraits()
  local configID, treeID = traitConfig()
  if not configID then return nil end
  local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
  if not groups or #groups == 0 then return nil end
  table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
  local out, tabOf = { trees = {}, cells = {} }, {}
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
  local colStep, rowStep, topY = pitch(xs), nil, nil
  rowStep, topY = pitch(ys)
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

local function read()
  if not cache then cache = hasTraits() and readTraits() or readLegacy() end
  return cache
end

function Talents.Ready() return read() ~= nil end
function Talents.Trees() local c = read(); return c and c.trees end
function Talents.At(tab, cell) local c = read(); return c and c.cells[tab] and c.cells[tab][cell] end
function Talents.Spent()
  local c, spent = read(), 0
  if not c then return 0 end
  for _, cells in pairs(c.cells) do for _, t in pairs(cells) do spent = spent + t.rank end end
  return spent
end
function Talents.Forget() cache = nil end
--[[ Every talent by tree, row and column, as lines of text: /fa debug prints them, to check the trees read right. ]]
function Talents.Dump()
  local c, lines = read(), {}
  if not c then return { "The game hasn't given its talents yet. Open the talent window and try again." } end
  for t, tree in ipairs(c.trees) do
    lines[#lines + 1] = t .. ". " .. (tree.name or "?")
    for cell = 0, 27 do
      local x = c.cells[t][cell]
      if x then lines[#lines + 1] = "   " .. x.row .. "," .. x.col .. " (" .. cell .. ") " .. (x.name or "?") .. " " .. x.rank .. "/" .. (x.max or "?") end
    end
  end
  return lines
end

--[[ ---- the talent window ---- ]]
function Talents.Frame()
  if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then return PlayerSpellsFrame.TalentsFrame end
  return _G.TalentFrame
end
--[[ The window whose edge the panel sits on: the whole spells window in the Forever client. ]]
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
