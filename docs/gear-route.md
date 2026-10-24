# The leveling gear route in the addon

The second part of the addon, after the level plan (forever-armoury#280): the site's leveling gear route for a class, spec and side, shown beside the character window, with the pieces to go and get at the character's level, whether it has them, and where each one comes from. BIS lists are meant to follow on the same panel later.

## What the site has

A route is `public/content/route/<class>.json` on the site: one per spec (the talent tree's index, 0 to 2) and side (`alliance` or `horde`), a list of pieces `{ id, level, slot, from }` in the order they are picked up. `from` is `["drop", dungeon, npc]` or `["quest", quest]`. The dungeon is the instance's map id as `public/data/gear.json` numbers it (Deadmines 36, Wailing Caverns 43; Forever's own dungeons are above 2900, The Hall of Thanes 3065), the npc the boss's id, the quest the quest's id. Every drop on the routes today is a dungeon boss. The rules for which piece is worn when are `public/content/route-fit.js`: the piece worn in a slot at a level is the last one picked up by then, and an off hand is put away by a two-handed main hand picked up after it. Item facts are `public/data/gear.json` and the sources' text `public/data/gear-sources.json`; the addon carries none of that, since the game names an item from its id.

The routes have 36 to 60 pieces (the Horde Survival hunter's is the longest), with 17 slots: head, neck, shoulder, back, chest, wrist, hands, waist, legs, feet, finger1, finger2, trinket1, trinket2, mainhand, offhand, ranged.

## The code

```
FAG1-warrior-0-alliance-18wxddd0Nr0Ul18izdgd0Nr0Un18j2did0Nr0Uo18ixdjd0Nr0Um1aOreoqp4J192Ehbd00H09r…
FAG <version> - <class> - <spec> - <side> - <pieces>
```

`FAG` is free: `FAT` is the talent build code and `FAR` the map's level route code. Version 1. The class is in lower case as the site names it, the spec is 0 to 2, the side is `alliance` or `horde`, and the code is made only of letters, digits, `.` and `-`, as the other codes are, so no chat app changes it. The pieces follow one after another with nothing between them, each a run of fixed-width fields in base 62 (`0-9`, then `a-z`, then `A-Z`, padded with `0` on the left):

| field | width | holds |
| --- | --- | --- |
| item id | 4 | up to 14,776,335 (Forever's items are numbered above 270,000; vanilla's below 25,000) |
| level | 1 | 1 to 60 |
| slot | 1 | a letter `a` to `q`, the 17 slots in the order above |
| source | 1 + ids | `d`, then the dungeon id (3) and the boss's NPC id (3); or `q`, then the quest id (3). A 3-character field holds up to 238,327. |

A drop is 13 characters and a quest reward 10. Over the 54 routes on the site today:

| | characters |
| --- | --- |
| shortest (Druid 0, Horde, 37 pieces) | 464 |
| median | 603 |
| longest (Rogue 1, Horde, 59 pieces) | 726 |

The import box has no letter limit (`SetMaxLetters(0)`) and full-class talent codes above 1,000 characters already pass through it, so a route code is well inside what it handles. One code is one route; a paste can hold several codes, and a build code (`FAT`) beside them: the import box reads both kinds from one paste.

The reader is versioned as the build code's is: each version has its own reader, a version above the addon's says to update the addon, and a trailing `.` or `-` from the sentence around a pasted code is dropped. The reader checks each piece's shape (a level 1 to 60, a slot letter it knows, a source letter it knows, an item id above 0) and stops with the piece's number when one is cut off or doesn't read. A route over 120 pieces keeps its first 120 and says so. A future source kind (a vendor, a craft) is a new letter in version 2; the reader for version 1 stays.

The code does not collide with the build code v3 work (forever-armoury#1540, #1541): it has its own prefix and its own readers, and the import box picks the reader by the prefix.

## What the site has to add

On the Best in slot window's Leveling plate (`public/assets/app/bis.js`, the route head beside the side chooser), a **Copy for addon** button, as the calculator's build menu and the character's Talent builds picker have for builds (#863). It writes the shown route (the class, spec and side chosen) with a new `public/content/gear-code.js`, a sibling of `build-code.js` with the same shape (`VERSION`, `write`, `read`, `find`, versioned `READERS`, the same letter-and-digit alphabet, `trimEnd` by hand). Base 62 is the alphabet above, in that order. The site repo is not changed by this work; this note and `GearCode.lua`'s header are the format's definition until `gear-code.js` exists, and `test/run.py` has a full Arms warrior route as the code it should produce (`WARRIOR_ARMS`), to check the site's writer against.

## The addon side

- `GearCode.lua` (`FA.GearCode`): `Read(text)` and `Write(route)`, as `BuildCode.lua`'s.
- `Data/Routes.lua` (`FA.RouteData`): the 54 routes of the site's `public/content/route/*.json` (nine classes, three specs, both sides), written by `tools/routes.py` (`python3 -I tools/routes.py`, from a site checkout; the header names the site commit and the date). A piece is numbers, `{ id, level, slot, kind, ... }`: the slot's place in `GearCode.SLOTS`, the kind 1 for a drop (then the dungeon and the boss) or 2 for a quest (then the quest). `FA.Gear.Shipped` turns one into the `{ id, level, slot, from }` the site's files and the pasted codes have. A pasted route for the same class, spec and side wins over the shipped one (`FA.Gear.Lookup`), and the panel says which it is showing. A later site script (forever-armoury#1568) is meant to write this file.
- `Gear.lua` (`FA.Gear`): the routes kept per account by class, one per spec and side (`FA.db.gear`), the character's route, and the plan. The side comes from `UnitFactionGroup`. The spec is the heaviest tree of the build the character follows (the tree with the most points in its picks); with no build, or a tie, the panel asks, and the choice is kept per character (`FA.char.gearSpec`). `Plan(route, level)` answers, per slot, the piece the route has there at this level and the next one, whether the piece is had (equipped, from `GetInventoryItemID` over the 19 slots, or in the bags, from `C_Container`), the pieces to get now, and the pieces coming. The off hand follows `route-fit.js`'s rule, with the game saying whether the main hand is two-handed (`GetItemInfo`'s equip location, `INVTYPE_2HWEAPON`); until the game has loaded the item, the off hand shows.
- `GearUI.lua`: the panel beside the character window (`CharacterFrame`), shown with it while the part is on: the route's spec and side, how many pieces of this level are had, then the pieces to get now and the ones coming, each as the game's item link with where it comes from under it. Each row is a button: hovering shows the game's tooltip for the item (`GameTooltip:SetItemByID`, else `SetHyperlink` with the link) to the right of the panel, with the source in full and the level the route has the piece at, and shift-click links the item in chat (`HandleModifiedItemClick`, else `ChatEdit_InsertLink`). The spec button cycles the spec; Import opens the shared box. It redraws as the character's gear, bags and level change and as the game loads names it was asked for.
- `ForeverArmoury.lua`: a `gear` switch in `FA.PARTS`, `/fa gear` (the character window with the panel) and `/fa gear on|off`.
- `TalentUI.lua`: the import box reads both codes from one paste and says what came of each.

## Where a piece comes from

The code carries ids, so the names come from the game: a dungeon's from `GetRealZoneText(instanceID)` (then `C_Map.GetAreaInfo`), a boss's through a tooltip of the addon's own set to `unit:Creature-0-0-0-0-<npc>-0000000000` (the game names a creature it has seen), a quest's from `C_QuestLog.GetTitleForQuestID` after `RequestLoadQuestByID`. Each falls back to the id (`dungeon 3065: NPC 3493`, `Quest: #1275`) when the game won't say.

## Still to check in the beta

- **`GetItemInfo` on Forever's item ids** (above 270,000) for an item the client hasn't cached: that it answers nil and then loads it after `C_Item.RequestLoadItemDataByID`, with `GET_ITEM_INFO_RECEIVED` or `ITEM_DATA_LOAD_RESULT`, and that the link and `GameTooltip:SetItemByID` then show the item.
- **`C_Container` in interface 16001**: `GetContainerNumSlots` and `GetContainerItemID` over bags 0 to `NUM_TOTAL_EQUIPPED_BAG_SLOTS`; the old `GetContainerItemID` is the fallback.
- **The names**: whether `GetRealZoneText` names Forever's own instance ids (3065, 2999, 2998, 2959) as it does Deadmines (36), whether the creature tooltip gives a boss's name on this client, and whether `C_QuestLog.GetTitleForQuestID` is there. If not, the code's next version can carry short source text, or the site can ship a names table with the route.
- **`CharacterFrame`'s size and where the panel sits** beside it, and `UnitFactionGroup` on the beta's races.
- **The build's heaviest tree as the spec**: whether it matches the site's spec for every class's routes (a hybrid build with points spread evenly asks instead).
