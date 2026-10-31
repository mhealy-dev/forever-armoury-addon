--[[ A Legacy plan code as the site writes it (forever-armoury: public/content/legacy-code.js, #1566), read and written here:

       FAL1-70425-Gatherer%27s%20Path-150000000051000000030001000
       FAL <version> - <build> - <name> - <ranks> { . <name> - <ranks> }

     The build is the game client's build number the Legacy perks' order is from (70425 of 1.60.1.70425, the last part
     of the site's LEGACY.build): a perk that moves between builds changes what a place in the ranks means, so a plan
     keeps the build its code came with, and Legacy.lua buys only the plans whose build is the one its table of perks
     is from. The name is written as a build's is (BuildCode.lua: everything but letters and digits is %XX of its UTF-8
     bytes, at most 40 characters, empty for a plan with none). The ranks are 27 characters, one a perk, each its rank
     in base 36 (0 to 5), tree by tree and in each tree in the order Legacy.lua lists the perks: Professions, then
     Adventure, then Resourcefulness. A perk the plan doesn't take is 0. Several plans join with ".", each after the
     first without its build: FAL1-<build>-<name>-<ranks>.<name>-<ranks>.

     FA.LegacyCode.Read(text) reads every code in a pasted text, ignoring what's around it, and answers
       plans, nil, notes   plans: { { name, ranks, build }, ... }   notes: what was cut, to tell the person
       nil, error          error: why, in a sentence
     build is the number the code was made on. A code from another build still reads; the ranks' shape is checked (27
     characters, base 36) and, for a code from the build Legacy.lua knows, each rank against the perk's most.
     FA.LegacyCode.Write(plans[, build]) is the code for a list of { name, ranks } from one build: Legacy.lua's own when
     build is nil. Answers nil and why for ranks that don't have the shape.
     FA.LegacyCode.Find(text) says whether a text has a Legacy code in it at all, for the import box's wording.

     Each version has its own reader in READERS, so a code from an older site still reads when the format changes. ]]

local _, FA = ...
local Code = FA.Code
local LegacyCode = {}
FA.LegacyCode = LegacyCode

LegacyCode.VERSION = 1
LegacyCode.PERKS = 27
local MAX_BUILD_DIGITS = 8
--[[ a code in a pasted text: its start, and everything after it that a code is made of ]]
local FIND = "FAL%d%d?%d?%-[A-Za-z0-9%%%.%-]*"
local NOT_A_CODE = "That isn't a Legacy plan code. A Legacy plan code starts with FAL1-."
local CUT_OFF = "That Legacy plan code doesn't read. It may be cut off: copy the whole code again."

--[[ Whether ranks has the shape of a plan's: PERKS characters of base 36 (digits and lower-case letters, as the site
     writes them). ]]
function LegacyCode.Shaped(ranks)
  return type(ranks) == "string" and #ranks == LegacyCode.PERKS and not ranks:find("[^0-9a-z]")
end

--[[ Why a plan from the build Legacy.lua knows can't have these ranks, or nil: a rank past what its perk takes. ]]
local function tooMany(ranks, build)
  local Legacy = FA.Legacy
  if not (Legacy and build == Legacy.BUILD) then return nil end
  for i, perk in ipairs(Legacy.PERKS) do
    if tonumber(ranks:sub(i, i), 36) > perk.max then return perk end
  end
  return nil
end

function LegacyCode.Write(plans, build)
  build = build or (FA.Legacy and FA.Legacy.BUILD) or 0
  local parts = {}
  for i, p in ipairs(plans) do
    if not LegacyCode.Shaped(p.ranks) then return nil, "Plan " .. i .. " doesn't have " .. LegacyCode.PERKS .. " ranks." end
    parts[i] = Code.EncodeName((Code.CutName(Code.CleanName(p.name)))) .. "-" .. p.ranks
  end
  return "FAL" .. LegacyCode.VERSION .. "-" .. build .. "-" .. table.concat(parts, ".")
end

--[[ Version 1: <build>-<name>-<ranks>{.<name>-<ranks>}. Adds to out.plans, each with the build it was made on, and
     answers why it stopped, or nil once it has read them all. ]]
local function read1(body, out)
  local build
  for seg in (body .. "."):gmatch("(.-)%.") do
    local n = #out.plans + 1
    local name, ranks
    if not build then
      local b
      b, name, ranks = seg:match("^(%d+)%-([^%-]*)%-([^%-]*)$")
      if not b or #b > MAX_BUILD_DIGITS then return CUT_OFF end
      build = tonumber(b)
    else
      name, ranks = seg:match("^([^%-]*)%-([^%-]*)$")
    end
    if not name or not LegacyCode.Shaped(ranks) then
      return "Plan " .. n .. " of that code doesn't read. It may be cut off, or made for other Legacy trees: copy the whole code again."
    end
    name = Code.DecodeName(name)
    if not name then return "The name of plan " .. n .. " in that code is cut off or changed. Copy the whole code again." end
    local cut
    name, cut = Code.CutName(Code.CleanName(name))
    if cut then
      name = Code.CleanName(name)
      out.notes[#out.notes + 1] = "The name of plan " .. n .. " was cut to " .. Code.MAX_NAME .. " characters."
    end
    local perk = tooMany(ranks, build)
    if perk then return "Plan " .. n .. " of that code has more ranks of " .. perk.name .. " than the perk takes (" .. perk.max .. "). Copy the whole code again." end
    out.plans[#out.plans + 1] = { name = name, ranks = ranks, build = build }
  end
  return nil
end
local READERS = { [1] = read1 }

function LegacyCode.Find(text)
  return tostring(text or ""):find("FAL%d+%-") ~= nil
end

function LegacyCode.Read(text)
  text = tostring(text or "")
  if not text:find("%S") then return nil, "Paste a Legacy plan code first." end
  local out, found = { plans = {}, notes = {} }, 0
  for m in text:gmatch(FIND) do
    found = found + 1
    local version = tonumber(m:match("^FAL(%d+)"))
    local reader = READERS[version]
    if not reader then
      if version > LegacyCode.VERSION then return nil, "That code is from a newer version of Forever Armoury than this addon. Update the addon and try again." end
      return nil, NOT_A_CODE
    end
    --[[ a sentence's full stop after the code isn't part of it, nor a dash, which no code ends with ]]
    local err = reader(Code.TrimEnd((m:gsub("^FAL%d+%-", "")), true), out)
    if err then return nil, err end
  end
  if found == 0 then return nil, NOT_A_CODE end
  return out.plans, nil, out.notes
end
