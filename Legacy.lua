--[[ The Legacy part: the account's Legacy plans, where the account is on one, and what Apply buys.

     WoW Forever's Legacy is account-wide: three perk trees (Professions, Adventure, Resourcefulness), 27 perks, and a
     seasonal cap on the points spent in all. Each tree is an ordinary trait tree with a config of its own, which the
     game's Legacy window (Blizzard_LegacySystem) buys in with C_Traits.PurchaseRank and applies with
     C_Traits.CommitConfig(configID), not C_ClassTalents. So Apply here works tree by tree: all or none in each.

     FA.db.legacy is a list of { id, name, ranks, build }: every plan imported on this account (Legacy being the
     account's, not a class's), the ranks as the code has them (27 characters of base 36, one a perk, in PERKS' order)
     and the client build their order is from. FA.db.legacyFollow is the id of the plan the account follows.

     PERKS is the 27 perks in the site's order (forever-armoury public/data/legacy.js, which a code's ranks are in),
     each { node, tree, max, name, row, col, after, need, locked, icon }: the trait node, the tree's id, the most ranks, the
     perk's row and column in its tree, the place in its tree (1 to 9) of the perk that must be full before this one can
     be bought (0 for none), the points that must be spent on the tree's other perks first, and whether the game shows
     the perk but doesn't sell it yet (its name is Unknown). The table is of one client build, BUILD; a plan from
     another build has other places for its ranks, so it is shown and never bought.

     FA.Legacy.Plans()                the saved plans
     FA.Legacy.Add(plans)             keeps plans a code gave (LegacyCode.Read's); how many were new or updated
     FA.Legacy.Find(id)               a plan, or nil
     FA.Legacy.Forget(id)             drops one
     FA.Legacy.Active()               the plan the account follows, or nil
     FA.Legacy.SetActive(id)          follows a plan (nil: none)
     FA.Legacy.Export()               the code for every plan, one line a build, or nil when there are none
     FA.Legacy.Differs(plan)          whether a plan is from another build than PERKS
     FA.Legacy.Ranks()                the account's rank of every perk as the game says, [1..27], or nil and why
     FA.Legacy.Points()               the Legacy points available, and the seasonal cap, each nil when the game won't say
     FA.Legacy.Progress(plan)         where the account is on a plan (below), or nil and why
     FA.Legacy.Order(plan)            every rank of a plan from nothing, in the order to buy them (the strip's taken ranks)
     FA.Legacy.Plan(plan)             what Apply would buy now: the list of steps and the progress, or nil and why
     FA.Legacy.Button(step)           the Legacy window's button for a perk, or nil (the panel lights it, the strip's hover too)
     FA.Legacy.Config(tree)           the game's config for a tree (the strip reads a perk's definition through it)
     FA.Legacy.TreeShown(tree)        whether the window shows a tree: its perks have buttons
     FA.Legacy.CanShowTree()          whether an addon can switch the window to a tree
     FA.Legacy.ShowTree(tree)         switches the window to a tree, as its tab would
     FA.Legacy.Applying()             whether the addon's commit is casting (its ranks staged, the game not yet answered)
     FA.Legacy.Summary(steps)         the steps as a short line: "Master Chef x2, Working Overtime"
     FA.Legacy.CommitFailed(cfg)      CONFIG_COMMIT_FAILED: rolls back what the addon staged in a config, true when it was the addon's
     FA.Legacy.Committed(cfg)         TRAIT_CONFIG_UPDATED: the addon's commit went through
     FA.Legacy.Loaded(name)           whether an ADDON_LOADED name is the Legacy window's
     FA.ApplyLegacy(plan[, limit])    buys the steps of Plan (the first `limit` of them, when one is given: the strip's click buys
                                      one), tree by tree: true, or false and why

     Progress answers { perks, steps, blocked, over, wanted, had, spent, differs } for a plan with its build:
       perks     [1..27] = { have, want }: the rank the account has and the plan wants (never past the perk's most)
       steps     every rank still to buy, in the order to buy them: { perk, rank, node, tree, name, max }; by tree, then
                 by row, a perk's prerequisite full and the points its tree wants spent first being met
       blocked   the perks the plan wants that can't be bought as the plan stands: { perk, why } (a perk the game doesn't
                 sell yet, a prerequisite or a gate the plan itself doesn't meet)
       over      how many ranks the account has that the plan doesn't want (Apply never refunds)
       wanted    the plan's points; had, how many of those the account has; spent, every point the account has spent ]]

local _, FA = ...
local Legacy = {}
FA.Legacy = Legacy
local game = FA.Talents.Game

Legacy.BUILD = 70425          -- the client build PERKS is from
Legacy.CLIENT = "1.60.1.70425"
Legacy.CAP = 16               -- the seasonal cap of points spent in all three trees, when the game won't say it
Legacy.CURRENCY = 4225        -- the Legacy points
Legacy.TREE_PAGE = 3          -- LegacySystemFrame.Pages: the reward track, the challenges, then the trees
Legacy.TREES = { { id = 1187, name = "Professions", short = "Prof" }, { id = 1188, name = "Adventure", short = "Adv" },
  { id = 1189, name = "Resourcefulness", short = "Res" } }   -- short: what the strip's badges call them

--[[ Copied by hand from forever-armoury's public/data/legacy.js (client build 1.60.1.70425; that file is generated from
     the game's tables, so these come from the game's): { node, tree, max, name, row, col, after, need, locked, icon }, with
     `after` made a place in the tree from 1 (0 for none) and icon the name of the perk's file under Interface\Icons. Re-copy them when the site's build moves. ]]
local TABLE = {
  -- Professions
  { 110289, 1187, 5, "Master Chef", 1, 2, 0, 5, false, "achievement_profession_chefhat" },
  { 110290, 1187, 5, "Working Overtime", 2, 1, 0, 0, false, "inv_misc_pocketwatch_03" },
  { 110286, 1187, 2, "Bartering", 2, 2, 0, 5, false, "inv_misc_coin_06" },
  { 110284, 1187, 1, "Dedicated Study", 2, 3, 3, 10, false, "inv_misc_book_08" },
  { 110291, 1187, 5, "Bountiful Harvest", 3, 1, 0, 0, false, "inv_misc_bag_18" },
  { 110292, 1187, 3, "Performance Bonus", 3, 2, 5, 5, false, "racial_dwarf_findtreasure" },
  { 113508, 1187, 1, "Unknown", 3, 3, 0, 0, true, "inv_misc_questionmark" },
  { 113506, 1187, 1, "Unknown", 3, 4, 7, 0, true, "inv_misc_questionmark" },
  { 110293, 1187, 2, "Luremaster", 4, 2, 0, 5, false, "inv_misc_basket_04" },
  -- Adventure
  { 110305, 1188, 2, "High Alert", 1, 2, 0, 5, false, "spell_shadow_detectlesserinvisibility" },
  { 110301, 1188, 5, "Well Rested", 2, 1, 0, 0, false, "spell_nature_sleep" },
  { 110298, 1188, 5, "Talented", 2, 2, 2, 5, false, "ability_marksmanship" },
  { 113511, 1188, 1, "Unknown", 2, 3, 0, 0, true, "inv_misc_questionmark" },
  { 113510, 1188, 1, "Unknown", 2, 4, 4, 0, true, "inv_misc_questionmark" },
  { 110296, 1188, 5, "Thrill of Adventure", 3, 1, 0, 0, false, "ability_hunter_huntervswild" },
  { 110304, 1188, 3, "Field Guide", 3, 2, 0, 5, false, "inv_fishingchair" },
  { 110300, 1188, 1, "Frequent Flier", 3, 3, 7, 10, false, "achievement_guild_ridelikethewind" },
  { 110303, 1188, 2, "Field Medicine", 4, 2, 0, 5, false, "inv_misc_bandage_05" },
  -- Resourcefulness
  { 110319, 1189, 5, "For Great Honor", 1, 2, 0, 5, false, "achievement_bg_winwsg" },
  { 110313, 1189, 3, "Gourmand", 2, 1, 0, 0, false, "inv_misc_food_64" },
  { 110316, 1189, 2, "Permanence", 2, 2, 2, 5, false, "spell_misc_emotionhappy" },
  { 113513, 1189, 1, "Unknown", 2, 3, 0, 0, true, "inv_misc_questionmark" },
  { 113512, 1189, 1, "Unknown", 2, 4, 4, 0, true, "inv_misc_questionmark" },
  { 110315, 1189, 2, "The Quick and the Dead", 3, 1, 0, 0, false, "spell_shadow_deadofnight" },
  { 110309, 1189, 1, "Reagent Economy", 3, 3, 6, 10, false, "inv_misc_candle_02" },
  { 110318, 1189, 5, "Reinforce", 4, 1, 0, 0, false, "inv_misc_armorkit_17" },
  { 110314, 1189, 5, "Diplomat", 4, 2, 0, 5, false, "inv_scroll_03" },
}
Legacy.PERKS = {}
local TREE_INDEX = {}   -- tree id -> its place in TREES
for t, tree in ipairs(Legacy.TREES) do TREE_INDEX[tree.id] = t; tree.perks = {} end
for i, x in ipairs(TABLE) do
  local perk = { node = x[1], tree = x[2], max = x[3], name = x[4], row = x[5], col = x[6], after = x[7], need = x[8], locked = x[9], icon = x[10] }
  local tree = Legacy.TREES[TREE_INDEX[perk.tree]]
  tree.perks[#tree.perks + 1] = i                      -- the tree's perks, as places in PERKS
  perk.place = #tree.perks                             -- its place in its tree, which `after` names
  perk.afterIndex = perk.after > 0 and tree.perks[perk.after] or nil
  Legacy.PERKS[i] = perk
end
assert(#Legacy.PERKS == FA.LegacyCode.PERKS, "Legacy.lua's perks and LegacyCode.lua's ranks disagree")

--[[ ---- the plans, kept for the account ---- ]]
function Legacy.Plans() return FA.db.legacy end

--[[ The saved plans as they load: a plan that isn't a table, or whose ranks don't have a plan's shape, is dropped (a
     newer addon may have written ranks this one can't read); a name that isn't text is emptied, a build that isn't a
     number is 0 (no build, which no table matches), an id that isn't a number or is another plan's is given a new one.
     The followed plan is cleared when it is gone. Answers how many were dropped and how many repaired. ]]
function Legacy.Repair()
  local dropped, repaired, seen, kept = 0, 0, {}, {}
  if type(FA.db.legacy) ~= "table" then FA.db.legacy = {} end
  for _, p in ipairs(FA.db.legacy) do
    if type(p) ~= "table" or not FA.LegacyCode.Shaped(p.ranks) then
      dropped = dropped + 1
    else
      local fixed = false
      if type(p.name) ~= "string" then p.name = ""; fixed = true end
      if type(p.build) ~= "number" then p.build = 0; fixed = true end
      if type(p.id) ~= "number" or seen[p.id] then p.id = nil; fixed = true else seen[p.id] = true end
      if fixed then repaired = repaired + 1 end
      kept[#kept + 1] = p
    end
  end
  FA.db.legacy = kept
  for _, p in ipairs(kept) do
    if not p.id then p.id = FA.db.nextId end
    FA.db.nextId = math.max(FA.db.nextId, p.id + 1)
  end
  if FA.db.legacyFollow and not Legacy.Find(FA.db.legacyFollow) then FA.db.legacyFollow = nil end
  return dropped, repaired
end

--[[ Keeps the plans a code gave, each with the build it's from. A plan with the name and ranks of one already kept
     updates that one's build and keeps its id, so pasting a plan again leaves the account following it; the same ranks
     under another name, or another name's ranks, are another plan. Answers how many plans were given. ]]
function Legacy.Add(plans)
  for _, p in ipairs(plans) do
    local found
    for _, old in ipairs(FA.db.legacy) do if old.name == p.name and old.ranks == p.ranks then found = old end end
    if found then found.build = p.build or 0
    else
      FA.db.legacy[#FA.db.legacy + 1] = { id = FA.db.nextId, name = p.name, ranks = p.ranks, build = p.build or 0 }
      FA.db.nextId = FA.db.nextId + 1
    end
  end
  return #plans
end

function Legacy.Find(id)
  for i, p in ipairs(FA.db.legacy) do if p.id == id then return p, i end end
  return nil
end

function Legacy.Forget(id)
  local p, i = Legacy.Find(id)
  if not p then return false end
  table.remove(FA.db.legacy, i)
  if FA.db.legacyFollow == id then FA.db.legacyFollow = nil end
  return true
end

function Legacy.Active() return FA.db.legacyFollow and Legacy.Find(FA.db.legacyFollow) or nil end
function Legacy.SetActive(id) FA.db.legacyFollow = id end

--[[ The code for every plan, for the site's Import box; nil when there are none. A code carries one build, so plans
     from different ones are a code each, a line each, in the order the first of each comes. A plan with no build (0) is
     written with build 0, which the site reads as one from another build. ]]
function Legacy.Export()
  local groups, byBuild = {}, {}
  for _, p in ipairs(FA.db.legacy) do
    if not byBuild[p.build] then byBuild[p.build] = { build = p.build, plans = {} }; groups[#groups + 1] = byBuild[p.build] end
    local list = byBuild[p.build].plans
    list[#list + 1] = p
  end
  if #groups == 0 then return nil end
  local codes = {}
  for i, g in ipairs(groups) do codes[i] = FA.LegacyCode.Write(g.plans, g.build) end
  return table.concat(codes, "\n")
end

function Legacy.Differs(plan) return plan.build ~= Legacy.BUILD end
local function differsWhy(plan)
  return "This plan is from client build " .. (plan.build ~= 0 and plan.build or "unknown") .. ", and this addon's Legacy perks are from " ..
    Legacy.BUILD .. ", so its ranks may mean other perks. Get the plan again from the site, or update the addon."
end

--[[ ---- what the game says ---- ]]
local function configOf(tree) return game("C_Traits.GetConfigIDByTreeID", tree.id) end

--[[ The account's rank in every perk, [1..27], and the config of every tree ([1..3]); nil and why when the game hasn't
     given a tree's config or a perk's node (the Legacy trees come with the character, but not before it). ]]
function Legacy.Ranks()
  local ranks, configs = {}, {}
  for t, tree in ipairs(Legacy.TREES) do
    local configID = configOf(tree)
    if not configID then return nil, "The game hasn't given the Legacy trees yet. Open the Legacy window and try again." end
    configs[t] = configID
    for _, i in ipairs(tree.perks) do
      local info = game("C_Traits.GetNodeInfo", configID, Legacy.PERKS[i].node)
      local rank = info and tonumber(info.ranksPurchased)
      if not rank then return nil, "The game doesn't know the Legacy perk " .. Legacy.PERKS[i].name .. " (node " .. Legacy.PERKS[i].node .. ")." end
      ranks[i] = rank
    end
  end
  return ranks, nil, configs
end

--[[ The Legacy points available and the seasonal cap, from the first tree's currency as the Legacy window reads it (the
     points are the account's, so every tree says the same); each nil when the game won't say. ]]
function Legacy.Points()
  local configID = configOf(Legacy.TREES[1])
  local list = configID and C_Traits and C_Traits.GetTreeCurrencyInfo and game("C_Traits.GetTreeCurrencyInfo", configID, Legacy.TREES[1].id, false)
  local info
  for _, c in ipairs(list or {}) do if c.traitCurrencyID == Legacy.CURRENCY then info = c end end
  info = info or (list and list[1])
  if not info then return nil, nil end
  return tonumber(info.quantity), tonumber(info.maxQuantity)
end

--[[ Whether any Legacy tree has points bought but not applied: those are the Legacy window's. ]]
function Legacy.HasStaged()
  for _, tree in ipairs(Legacy.TREES) do
    local configID = configOf(tree)
    if configID and C_Traits and C_Traits.ConfigHasStagedChanges and game("C_Traits.ConfigHasStagedChanges", configID) then return true end
  end
  return false
end
Legacy.STAGED = "The Legacy window has changes waiting. Apply or undo them there first."

--[[ ---- where the account is on a plan ---- ]]
--[[ A tree's ranks to buy, in the order to buy them, from the ranks sim has in every perk (which this raises as it goes):
     a rank of the first perk (by row, then column) that can be bought as things stand, until no perk the plan wants
     can be. A perk's prerequisite has to be full, and the points on the tree's other perks have to reach its need; a
     perk the plan has begun needs neither again. want(i) is the ranks the plan wants of a perk; each step is added to
     steps. Answers the tree's perks in the row and column order. ]]
local function walk(tree, sim, want, steps)
  local order = {}
  for _, i in ipairs(tree.perks) do order[#order + 1] = i end
  table.sort(order, function(a, b)
    local x, y = Legacy.PERKS[a], Legacy.PERKS[b]
    if x.row ~= y.row then return x.row < y.row end
    return x.col < y.col
  end)
  --[[ The gate: the points on all the tree's other perks, every rank. The site's legacyBefore (assets/app/legacy.js)
       counts only the perks with a lower gate; the two agree while the gates are 0, 5 and 10, as in build 70425.
       Check them again when this table is re-copied for another client build. ]]
  local function ready(i)
    local perk = Legacy.PERKS[i]
    if perk.locked or sim[i] >= want(i) then return false end
    if sim[i] > 0 then return true end
    if perk.afterIndex and sim[perk.afterIndex] < Legacy.PERKS[perk.afterIndex].max then return false end
    local others = 0
    for _, j in ipairs(tree.perks) do if j ~= i then others = others + sim[j] end end
    return others >= perk.need
  end
  local moved = true
  while moved do
    moved = false
    for _, i in ipairs(order) do
      if ready(i) then
        sim[i] = sim[i] + 1
        local perk = Legacy.PERKS[i]
        steps[#steps + 1] = { perk = i, rank = sim[i], node = perk.node, tree = Legacy.TREES[TREE_INDEX[perk.tree]], name = perk.name, max = perk.max }
        moved = true
        break
      end
    end
  end
  return order
end

--[[ Every rank the plan buys from nothing, in the order to buy them (what Apply would buy for an account with no Legacy
     ranks at all): the steps of every tree in turn. A perk the plan wants that can't be bought as the plan stands has no
     step. The strip shows the ranks the account has from it, then the ones still to buy (Progress's steps). ]]
function Legacy.Order(plan)
  if Legacy.Differs(plan) then return {} end
  local sim, steps = {}, {}
  for i in ipairs(Legacy.PERKS) do sim[i] = 0 end
  for _, tree in ipairs(Legacy.TREES) do
    walk(tree, sim, function(i) return math.min(tonumber(plan.ranks:sub(i, i), 36) or 0, Legacy.PERKS[i].max) end, steps)
  end
  return steps
end

function Legacy.Progress(plan)
  if Legacy.Differs(plan) then return nil, differsWhy(plan) end
  local had, why = Legacy.Ranks()
  if not had then return nil, why end
  local out = { perks = {}, steps = {}, blocked = {}, over = 0, wanted = 0, had = 0, spent = 0 }
  local sim = {}
  for i, perk in ipairs(Legacy.PERKS) do
    local want = math.min(tonumber(plan.ranks:sub(i, i), 36) or 0, perk.max)
    out.perks[i] = { have = had[i], want = want }
    sim[i] = had[i]
    out.wanted, out.spent = out.wanted + want, out.spent + had[i]
    out.had = out.had + math.min(want, had[i])
    out.over = out.over + math.max(0, had[i] - want)
  end
  for _, tree in ipairs(Legacy.TREES) do
    local order = walk(tree, sim, function(i) return out.perks[i].want end, out.steps)
    for _, i in ipairs(order) do
      local want, perk = out.perks[i].want, Legacy.PERKS[i]
      if sim[i] < want then
        local why
        if perk.locked then why = "the game doesn't sell it yet"
        elseif perk.afterIndex and sim[perk.afterIndex] < Legacy.PERKS[perk.afterIndex].max and out.perks[perk.afterIndex].want < Legacy.PERKS[perk.afterIndex].max then
          why = "the plan doesn't fill " .. Legacy.PERKS[perk.afterIndex].name .. " first"
        else why = "the plan has too few points in " .. tree.name .. " before it" end
        out.blocked[#out.blocked + 1] = { perk = i, why = why }
      end
    end
  end
  return out
end

--[[ What Apply would buy now: the steps of Progress, as many as the points allow and the cap leaves room for. Answers
     the list, the progress, and how many steps the points kept back; or nil and why. ]]
function Legacy.Plan(plan)
  if InCombatLockdown and InCombatLockdown() then return nil, "You can't change Legacy perks in combat." end
  if Legacy.HasStaged() then return nil, Legacy.STAGED end
  local p, why = Legacy.Progress(plan)
  if not p then return nil, why end
  if #p.steps == 0 then
    if #p.blocked > 0 then return nil, "The plan's other ranks can't be bought: " .. Legacy.PERKS[p.blocked[1].perk].name .. ", " .. p.blocked[1].why .. "." end
    return nil, "Every rank of this plan is bought."
  end
  local available, cap = Legacy.Points()
  cap = cap or Legacy.CAP
  local room = cap - p.spent
  if room <= 0 then return nil, "You have spent the seasonal cap of " .. cap .. " Legacy points." end
  local budget = room
  if available ~= nil then
    if available <= 0 then return nil, "You have no Legacy points to spend." end
    budget = math.min(budget, available)
  end
  local list = {}
  for i = 1, math.min(budget, #p.steps) do list[i] = p.steps[i] end
  return list, p, #p.steps - #list
end

function Legacy.Summary(steps, limit)
  local order, count = {}, {}
  for _, s in ipairs(steps) do
    if not count[s.perk] then order[#order + 1] = s; count[s.perk] = 0 end
    count[s.perk] = count[s.perk] + 1
  end
  local parts = {}
  for i, s in ipairs(order) do
    if limit and i > limit then parts[#parts + 1] = "and " .. (#order - limit) .. " more"; break end
    parts[#parts + 1] = s.name .. (count[s.perk] > 1 and (" x" .. count[s.perk]) or "")
  end
  return table.concat(parts, ", ")
end

--[[ ---- spending points ---- ]]
local committing = {}   -- configID -> true while the game casts the addon's commit, until it says how it went
local calling           -- the config inside CommitConfig, where the game can fail the commit before it answers
local failedNow         -- whether that happened

--[[ One tree's steps: a rank of each perk in order, then the commit; if one can't be bought, or the commit is turned
     down, none are. Answers true, or false and why. ]]
local function buy(tree, configID, steps)
  for i, s in ipairs(steps) do
    if not game("C_Traits.PurchaseRank", configID, s.node) then
      game("C_Traits.RollbackConfig", configID)
      return false, "The game wouldn't take " .. s.name .. (s.max > 1 and (" rank " .. s.rank) or "") .. " (" .. tree.name .. "). Nothing was bought in " .. tree.name .. "."
    end
  end
  --[[ true from CommitConfig only means the commit started: CommitFailed rolls back if the game fails it later ]]
  committing[configID], calling, failedNow = true, configID, false
  local started = game("C_Traits.CommitConfig", configID)
  calling = nil
  --[[ the game can also answer TRAIT_CONFIG_UPDATED inside the call (Committed clears the flag), which is a success ]]
  if not started or failedNow then
    if committing[configID] then game("C_Traits.RollbackConfig", configID) end
    committing[configID] = nil
    return false, "The game wouldn't apply the " .. tree.name .. " perks. Nothing was bought in " .. tree.name .. "."
  end
  return true
end

--[[ Buys the steps Plan chose (the first `limit` of them, when one is given: the strip's click buys one), tree by tree. ]]
function FA.ApplyLegacy(plan, limit)
  local list, p = Legacy.Plan(plan)
  if not list then return false, p end
  if limit and limit < #list then
    local first = {}
    for i = 1, limit do first[i] = list[i] end
    list = first
  end
  local _, _, configs = Legacy.Ranks()
  local bought, said = {}, {}
  for t, tree in ipairs(Legacy.TREES) do
    local steps = {}
    for _, s in ipairs(list) do if s.tree == tree then steps[#steps + 1] = s end end
    if #steps > 0 then
      local ok, why = buy(tree, configs[t], steps)
      if ok then for _, s in ipairs(steps) do bought[#bought + 1] = s end else said[#said + 1] = why end
    end
  end
  if #said == 0 then return true, Legacy.Summary(bought) end
  if #bought > 0 then said[#said + 1] = "Bought: " .. Legacy.Summary(bought) .. "." end
  return false, table.concat(said, " ")
end

function Legacy.CommitFailed(configID)
  if configID then
    if not committing[configID] then return false end
    game("C_Traits.RollbackConfig", configID)
    committing[configID] = nil
    if calling == configID then failedNow = true; return false end   -- inside CommitConfig, Apply says it
    return true
  end
  -- the game said no config: the addon's commit in flight, if any, is the one
  local any = false
  for id in pairs(committing) do
    game("C_Traits.RollbackConfig", id)
    committing[id] = nil
    if calling == id then failedNow = true else any = true end
  end
  return any
end
function Legacy.Committed(configID) if configID then committing[configID] = nil end end
--[[ Whether the addon's own commit is casting: a config it committed has its ranks staged and the game hasn't said how
     it went. Staged as well, so a TRAIT_CONFIG_UPDATED that never came can't leave this true for good. ]]
function Legacy.Applying()
  for configID in pairs(committing) do
    if C_Traits and C_Traits.ConfigHasStagedChanges and game("C_Traits.ConfigHasStagedChanges", configID) then return true end
  end
  return false
end

--[[ ---- the Legacy window ---- ]]
function Legacy.Loaded(name) return name == "Blizzard_LegacySystem" end

--[[ The window's tree panel (LegacySystemFrame.TreePage.LegacyTreeTraitPanel, a talent frame like the class one),
     which shows one tree at a time: a button for a perk of another tree is nil. ]]
function Legacy.TreePanel()
  local f = _G.LegacySystemFrame
  return f and f.TreePage and f.TreePage.LegacyTreeTraitPanel or nil
end
function Legacy.Button(step)
  local panel = Legacy.TreePanel()
  if not (panel and panel.GetTalentButtonByNodeID and step) then return nil end
  return panel:GetTalentButtonByNodeID(step.node)
end

--[[ The tree's config, for reading its nodes' definitions. ]]
function Legacy.Config(tree) return configOf(tree) end

--[[ Whether a tree is the one the window shows: its perks have buttons. ]]
function Legacy.TreeShown(tree)
  for _, i in ipairs(tree.perks) do
    if Legacy.Button(Legacy.PERKS[i]) then return true end
  end
  return false
end

--[[ A tree's place in the game's list of Legacy trees (LegacyTreeData), which its tree tabs and its panel's SelectTree
     number them by; the place in TREES when the game's list isn't there. ]]
local function treeIndex(tree)
  for i, data in ipairs(_G.LegacyTreeData or {}) do
    if type(data) == "table" and data.treeID == tree.id then return i end
  end
  return TREE_INDEX[tree.id]
end

--[[ Whether an addon can switch the window to a tree: the window's tree tabs send the event Legacy.SelectTree with the
     tree's place (Blizzard_LegacyTree.lua), which its tree panel and its tabs listen to, and the panel has SelectTree
     itself. Either will do. ]]
function Legacy.CanShowTree()
  local panel = Legacy.TreePanel()
  if not panel then return false end
  return (EventRegistry and type(EventRegistry.TriggerEvent) == "function") or type(panel.SelectTree) == "function"
end

--[[ Switches the window to a tree as its tab would, the trees page first if the window shows another page. Answers
     whether it was asked to: the game's event, so the tabs' selection follows, else the panel's own SelectTree. ]]
function Legacy.ShowTree(tree)
  local panel = Legacy.TreePanel()
  local index = treeIndex(tree)
  if not (panel and index and Legacy.CanShowTree()) then return false end
  if EventRegistry and type(EventRegistry.TriggerEvent) == "function" then
    if panel.IsVisible and not panel:IsVisible() then pcall(EventRegistry.TriggerEvent, EventRegistry, "Legacy.SelectPage", Legacy.TREE_PAGE) end
    return (pcall(EventRegistry.TriggerEvent, EventRegistry, "Legacy.SelectTree", index))
  end
  return (pcall(panel.SelectTree, panel, index))
end
