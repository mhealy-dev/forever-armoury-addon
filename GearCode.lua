--[[ A gear route code, as the site's Copy for addon on the Best in slot window's Leveling plate will write it
     (docs/gear-route.md), read and written here:

       FAG1-warrior-0-alliance-18wxddd0Nr0Ul18izdgd0Nr0Un1aOreoqp4J...
       FAG <version> - <class> - <spec> - <side> - <pieces>

     The class is in lower case as the site names it (warrior, paladin, ...); the spec is the talent tree's index, 0 to
     2, as the site's route files have it; the side is alliance or horde. The pieces follow one after another with
     nothing between them, each a run of fields of fixed width in base 62 (0-9, then a-z, then A-Z; 0 pads on the left):

       item id   4 characters (up to 14,776,335: Forever's own items are numbered above 270000)
       level     1 character, 1 to 60, the level the piece is picked up at
       slot      1 letter, a to q: head neck shoulder back chest wrist hands waist legs feet finger1 finger2 trinket1
                 trinket2 mainhand offhand ranged (SLOTS)
       source    d, then the dungeon's id (3 characters) and the boss's NPC id (3 characters): a drop
                 q, then the quest's id (3 characters): a quest reward

     so a drop is 13 characters and a quest reward 10, and a route of the site's (37 to 59 pieces) is 460 to 730
     characters. The ids are the site's (public/data/gear.json: a dungeon's id is the instance's map id, Forever's own
     dungeons numbered above 2900). The code carries no item text: the game names an item from its id, and the panel
     shows the game's own tooltip.

     FA.GearCode.Read(text) reads every code in a pasted text, ignoring what's around it, and answers
       routes, nil, notes   routes: { { cls, spec, side, pieces }, ... }, each piece { id, level, slot, from }, from
                            being { "drop", dungeon, npc } or { "quest", quest }, as the site's route files have it
                            notes: what was cut, to tell the person
       nil, error           error: why, in a sentence
     FA.GearCode.Write(route) is the code for one { cls, spec, side, pieces }, or nil and why when a piece can't be
     written (an id too big for its field, a slot or source the code has no letter for).
     FA.GearCode.Find(text) says whether a text has a gear code in it at all, for the import box's wording.

     Each version has its own reader in READERS, so a code from an older site still reads when the format changes. ]]

local _, FA = ...
local GearCode = {}
FA.GearCode = GearCode

GearCode.VERSION = 1
GearCode.MAX_PIECES = 120
GearCode.SLOTS = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
  "finger1", "finger2", "trinket1", "trinket2", "mainhand", "offhand", "ranged" }
local CLASSES = { warrior = true, paladin = true, hunter = true, rogue = true, priest = true, shaman = true, mage = true, warlock = true, druid = true }
local SIDES = { alliance = true, horde = true }
local ID, LEVEL = 4, 1                                   -- the fields' widths
local KINDS = { d = { "drop", 3, 3 }, q = { "quest", 3 } }   -- a source's letter: its kind and its ids' widths
local LETTERS = { drop = "d", quest = "q" }
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local VALUE, SLOT_LETTER, LETTER_SLOT = {}, {}, {}
for i = 1, #DIGITS do VALUE[DIGITS:sub(i, i)] = i - 1 end
for i, slot in ipairs(GearCode.SLOTS) do
  local c = DIGITS:sub(10 + i, 10 + i)   -- a to q
  SLOT_LETTER[slot], LETTER_SLOT[c] = c, slot
end
--[[ a code in a pasted text: its start, and everything after it that a code is made of ]]
local FIND = "FAG%d+%-[A-Za-z0-9%%%.%-]*"
local NOT_A_CODE = "That isn't a gear code. A gear code starts with FAG1-."

--[[ A number in base 62, padded to a width; nil when it doesn't fit. ]]
local function encode(n, width)
  if type(n) ~= "number" or n < 0 or n ~= math.floor(n) then return nil end
  local s = ""
  repeat
    local d = n % 62
    s = DIGITS:sub(d + 1, d + 1) .. s
    n = math.floor(n / 62)
  until n == 0
  if #s > width then return nil end
  return string.rep("0", width - #s) .. s
end
local function decode(s)
  local n = 0
  for i = 1, #s do
    local v = VALUE[s:sub(i, i)]
    if not v then return nil end
    n = n * 62 + v
  end
  return n
end

function GearCode.Write(route)
  if not (route and CLASSES[route.cls] and SIDES[route.side]) then return nil, "That route has no class or side." end
  local spec = tonumber(route.spec)
  if not spec or spec < 0 or spec > 2 then return nil, "That route has no spec." end
  local parts = {}
  for i, p in ipairs(route.pieces or {}) do
    local from = p.from or {}
    local letter, kind = LETTERS[from[1]], KINDS[LETTERS[from[1]] or ""]
    local s = encode(tonumber(p.id) or -1, ID)
    local level = tonumber(p.level)
    if not s then return nil, "Piece " .. i .. " of that route has an item id the code can't carry." end
    if not level or level < 1 or level > 60 then return nil, "Piece " .. i .. " of that route has no level." end
    if not SLOT_LETTER[p.slot] then return nil, "Piece " .. i .. " of that route has a slot the code can't carry." end
    if not kind then return nil, "Piece " .. i .. " of that route comes from somewhere the code can't carry." end
    s = s .. encode(level, LEVEL) .. SLOT_LETTER[p.slot] .. letter
    for k = 2, #kind do
      local v = encode(tonumber(from[k]) or -1, kind[k])
      if not v then return nil, "Piece " .. i .. " of that route has a source id the code can't carry." end
      s = s .. v
    end
    parts[i] = s
  end
  return "FAG" .. GearCode.VERSION .. "-" .. route.cls .. "-" .. spec .. "-" .. route.side .. "-" .. table.concat(parts)
end

--[[ Version 1: <class>-<spec>-<side>-<pieces>. Adds the route to out.routes and answers why it stopped, or nil. ]]
local function read1(body, out)
  local n = #out.routes + 1
  local cls, spec, side, text = body:match("^([a-z]+)%-(%d)%-([a-z]+)%-?([0-9A-Za-z]*)$")
  if not cls or not CLASSES[cls] or not SIDES[side] or tonumber(spec) > 2 then
    return "Route " .. n .. " of that code doesn't read. It may be cut off: copy the whole code again."
  end
  if text == "" then return "Route " .. n .. " of that code has no pieces." end
  local pieces, pos, i = {}, 1, 0
  while pos <= #text do
    i = i + 1
    local head = text:sub(pos, pos + ID + LEVEL)   -- id, level, slot
    local kind = KINDS[text:sub(pos + ID + LEVEL + 1, pos + ID + LEVEL + 1)]
    local need = ID + LEVEL + 2
    for k = 2, #(kind or {}) do need = need + kind[k] end
    if #text - pos + 1 < need then
      return "Piece " .. i .. " of route " .. n .. " in that code is cut off: copy the whole code again."
    end
    local id, level, slot = decode(head:sub(1, ID)), decode(head:sub(ID + 1, ID + LEVEL)), LETTER_SLOT[head:sub(ID + LEVEL + 1)]
    if not kind or not slot or not id or id == 0 or not level or level < 1 or level > 60 then
      return "Piece " .. i .. " of route " .. n .. " in that code doesn't read. Copy the whole code again."
    end
    local from, at = { kind[1] }, pos + ID + LEVEL + 2
    for k = 2, #kind do
      from[k] = decode(text:sub(at, at + kind[k] - 1))
      at = at + kind[k]
    end
    pieces[#pieces + 1] = { id = id, level = level, slot = slot, from = from }
    pos = at
  end
  if #pieces > GearCode.MAX_PIECES then
    out.notes[#out.notes + 1] = "A route has " .. GearCode.MAX_PIECES .. " pieces at most, so the last " .. (#pieces - GearCode.MAX_PIECES) .. " of route " .. n .. " were left out."
    for k = #pieces, GearCode.MAX_PIECES + 1, -1 do pieces[k] = nil end
  end
  out.routes[n] = { cls = cls, spec = tonumber(spec), side = side, pieces = pieces }
  return nil
end
local READERS = { [1] = read1 }

function GearCode.Find(text) return tostring(text or ""):find("FAG%d+%-") ~= nil end

function GearCode.Read(text)
  text = tostring(text or "")
  if not text:find("%S") then return nil, "Paste a gear code first." end
  local out, found = { routes = {}, notes = {} }, 0
  for m in text:gmatch(FIND) do
    found = found + 1
    local version = tonumber(m:match("^FAG(%d+)"))
    local reader = READERS[version]
    if not reader then
      if version > GearCode.VERSION then return nil, "That code is from a newer version of Forever Armoury than this addon. Update the addon and try again." end
      return nil, NOT_A_CODE
    end
    --[[ a sentence's full stop or dash after the code isn't part of it; trimmed by hand, as a pattern anchored at
         the end tries every run of them in a long paste ]]
    local last = #m
    while last > 0 and m:sub(last, last):match("[%.%-]") do last = last - 1 end
    local body = m:sub(1, last):gsub("^FAG%d+%-", "")
    local err = reader(body, out)
    if err then return nil, err end
  end
  if found == 0 then return nil, NOT_A_CODE end
  return out.routes, nil, out.notes
end
