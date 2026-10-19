--[[ A build code as the site writes it (forever-armoury: public/content/build-code.js, #863), read and written here:

       FAT2-70170-warrior-Arms%20PvP-0a0a0a0b0b0b1c
       FAT <version> - <build> - <class> - <name> - <picks> { . <class> - <name> - <picks> }

     The build is the game client's build number the talents are from (GetBuildInfo's second answer, 70170 of
     1.60.1.70170): a talent that moves between the beta's builds changes what a cell means, so the site carries a
     code's picks to the trees it has by it (#1215). The addon writes the build it runs on and reads any: it applies a
     cell to the game's own trees, which are the truth in-game. The class is in lower case as the site names it
     (warrior, paladin, ...). The name has everything but letters and digits as %XX of its UTF-8 bytes, and is empty
     for a build with none. The picks are the build's points in the order spent, two characters a point: the tree
     (0-2) then the talent's cell, (tier - 1) * 4 + (column - 1), in base 36. Point n is taken at level n + 9. The
     cell is matched to a talent with the game's own tier and column (Builds.lua), so nothing here needs changing at
     a patch. Several builds join with ".".

     FA.Code.Read(text) reads every code in a pasted text, ignoring what's around it, and answers
       builds, nil, notes   builds: { { cls, name, picks, build }, ... }   notes: what was left out, to tell the person
       nil, error           error: why, in a sentence
     build is the game build the picks are from, or nil for a FAT1- code, from before the build was written in.
     FA.Code.Write(builds[, build]) is the code for a list of { cls, name, picks } from one game build: the game's own
     when build is nil, and a FAT1- code when it's false, for picks from a code from before the build was written in.
     FA.Code.GameBuild() is the build the game is on, as a code carries it.
     FA.Code.Points(picks) is a picks string as { { tab = 1..3, cell = 0..27 }, ... }, or nil for one that doesn't read.

     Each version has its own reader in READERS, so a code from an older site still reads when the format changes.
     Version 1 had no build: FAT1-<class>-<name>-<picks>{.<class>-<name>-<picks>}.

     Letters and digits are spelt out as A-Z, a-z and 0-9 rather than %w, which follows the locale: under a UTF-8 one
     it takes bytes above 127 for letters, and a name would pass them through unencoded. ]]

local _, FA = ...
local Code = {}
FA.Code = Code

Code.VERSION = 2
local CLASSES = { warrior = true, paladin = true, hunter = true, rogue = true, priest = true, shaman = true, mage = true, warlock = true, druid = true }
--[[ a code in a pasted text: its start, and everything after it that a code is made of ]]
local FIND = "FAT%d+%-[A-Za-z0-9%%%.%-]*"
local NOT_A_CODE = "That isn't a build code. A build code starts with FAT2- (or FAT1-, from before)."

local function clean(name) return (tostring(name or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")) end
local function encodeName(name) return (name:gsub("[^A-Za-z0-9]", function(c) return string.format("%%%02X", c:byte()) end)) end
--[[ The name as text, or nil when it isn't a name (a broken or cut-off %XX). ]]
local function decodeName(s)
  for pos in s:gmatch("()%%") do if not s:sub(pos + 1, pos + 2):match("^%x%x$") then return nil end end
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
--[[ The game's build number, as the code carries it: 0 outside the game (the tests stub GetBuildInfo). ]]
local function gameBuild()
  local _, build = GetBuildInfo()
  return tonumber(build) or 0
end
Code.GameBuild = gameBuild

function Code.Points(picks)
  if type(picks) ~= "string" or #picks % 2 ~= 0 or #picks > 102 then return nil end
  local out = {}
  for i = 1, #picks, 2 do
    local pair = picks:sub(i, i + 1)
    if not pair:match("^[0-2][0-9a-r]$") then return nil end
    out[#out + 1] = { tab = tonumber(pair:sub(1, 1)) + 1, cell = tonumber(pair:sub(2, 2), 36) }
  end
  return out
end

function Code.Write(builds, build)
  local parts = {}
  for i, b in ipairs(builds) do parts[i] = b.cls .. "-" .. encodeName(clean(b.name)) .. "-" .. (b.picks or "") end
  if build == false then return "FAT1-" .. table.concat(parts, ".") end
  return "FAT" .. Code.VERSION .. "-" .. (build or gameBuild()) .. "-" .. table.concat(parts, ".")
end

--[[ Version 1: <class>-<name>-<picks>{.<class>-<name>-<picks>}, with no build. Adds to out.builds and out.empty, each
     build with the game build it's from (nil for none), and answers why it stopped, or nil once it has read them all. ]]
local function read1(body, out, build)
  for seg in (body .. "."):gmatch("(.-)%.") do
    local n = #out.builds + out.empty + 1
    local cls, name, picks = seg:match("^([a-z]+)%-([A-Za-z0-9%%]*)%-([0-9a-r]*)$")
    if not cls or not CLASSES[cls] or not Code.Points(picks) then
      return "Build " .. n .. " of that code doesn't read. It may be cut off: copy the whole code again."
    end
    name = decodeName(name)
    if not name then return "The name of build " .. n .. " in that code is cut off or changed. Copy the whole code again." end
    if picks == "" then out.empty = out.empty + 1
    else out.builds[#out.builds + 1] = { cls = cls, name = clean(name), picks = picks, build = build } end
  end
  return nil
end
--[[ Version 2: <build>-, then as version 1. ]]
local function read2(body, out)
  local build, rest = body:match("^(%d+)%-(.*)$")
  if not build then return "That code doesn't read. It may be cut off: copy the whole code again." end
  return read1(rest, out, tonumber(build))
end
local READERS = { [1] = read1, [2] = read2 }

function Code.Read(text)
  text = tostring(text or "")
  if not text:find("%S") then return nil, "Paste a build code first." end
  local out, found = { builds = {}, notes = {}, empty = 0 }, 0
  for m in text:gmatch(FIND) do
    found = found + 1
    local version = tonumber(m:match("^FAT(%d+)"))
    local reader = READERS[version]
    if not reader then
      if version > Code.VERSION then return nil, "That code is from a newer version of Forever Armoury than this addon. Update the addon and try again." end
      return nil, NOT_A_CODE
    end
    --[[ a sentence's full stop after the code isn't part of it ]]
    local body = m:gsub("^FAT%d+%-", ""):gsub("%.+$", "")
    local err = reader(body, out)
    if err then return nil, err end
  end
  if found == 0 then return nil, NOT_A_CODE end
  if #out.builds == 0 then return nil, out.empty == 1 and "That build has no talent points." or "Those builds have no talent points." end
  if out.empty > 0 then out.notes[#out.notes + 1] = "Left out " .. (out.empty == 1 and "a build" or out.empty .. " builds") .. " with no talent points." end
  return out.builds, nil, out.notes
end
