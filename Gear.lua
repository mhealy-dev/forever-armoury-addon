--[[ The leveling gear part: the site's gear routes kept per account, the one this character is on, and the next
     pieces at its level.

     FA.db.gear[class] is a list of { spec, side, pieces }: every route imported on this account, by class, one per
     spec and side (a paste of the same spec and side replaces it). A route is the site's leveling route (forever-armoury
     public/content/route/<class>.json): the weapons and key armour pieces picked up on the way to 60, in order, each
     { id, level, slot, from }. The character's route is its class's for its spec and side: the side from the game,
     the spec the heaviest tree of the build it follows, or the one it chose (FA.char.gearSpec) when there's no build
     or the trees tie.

     FA.Gear.RoutesFor(cls)                 the routes kept for a class
     FA.Gear.Add(routes)                    keeps routes a code gave; how many were this class's, and how many others'
     FA.Gear.Find(cls, spec, side)          a route, or nil
     FA.Gear.Forget(cls, spec, side)        drops one
     FA.Gear.Side()                         "alliance" or "horde", from the game; nil before it says
     FA.Gear.BuildSpec(build)               the heaviest tree of a build, 0 to 2, or nil on a tie or without points
     FA.Gear.Spec()                         the character's spec, and where it came from: "chosen", "build", or nil
     FA.Gear.SetSpec(spec)                  chooses a spec (nil: back to the build's)
     FA.Gear.SpecName(spec)                 a tree's name from the game, or "spec 1" when it hasn't said
     FA.Gear.Route()                        this character's route, or nil and why
     FA.Gear.Owned()                        the item ids equipped or in the bags, as a set
     FA.Gear.Plan(route, level, owned, twoHand)
                                            where a character is on a route at a level (below); owned and twoHand
                                            are optional
     FA.Gear.SourceText(piece, names)       where a piece comes from, in words the game gives; names is optional

     Plan answers { slots, get, coming, worn, had }:
       slots    [slot] = { now, next, had }: now is the piece the route has in the slot at this level (the last one
                picked up by then), next the first picked up after it, had whether now is owned. An off hand is put
                away by a two-handed main hand picked up after it, as the site's route-fit.js has it.
       get      every now piece not had, in the route's order: what to go and get
       coming   every piece picked up after this level, in the route's order
       worn     how many slots have a now piece; had, how many of those are owned
     owned is a set of item ids (Owned's), and twoHand(id) says whether an item is two-handed (the game's answer,
     nil while it hasn't loaded the item); both can be given, for the tests. ]]

local _, FA = ...
local Gear = {}
FA.Gear = Gear

function Gear.RoutesFor(cls)
  local list = FA.db.gear[cls]
  if not list then list = {}; FA.db.gear[cls] = list end
  return list
end

function Gear.Find(cls, spec, side)
  for i, r in ipairs(Gear.RoutesFor(cls)) do if r.spec == spec and r.side == side then return r, i end end
  return nil
end

function Gear.Add(routes)
  local mine, others = 0, 0
  for _, r in ipairs(routes) do
    local list = Gear.RoutesFor(r.cls)
    local old, i = Gear.Find(r.cls, r.spec, r.side)
    local kept = { spec = r.spec, side = r.side, pieces = r.pieces }
    if old then list[i] = kept else list[#list + 1] = kept end
    if r.cls == FA.class then mine = mine + 1 else others = others + 1 end
  end
  return mine, others
end

function Gear.Forget(cls, spec, side)
  local r, i = Gear.Find(cls, spec, side)
  if not r then return false end
  table.remove(Gear.RoutesFor(cls), i)
  return true
end

function Gear.Side()
  local side = UnitFactionGroup and UnitFactionGroup("player")
  side = side and side:lower()
  if side == "alliance" or side == "horde" then return side end
  return nil
end

function Gear.BuildSpec(build)
  local points = build and FA.Code.Points(build.picks)
  if not points or #points == 0 then return nil end
  local count = { 0, 0, 0 }
  for _, p in ipairs(points) do count[p.tab] = count[p.tab] + 1 end
  local best, tie = 1, false
  for t = 2, 3 do
    if count[t] > count[best] then best, tie = t, false elseif count[t] == count[best] then tie = true end
  end
  if tie then return nil end
  return best - 1
end

function Gear.Spec()
  local chosen = FA.char.gearSpec
  if chosen ~= nil then return chosen, "chosen" end
  local spec = Gear.BuildSpec(FA.ActiveBuild and FA.ActiveBuild())
  if spec ~= nil then return spec, "build" end
  return nil, nil
end
function Gear.SetSpec(spec) FA.char.gearSpec = spec end

function Gear.SpecName(spec)
  local trees = FA.Talents and FA.Talents.Trees and FA.Talents.Trees()
  local tree = trees and trees[spec + 1]
  return tree and tree.name or ("spec " .. (spec + 1))
end

function Gear.Route()
  local list = Gear.RoutesFor(FA.class)
  if #list == 0 then return nil, "No gear route for this class yet. On the site, open Best in slot, Leveling, Copy for addon, then Import here." end
  local side = Gear.Side()
  if not side then return nil, "The game hasn't said which side you're on yet." end
  local spec = Gear.Spec()
  if spec == nil then return nil, "Pick a spec: follow a build, or press the spec button." end
  local route = Gear.Find(FA.class, spec, side)
  if not route then
    local sideName = side:sub(1, 1):upper() .. side:sub(2)
    return nil, "No " .. Gear.SpecName(spec) .. " route for " .. sideName .. " here yet. Copy it from the site's Leveling plate and Import it."
  end
  return route
end

function Gear.Owned()
  local set = {}
  if GetInventoryItemID then
    for slot = 1, 19 do
      local id = GetInventoryItemID("player", slot)
      if id then set[id] = true end
    end
  end
  local count = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local item = C_Container and C_Container.GetContainerItemID or GetContainerItemID
  if count and item then
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
      for slot = 1, (count(bag) or 0) do
        local id = item(bag, slot)
        if id then set[id] = true end
      end
    end
  end
  return set
end

--[[ Whether an item is two-handed, from the game; nil while it hasn't loaded the item. ]]
function Gear.TwoHand(id)
  local info = C_Item and C_Item.GetItemInfo or GetItemInfo
  if not info then return nil end
  local name, _, _, _, _, _, _, _, equip = info(id)
  if not name then return nil end
  return equip == "INVTYPE_2HWEAPON"
end

function Gear.Plan(route, level, owned, twoHand)
  owned = owned or Gear.Owned()
  twoHand = twoHand or Gear.TwoHand
  local slots, get, coming = {}, {}, {}
  for _, slot in ipairs(FA.GearCode.SLOTS) do slots[slot] = {} end
  for _, p in ipairs(route.pieces) do
    local s = slots[p.slot]
    if s then
      if p.level <= level then s.now = p
      elseif not s.next then s.next = p end
    end
    if p.level > level then coming[#coming + 1] = p end
  end
  local off, main = slots.offhand, slots.mainhand
  if off.now and main.now and main.now.level > off.now.level and twoHand(main.now.id) then off.now = nil end
  local worn, had = 0, 0
  for _, slot in ipairs(FA.GearCode.SLOTS) do
    local s = slots[slot]
    s.had = s.now and owned[s.now.id] and true or false
    if s.now then worn = worn + 1 end
    if s.had then had = had + 1 end
  end
  for _, p in ipairs(route.pieces) do
    local s = slots[p.slot]
    if s and s.now == p and not s.had then get[#get + 1] = p end
  end
  return { slots = slots, get = get, coming = coming, worn = worn, had = had }
end

--[[ ---- where a piece comes from, in the game's words ---- ]]
local scan   -- a tooltip of the addon's own, for the names the game only gives through one

local function ok(f, ...)
  local good, value = pcall(f, ...)
  if good and type(value) == "string" and value ~= "" then return value end
  return nil
end
--[[ A dungeon's name from its instance id. ]]
local function dungeonName(id)
  if GetRealZoneText then
    local name = ok(GetRealZoneText, id)
    if name then return name end
  end
  if C_Map and C_Map.GetAreaInfo then return ok(C_Map.GetAreaInfo, id) end
  return nil
end
--[[ A creature's name from its NPC id, through a tooltip: the game names a creature it has seen. ]]
local function npcName(id)
  return ok(function()
    scan = scan or CreateFrame("GameTooltip", "ForeverArmouryScan", UIParent, "GameTooltipTemplate")
    scan:SetOwner(UIParent, "ANCHOR_NONE")
    scan:SetHyperlink("unit:Creature-0-0-0-0-" .. id .. "-0000000000")
    local line = _G["ForeverArmouryScanTextLeft1"]
    local name = line and line:GetText()
    scan:Hide()
    return name
  end)
end
--[[ A quest's title from its id; asks the game to load it when it hasn't, and QUEST_DATA_LOAD_RESULT redraws. ]]
local function questTitle(id)
  if not C_QuestLog then return nil end
  local title = C_QuestLog.GetTitleForQuestID and ok(C_QuestLog.GetTitleForQuestID, id)
  if title then return title end
  if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
  return nil
end
Gear.NAMES = { dungeon = dungeonName, npc = npcName, quest = questTitle }

function Gear.SourceText(piece, names)
  names = names or Gear.NAMES
  local from = piece.from or {}
  if from[1] == "drop" then
    return (names.dungeon(from[2]) or ("dungeon " .. tostring(from[2]))) .. ": " .. (names.npc(from[3]) or ("NPC " .. tostring(from[3])))
  elseif from[1] == "quest" then
    return "Quest: " .. (names.quest(from[2]) or ("#" .. tostring(from[2])))
  end
  return "?"
end
