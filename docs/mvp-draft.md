# Forever Armoury addon: MVP draft

The addon's MVP, from the recorded meeting of 2026-10-21. Its issues are filed on mhealy-dev/forever-armoury as #1558 to #1583, in the [Addon MVP milestone](https://github.com/mhealy-dev/forever-armoury/milestone/15) with the existing #871, #872, #1536–#1541 and #1538, and in project 2 with Status, Priority and Size. Each issue's body says the version it ships in.

What it is built on:

- The meeting notes.
- Discovery issue #280 and its comments, and issues #871, #872, #1535–#1541 and #1552.
- Addon PR 3, this repo at `origin/main` (`f7a5923`), and the site repo at `origin/main` (`d5bee347`). Every size below comes from the real files there: raw KB, with gzip in brackets where it matters.
- Blizzard's UI source for the Forever client: the `forever` branch of Gethe/wow-ui-source at `172a387e3ab8`, "1.60.1 (70450)", 2026-10-16. API doc flags are from `Interface/AddOns/Blizzard_APIDocumentationGenerated/`.

Two corrections to what the brief assumed:

- **Devon's addon PR 3 is merged, not open.** It went in on 2026-10-20 as `f7a5923`. It adds Gear.lua, GearCode.lua, GearUI.lua, `/fa gear` and `docs/gear-route.md`, with a 0.4.0 changelog entry.
- **The site's writer is merged too.** Site issue #1552 is closed: site PR 1553 put Copy for addon on the Leveling plate. The local `main` in this checkout is three commits behind `origin/main`.

So the leveling gear part exists end to end, waiting only on beta checks and a release.

---

## 1. What the meeting decided

### Decisions

1. **The MVP is five parts in one addon.**
   - Talents, with Legacy.
   - Leveling gear guide.
   - Professions leveling, with a shopping list at the auction house.
   - Bestiary.
   - Dungeon and raid journal.

   The addon is meant to mirror the site ("the product suite is one-to-one"): a Leatrix-style bundle of quality-of-life parts, each with its own switch. That matches #280's "one addon with several parts, each of which you can turn on or off".
2. **The talent panel opens beside the talent window**, as it does today. It is to show the build's talents as a vertical bar of icons: the last few taken, then the ones coming, in the build's order.
3. **Hovering an icon in that bar lights the talent in the tree.**
4. **Builds come from the site by import**, as today with `FAT2-` codes.
5. **Talents include Legacy**: Legacy plans import from the site too.
6. **"Keep it simple to start"**: the first version shows the next talent and the player takes it. Click-to-select, and loading a whole build after a trainer reset, are things to iterate towards. See the flag below: the addon already has both, as Apply.
7. **No network.** Anything in the game is stored in the addon or pasted in. Devon's point that addons have no network access is correct, and #280 settled the same.
8. **Popular builds in the game is not MVP.** It becomes a discovery spike. On the site, popular builds can already be imported.
9. **The leveling guide in the addon is the gear guide**: "level 18 coming up, grab this weapon from this quest or this boss, run Deadmines soon". It follows the site's gear route. The spells-by-level side is #1541's trainer part.
10. **The addon should look and work like the site**, so moving from one to the other feels familiar.
11. **The professions part** is the site's profession guides for the character's professions. It comes with a shopping list opened from an icon on the auction house window, and it should count the reagents on your other characters so you don't over-buy.
12. **The bestiary** shows the site's pet information and where each beast is, "maybe not the map functionality".
13. **Spikes, not MVP:**
    - GPS / directions in the game
    - popular builds in the game
    - an in-game macro builder that's better than the game's own
14. **A server status gag** that says the servers are online.

### Open questions the meeting left

- Click-to-select: in or out of the first talents release? The meeting said both, minutes apart.
- How many past and upcoming talents the icon bar shows. Devon said "the last couple items".
- Whether the shopping list searches the auction house for you, as Auctioneer does, or only lists what to buy. Devon: "That sounds hard."
- Whether the bestiary has a map pin.
- Whether the journal covers raids as well as dungeons, and what it shows per boss.
- What "look and feel like the website" means inside the game's UI kit.
- How big the addon may get. The owner's worry, never given a number.
- The "dedicated lanes": who builds which part.

### Claims checked against the client's UI source

**"Is the whole automated talent point thing even allowed?" and "every action needs a button press".**

Checked: allowed, and the addon already does it.

- `C_Traits.PurchaseRank`, `C_Traits.CommitConfig` and `C_ClassTalents.CommitConfig` carry no `HasRestrictions` flag in `SharedTraitsDocumentation.lua` and `ClassTalentsDocumentation.lua`.
- Restricted functions, by contrast, are flagged: `C_ClassTalents.SwitchToLoadoutByIndex`, `C_AuctionHouse.PlaceBid`, `C_ChatInfo.SendChatMessage`.
- The talent window's own buttons call the same thing: `TalentButtonSpend` OnClick → `TalentFrameBaseMixin:PurchaseRank` → `C_Traits.PurchaseRank` (`Blizzard_SharedTalentFrame.lua:1773`). Its Apply button calls `C_ClassTalents.CommitConfig` (`Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua:1187`).

The model is "stage points, then Apply", and the commit is a short cast. It can fail in combat or mid-cast, which the addon already rolls back (#1535).

So "every action needs a button press" applies to specific protected actions: casting, targeting, buying and posting at the auction house, chat. Spending talent points isn't one of them.

The addon's **Apply** (#872, merged) already stages a build's points and commits after one confirm. After a trainer reset, Swap already says "open your talents and press Apply once". The meeting's "load build" is built.

What only the beta proves is #1536 check 3: purchases and the commit go through from an addon outside the window. #280 also notes that Talents Forever, another Forever addon, has a hands-free mode, which suggests the game allows it.

**Hover to highlight the talent.**

Checked: yes. `TalentFrameBaseMixin:GetTalentButtonByNodeID` (`Blizzard_SharedTalentFrame.lua:544`) finds a node's button, and the addon already uses it to light the next talent (`Talents.Button`, `TalentUI.lua` `lightTalent`).

Nothing in `Blizzard_PlayerSpells` or `Blizzard_SharedTalentUI` is protected or checks `InCombatLockdown`. Buttons are pooled, so the glow stays an overlay frame of our own, as it is now, never a field written onto Blizzard's button.

**Legacy builds.**

Checked: the Legacy trees are ordinary trait configs.

- `Constants.LegacyConsts` (`LegacyConstantsDocumentation.lua`) names the three trees: Professions 1187, Adventure 1188, Progression 1189. The Legacy points currency is 4225.
- The frame is `Blizzard_LegacySystem`, load on demand. `LegacyTreeTraitPanelMixin` inherits the talent frame base.
- It buys with the same `C_Traits.PurchaseRank` and commits with `C_Traits.CommitConfig`. Note: `C_Traits`, not `C_ClassTalents`.
- The micro menu reads the Adventure tree with no frame open (`MainMenuBarMicroButtonsOverrides.lua`), as the addon already does for Talented.

Two catches:

- **Each tree is its own config** (`GetConfigIDByTreeID(treeID)`), so a plan across all three trees is up to three commits.
- **Legacy points are account-wide and capped.** `LEGACY_POINTS_SEASONAL_CAP`: the site's data has a cap of 16.

**"Bagnon tracks character information: what mats are on your other characters".**

Checked: there is no API for another character's bags. `C_Container` is the logged-in character's only.

Bagnon and BagBrother do it by recording each character's bags and bank into SavedVariables when that character is played. So the addon only knows an alt's bags as of that alt's last login, and its bank as of the last time the bank was opened.

The Forever client does have an **account bank**:

- `Enum.BankType.Account`, and `Blizzard_UIPanels_Game/Camelot/BankFrame.lua` builds Account bank tabs.
- `C_Item.GetItemCount` takes `includeAccountBank`.

Whether the account bank's contents read away from a banker needs the beta.

**"Work like Auctioneer: a shopping list, search each item, results for all".**

Checked: possible, within limits.

- The client has the modern auction house: `Blizzard_AuctionHouseUI` and `C_AuctionHouse`. The classic `QueryAuctionItems` and `Blizzard_AuctionUI` aren't there.
- `SendSearchQuery`, `SendBrowseQuery` and `SearchForItemKeys` (many items in one call) carry no restriction flag. `SendSearchQuery` is "restricted to 100 calls per minute", with `AUCTION_HOUSE_THROTTLED_*` events.
- `PlaceBid`, `StartCommoditiesPurchase` and the post functions do carry `HasRestrictions`.

So one click can run the whole list's searches, paced on the throttle events, but each purchase is the player's own click. That's how Auctionator works on retail.

A missing flag isn't proof, so the first professions spike checks it in the beta. Favourites also exist (`SetFavoriteItem`, `SearchForFavorites`) and could stand in for a list.

**"GPS: a Fable-style glowing trail".**

Checked: **not possible as described.** No API draws in the 3D world: a search of every API doc for path, trail, decal or projected found nothing.

What an addon can do:

- **Lines and pins on the world map and minimap**: `MapCanvasMixin:AddDataProvider` and `AcquirePin` (`Blizzard_MapCanvas.lua:191, 280`), plus `Frame:CreateLine`.
- **Set the game's own user waypoint and super-track it**: `C_Map.SetUserWaypoint`, `C_SuperTrack.SetSuperTrackedUserWaypoint`. The game then shows its on-screen navigation marker and distance (`C_Navigation`, `InGameNavigationDocumentation.lua`).
- **Read known flight points anywhere**: `C_TaxiMap.GetTaxiNodesForMap` works "without considering the current flight master" and returns `isUndiscovered`. That covers "based on flight paths unlocked".

So "click where you want to go, get the route on the map, and an arrow to the next step" is feasible. A glowing line on the ground is not. The owner's 15% is about right for the trail and too low for the map version.

**"An API call from the addon to our website".**

Checked: none. The meeting reached this itself.

**Server status in the game.**

There's no realm-status API in the game client. `C_RealmList` is used only in the log-in screens (`Blizzard_GlueXML`); in game there's `GetRealmName` and `GetNetStats`. The site's status comes from a Worker cron (`src/status.js`).

So the gag is true by construction: if the addon is running, you're logged in.

---

## 2. Initiatives

Sizes: XS under a day, S one to two days, M three to five days, L one to two weeks, XL more than two weeks. Each assumes one person plus Claude sessions: the top model plans and reviews, cheaper models implement.

### Size of the data, for the owner's size worry

The shipped addon today (all `.lua` and the `.toc` on `origin/main`) is about **88 KB** of code and carries no data. Everything it names, it gets from the game. The game client names items, spells and zones from their ids: `GetItemInfo`, the spell API, `C_Map.GetAreaInfo`. It cannot name an NPC from its id unless it has seen it, so boss and beast names have to ship.

What each part would carry, from the real site files:

| Part | Site files (raw) | Addon carries | Or by code |
| --- | --- | --- | --- |
| Talents | talents.js 81 KB | nothing; reads the game | `FAT2-`, ≤102 chars a build |
| Legacy | legacy.js 3.5 KB | 27 node ids, under 1 KB | 27-char plan, as the site's link |
| Gear route | route/*.json 216 KB | nothing | `FAG1-`, 464–729 chars a route |
| BIS lists | bis/*.json 757 KB | 69 KB ids only (6 gz) | about 280 chars a list |
| Professions | professions.json 310 KB, prof-guides.js 30 KB | 12 KB guide steps; about 17 KB with gathering | not worth it |
| Bestiary | pets.json 59 KB, pins.js 183 KB | about 61 KB (20 gz) | no, reference data |
| Journal | raids.js 439 KB, journal.js 460 KB | about 30 KB (bosses, loot, abilities, names) | no, reference data |
| Directions | 52 road grids, 1,334 KB | about 60 KB road and flight graph | waypoints, about 10 chars a step |
| Popular builds | D1 query | about 17 KB snapshot, stale | a site button, see #1582 |
| Macros | classes/*.js 218 macros | 12 KB kits | one macro ≤255 chars |
| Server status | Worker + D1 | nothing; meaningless offline | — |

**The whole MVP's data is about 110 KB raw** (talents 0, Legacy 1, gear 0, professions 17, bestiary 61, journal 30). That takes the shipped addon from about 88 KB to about 200 KB. Popular builds, BIS and directions would add about 145 KB more if they ever shipped.

For scale, quest and map addons ship megabytes. The real costs are elsewhere:

- data that goes stale with each beta build
- a release for every data change
- memory held whether or not the part is used

All three are handled by **#1568** (data generated from the site, stamped with the game build) and **#1570** (a size budget in the release script). Load-on-demand data folders are an option if memory proves a problem (see the questions).

How the subsets were measured: by scripts over the site's JSON, keeping only ids, numbers and short names, and dropping tooltip prose, polylines and art.

### I1. Talents and Legacy

**Story.** As a player levelling a character, I see my build's talents in order beside the talent window: the ones I took, the next, and the ones coming. I can see where each is in the tree, and take the next with one click, for my class talents and my account's Legacy perks.

**What exists.**

- Import and export of `FAT2-` codes, the build list beside the window and the next talent lit (#871).
- Apply and Swap (#872).
- The seven fixes and release files (#1535, closed).
- The release script (#1537's tooling, merged).
- `nodeNameAndIcon` in `Talents.lua` already reads each talent's name and icon from the game, which the icon bar needs.
- Open: #1536 beta checks, #1537 the CurseForge project, #1538 the site's Addon page (parked), #1539 small fixes, #1540 FAT3 with the Talented rank, #1541 spells to buy and the trainer part.

**Data.** None shipped for class talents: the build comes by code and the trees from the game. Legacy needs a new code, `FAL1-`.

The site already has the 27-character rank string. `assets/app/legacy.js` `code()` writes each perk's rank in base 36, tree by tree in the data's order, and shares it as `/legacy/<code>`. The addon needs the 27 node ids in that order: from `public/data/legacy.js`, tagged with the client build it was read from (1.60.1.70425).

**Main risk.** Three:

- The beta disagreeing with the stubbed tests on the sort or the commit (#1536 checks 1 and 3).
- For Legacy, the account-wide cap and one commit per tree.
- The panel is already 210 × 410 with ten build rows. An icon bar needs room without hiding the build list: a design question, not a technical one.

**Size.** L for what the meeting adds: icon bar M, hover S, click to take M, Legacy M + S site. That's on top of the open issues.

### I2. Leveling gear guide

**Story.** As a player levelling, I'm told what gear the site's route has me wear at my level and what's coming: "level 18 coming up: this weapon from this quest, or from VanCleef in Deadmines: run Deadmines soon".

**What exists.** All of the first version:

- Addon PR 3 (merged): the `FAG1-` code, a panel beside the character window, pieces to get now and coming, owned or not, item links, sources named from the game, `/fa gear`. 65 tests.
- Site PR 1553 (merged, #1552): Copy for addon on the Best in slot window's Leveling plate.

Still open: the beta checks listed at the end of `docs/gear-route.md`:

- `GetItemInfo` on Forever's item ids above 270,000
- `C_Container` in this client
- whether the game names Forever's own dungeons, bosses and quests
- where the panel sits

**What the meeting adds.** The "coming up" nudge: a chat line or panel line when you level, and grouping upcoming drops by dungeon ("run Deadmines soon").

"Following what our gear and BIS guide on the website has" also raises BIS lists. The site's BIS lists are only twink PvP brackets today (levels 5, 10, 19, 30; 108 lists, no level-60 lists yet). They could ride the same panel by a code of about 280 characters. That's not MVP unless you say so.

**Data.** None shipped. The route comes by code (464–729 characters), items are named by the game, and `GetItemInfoInstant` can say whether a weapon is two-handed. Boss names are the weak spot: a creature the client hasn't seen has no name, and the fallback is "dungeon 3065: NPC 3493". The journal's boss-name table (I5) fixes that for free once it exists.

**Main risk.** Names of Forever's own instances, bosses and quests not resolving, and item data loading late for uncached items.

**Size.** S for what's left: beta checks and the nudge.

### I3. Professions leveling and shopping list

**Story.** As a crafter, beside my profession window I see the site's guide step for my skill. At the auction house, an icon opens a shopping list for my next steps that knows what I and my other characters already hold, and can search the auction house for all of it.

**What exists.** Nothing in the addon. The site has the guides and the engine:

- `content/prof-guides.js`: hand-written steps `[from, to, recipe, crafts, alts]`, choices, trainers and vendors.
- `assets/profroute.js`: the engine, cheapest option per choice, and `shop()` totals reagents.
- `data/professions.json`: 2,173 recipes with reagent item ids.

**Data.** Ship the guides as steps: `[from, to, product id, crafts, [[reagent id, count]…]]`. Run over all eight crafting guides for both factions, that's 290 steps, **12.3 KB** (2.1 gz). The four gathering guides add 4.6 KB, and choices and alternatives a little more.

The addon doesn't re-plan. It follows the site's computed route, so it doesn't need the 108 KB recipe table. Names come from the game by item id.

There are **no prices** on the site: the engine uses weight classes. Any price is the auction house's, live.

**Main risk.** The auction house part:

- searching a list is allowed but throttled (100 a minute)
- whether Forever's reagents are commodities or items changes which search call fits
- buying stays a click per purchase

Also: alt counts are only as fresh as each alt's last login. And knowing which professions the character has depends on `GetProfessions` / `GetProfessionInfo` answering on this client: Camelot is a mainline-family game type, so they should, but that's a beta check.

**Size.** XL as a whole. Guide panel M, shopping list M, alts' bags M, auction house search L, spike S.

### I4. Bestiary

**Story.** As a hunter, I can browse the site's tameable beasts in the game, by family, level, zone and ability taught, and see where each one is.

**What exists.** Nothing in the addon. On the site:

- `data/pets.json`: 17 families, 670 beasts `[npc, name, family, min level, max level, areas, rank, reactions]`, what each teaches, attack speeds.
- `data/pins.js` `PINS.tame`: 1,087 spawn points for 589 beasts, in world yards.

**Data.**

- About **61 KB** (20 gz): families, beasts, teach and speed 30 KB; names 10 KB; coordinates 21 KB.
- Coordinates should be converted to map x/y at export time. `C_Map.GetMapPosFromWorldPos` exists in the client too.
- The game can't help much: `UnitCreatureFamily` names a family on a target, but there's no "is tameable" or bestiary API (`C_StableInfo` is your own stable only). The list has to ship.

**Main risk.** Stale data across beta builds, and coordinates converted wrongly. Low technical risk.

**Size.** M. A tooltip add-on (S) is a cheap extra.

### I5. Dungeon and raid journal

**Story.** As a player heading into an instance, I can open its bosses, what each drops and the abilities to watch for, in the game, as on the site's journal.

**What exists.** Nothing in the addon. On the site:

- `data/raids.js`: 30 instances, 266 bosses with encounter id, NPC, loot, and 1,018 item tooltips.
- `data/journal.js`: bosses' ability spell ids and role tags, plus quests, things and spells.
- `data/dungeons.json`: the picker list.

The hand-written boss notes are **empty everywhere** today, so there's no prose to carry yet.

**Data.**

- About **30 KB**: `[encounter, npc, loot ids]` 17 KB, plus ability ids and roles to 22 KB, plus boss names (about 4 KB) and the instance list.
- Items and spells are named by the game, so the 384 KB of item tooltips stays on the site.

**Main risk.** Low. The question is overlap with the game's own Encounter Journal, if Forever has one: `Blizzard_EncounterJournal` should be checked on the `forever` branch. If it's there and populated, our journal's worth is the site's own data (ability roles, the route's picks) rather than a copy. Not checked in this draft.

**Size.** M.

### Deferred spikes

**#1581. GPS / directions** (spike S; build L if it goes ahead).

- **Story**: I pick a place on the world map and get the fastest way there: walk, my known flight paths, boats. A line on the map and the game's waypoint arrow guide me to each step.
- **Exists**: the site's directions (`assets/route-worker.js`, A* over 52 walking grids of about 11 million blocks, 1,334 KB of PNG, plus flights, boats, roads and danger costs). `waypoint.js` already writes TomTom `/way` lines.
- **Data**: the site's search can't ship. A road and flight graph is about 30 KB per continent (60 KB for both), plus 155 KB of polylines if the route is drawn along roads. Alternatively, the site computes the route and Copy for addon pastes the waypoints: 20 to 60 steps at about 10 characters each.
- **Risk**: the trail the meeting pictured is impossible (no 3D drawing API). What's possible is a map line, a minimap pin and the game's own user waypoint (`C_Map.SetUserWaypoint` + `C_SuperTrack`). A graph route in Lua will be worse than the site's grid search.
- **Recommendation**: spike the pasted-route version first. It's mostly site work the site already does.

**#1582. Popular builds in the game** (spike XS; build S).

- **Story**: I can pick one of the most popular builds for my class without leaving the game.
- **Exists**: `popularbuilds.js` → `GET /api/search?sort=popular` over D1 `talent_builds` by votes.
- **Data**: a snapshot of five per spec is about 17 KB of `FAT2-` codes. But it's frozen at release while votes move, and a new release ships for every refresh.
- **Recommendation**: instead, a **Copy top builds for addon** button on the site's popular builds page, writing a multi-build `FAT2-` paste the import box already reads. That's one site issue of size S and no addon change. The in-game list then shows them as ordinary imported builds.

**#1583. Macro builder in the game** (spike S; build L).

- **Story**: an easier macro editor in the game than the game's own.
- **Exists**: the site's builder (`assets/app/macros.js`, `macroscreen.js`) and 218 class kit macros (`content/classes/*.js`, 12 KB name and body).
- **Data**: the kits 12 KB; spell names from the game; icons from `GetMacroIcons`. A user's macro is at most 255 characters, so a code can carry it.
- **Client**: `CreateMacro` and `EditMacro` are plain globals the game's macro frame calls (`Blizzard_MacroIconSelector.lua:109, 112`), with no combat check in the frame. Retail blocks them in combat, so plan on out of combat only. `C_Macro.RunMacroText` is restricted. Limits are 120 account and 30 character macros (`MacroConstantsDocumentation.lua`).
- **Recommendation**: the spike answers whether "Copy for addon" from the site's builder, which creates the macro in the game, is enough, rather than building a second editor in Lua.

**X1. Server status gag** (XS). A line on the addon's home window: "Servers: online. You're in game." A tooltip says the site has the real status (foreverarmoury.app/status). No data, no API.

### Shared foundations (not a part, but the parts need them)

- **#1568**: the site exports the addon's data as generated Lua, stamped with the game build. Without it, professions, bestiary and journal are hand copies that rot.
- **#1569**: a home window with a tab per part, and a minimap button, styled like the site. Today `/fa` opens the talent window, and each part has its own slash command. With five parts, a home is what makes it "Leatrix-like", and it's where "look and feel like the website" lands.
- **#1570**: a size budget in `scripts/release.sh`.

---

## 3. Milestones

Each is a version shipped to CurseForge. The weeks are rough, counted from when the previous milestone ships, for two people working part time with Claude sessions. The beta's availability can move any of them.

### 0.3.0: Talents, the first release (in flight)

The build list, next talent, Apply and Swap, Talented read from the game.

- **Gate**: #1536 checks 1–3 answered in the beta (sort, can change, Apply outside the window) and #1537 done (the CurseForge project, its ID in the `.toc`, the `v0.3.0` tag).
- **About 1 week**, almost all the owner's beta time.
- **Caveat**: `origin/main` already carries the gear part under 0.4.0. Tagging `v0.3.0` from `main` today would ship gear too. Either tag 0.3.0 from `f66ae54` (before PR 3's merge), or accept gear in the first release and call it 0.3.0 with both. See the questions.

### 0.4.0: Leveling gear, and the talents' small fixes

The gear part as merged in PR 3, its beta checks, the level-up nudge, #1539's small fixes.

- **Gate**: the gear beta checks (#1560) pass, especially item info for ids above 270,000 and source names.
- **About 1–2 weeks.**

### 0.5.0: Talents, the meeting's panel, and Legacy

The icon bar of past and upcoming talents, hover to light, click to take, FAT3 with the Talented rank (#1540), Legacy plans by code.

- **Gate**: #1536 fully answered, and the 0.5 beta checks (#1565).
- **About 2–3 weeks.**
- #1541 (spells to buy and the trainer part) shares FAT3 with #1540, so it belongs here. It's the cut line if 0.5 runs long: it can ship alone as 0.5.1.

### 0.6.0: Foundations and the reference parts (bestiary, journal)

The site's data export, the home window and minimap button, the size budget, the bestiary, the journal.

- **Gate**: #1568's export runs from the site and its output loads in the game, and the size budget holds.
- **About 3 weeks.**

Why the reference parts before professions: they're pure data and UI, low risk, and they build the export and home window that professions then reuses. Professions carries the hard auction house work. If you'd rather lead with professions (the owner's "least favourite thing"), swap 0.6 and 0.7. The foundations still go first.

### 0.7.0: Professions and the shopping list

The guide panel beside the profession window, the shopping list, each character's bags and bank, the auction house search.

- **Gate**: spike #1574 answers how Forever's auction house searches behave. If searching is worse than the docs suggest, #1578 slips to 0.7.1 and the list ships without it.
- **About 3–4 weeks.**

### 1.0.0: The MVP complete

All five parts, the server status gag, a size and memory check, the README and the site's Addon page (#1538) brought up to all parts, the CurseForge description.

- **Gate**: every part's beta checks answered, and a week of the testers on 0.7.
- **About 1 week.**

**Total: about 11–15 weeks after 0.3.0 ships.**

The spikes (#1581–#1583) don't belong to a milestone. They're discovery issues a cheaper model can run any time. Anything they recommend building goes after 1.0, unless you pull it in.

---

## 4. Issues

Titles follow the repo's style ("Addon: …", "Site: …", "Build code v3: …"). All go on the site repo with `project: addon`, plus the part's own label where one exists: `project: bestiary`, `project: journal`, `project: professions`, `project: gear route`, `project: legacy`, `project: popular builds`, `project: flight paths`, `project: server status`, `area: macros`.

"Replaces / extends / depends on" are marked per issue. **Spike** marks discovery issues.

### 0.3.0: Talents, the first release

Existing issues, kept as they are:

- **#1536 Addon: beta checks before the first release** (open). Gates the release. No change.
- **#1537 Addon: release process and CurseForge listing** (open). One change: a checkbox for which commit `v0.3.0` is tagged from, given PR 3 is on `main` (see the 0.3.0 caveat).
- **#871, #872**: close with the release, as #1537 says.

New:

**#1558. Addon: decide what 0.3.0 ships, now that the gear part is on main** · XS · extends #1537

`main` has the leveling gear part (PR 3) under 0.4.0 in the changelog, and #1537 tags `v0.3.0` from `main`. Either tag from `f66ae54` so 0.3.0 is talents only, or fold the gear part into the first release. Decide, and make the changelog and the tag agree.

- [ ] Decide: talents-only from `f66ae54`, or both parts from `main`.
- [ ] If talents-only: check `scripts/release.sh`'s "on main" check (it refuses a tag that isn't `main`'s `HEAD`), and allow a release branch or tag from the commit.
- [ ] `CHANGELOG.md` matches what ships.

Depends on: nothing.
Done when: the tag's tree and the changelog's 0.3.0 entry list the same parts.

### 0.4.0: Leveling gear and the small fixes

Existing issues:

- **#1539 Addon: small fixes after the first release**. Kept. One addition: the build list's ten rows with no scroll (its second item) matters more once #1561 shares the panel. Do it here, before 0.5.

New:

**#1559. Addon: beta checks for the leveling gear part** · S · extends addon PR 3's `docs/gear-route.md`

PR 3 listed what only the game can answer; this makes them a checklist to answer in the beta, as #1536 does for talents. Each is a few minutes with 0.4's build installed.

- [ ] `GetItemInfo` on an uncached Forever item (id above 270,000) answers nil, then loads after `C_Item.RequestLoadItemDataByID` with `GET_ITEM_INFO_RECEIVED` or `ITEM_DATA_LOAD_RESULT`, and the link and tooltip then show it.
- [ ] `C_Container.GetContainerNumSlots` and `GetContainerItemID` over bags 0 to `NUM_TOTAL_EQUIPPED_BAG_SLOTS`.
- [ ] `GetRealZoneText` names Forever's own instances (3065, 2999, 2998, 2959) as it does Deadmines (36). The creature tooltip names a boss the character hasn't seen. `C_QuestLog.GetTitleForQuestID` exists.
- [ ] The panel's place beside `CharacterFrame` (it's taller than the window), and `UnitFactionGroup` on the beta's races.
- [ ] The heaviest tree of a build picks the site's spec for a hybrid build.

Depends on: #1537 (a build on CurseForge to test).
Done when: each box has what the game said, and anything failing has its own issue (#1561's names table is the likely one).

**#1560. Addon: "level N coming up" for the gear route** · S · extends PR 3

The meeting's "level 18 coming up: this is a weapon you should look to grab; run Deadmines soon". On a level-up, say in chat the next pieces due within a few levels, with where each comes from. Group the coming drops by dungeon on the panel, so "run Deadmines soon" reads at a glance.

- [ ] On `PLAYER_LEVEL_UP`, one chat line for pieces due in the next three levels (item link, level, quest or dungeon and boss), behind a setting that's on by default.
- [ ] The panel's "coming" list groups drops by dungeon, with the level range they cover.
- [ ] Tests over the Arms warrior fixture: the line at levels 17 and 18, the grouping.

Depends on: #1559 (names that read).
Done when: levelling from 17 to 18 on the beta says the right pieces, with names, and the panel groups Deadmines' drops.

**#1561. Addon: names for bosses and quests the game won't give** · S · conditional on #1559

Only if #1559 finds the game won't name Forever's own bosses or quests. Ship a small names table from the site (boss names about 4 KB, the routes' quests fewer than 300 names) and use it before the id fallback. Once #1568 and #1573 exist, this is their boss-name table; before then, a generated file.

- [ ] A generated `Data/Names.lua`: NPC id → name for bosses on the routes, quest id → title for quests on the routes.
- [ ] `Gear.lua` uses it when the game has no name.

Depends on: #1559.
Done when: no gear panel line shows a bare id on the beta.

### 0.5.0: Talents, the meeting's panel, and Legacy

Existing issues, kept as they are:

- **#1540 Build code v3: the Talented rank**. No change.
- **#1541 Build code v3: spells to buy from the level plan, and the addon's trainer part**. No change. The cut line for 0.5: it can ship as 0.5.1.
- **#1536**: checks 4–7 (unspent count, dual spec, trainer reset, trainer names) are answered by now. #1541 depends on check 7.

New:

**#1562. Addon: the build's talents as a column of icons beside the talent window** · M · extends #871's panel

The meeting's "vertical icon bar of your talents": the build's talents in its order, as icons. Show the last few taken, the next one marked, and the ones coming, each with the level it's due. Names and icons come from the game (`nodeNameAndIcon` in `Talents.lua`). The panel today is a status line, Apply and ten build rows in 210 × 410, so this needs a layout decision first.

- [ ] A design for where the column goes: a strip between the window and the panel, or the panel's top half with the build list below and scrolling (#1539's scroll). Settle it with a mock before building.
- [ ] The column shows the last 3 taken, the next (marked, with its level), and the next 5 coming. A setting picks how many of each.
- [ ] A talent with ranks shows once per rank, with "2/3" on the icon, since the build's order spends ranks one at a time.
- [ ] It redraws as points are spent, the active build changes, or the spec swaps, through the existing `FA.Refresh`.
- [ ] Tests against the frame mock: the column at 0 points, mid-build, a finished build, and a build that's off its order (a spent point not in the build).

Depends on: #1539 (the build list's scroll, if the column shares the panel).
Done when: on the beta, the column matches the site's build order for a level 25 character, and spending a point moves it on.

**#1563. Addon: hovering a talent in the column lights it in the tree** · S · extends #1562

"When you hover over the talent on the add-on, it highlights the talent on the talent tree". Hovering an icon in #1562's column lights that talent's button in the window, with the same glow the next talent has but in another colour, and shows the game's own tooltip for it.

- [ ] `OnEnter` on each icon lights `Talents.Button(t)`'s overlay; `OnLeave` puts back the next talent's glow.
- [ ] The tooltip: the talent's spell tooltip (`GameTooltip:SetSpellByID` from the trait definition), plus "Level N" and "Rank r of m".
- [ ] The glow is an overlay frame of the addon's own, never a field on Blizzard's pooled button (the UI source pools them: `Blizzard_SharedTalentFrame.lua`).
- [ ] A test that hovering and leaving restores the next-talent glow.

Depends on: #1562.
Done when: on the beta, hovering any icon lights the right button in each of the three trees.

**#1564. Addon: click a talent in the column to take it** · M · extends #872 (Apply); depends on a decision

"If you click on it, it auto-selects the talent for you if you have talent points available". Clicking the next talent's icon, with a point to spend, takes that one point. It's Apply for one point, so it goes through the same `Talents.Learn`, all or none, rollback on failure.

The UI source shows nothing stops it (see the draft's section 1). The open choice is what the click does:

- **(a) Stage only.** `C_Traits.PurchaseRank`, so the talent window shows it pending and the window's own Apply button commits. The player's last press is the game's button.
- **(b) Stage and commit.** One click, one short cast, as the addon's Apply does.

- [ ] Decide (a) or (b).
- [ ] Only the next talent's icon is clickable, and only with an unspent point, out of combat, with no changes of the window's own waiting (Apply's existing refusals and their reasons as the tooltip).
- [ ] Shift-click on the next icon is Apply for every point due, with the existing confirm. Or leave Apply as a button only. Decide with (a)/(b).
- [ ] Tests: the click with a point, without, in combat, with the window's own staged changes, and a refused purchase rolling back.

Depends on: #1562, #1536 check 3 (purchases from an addon outside the window).
Done when: on the beta, one click takes the next talent, and the column and tree move on.

**#1565. Addon: beta checks for the talent column and Legacy** · S

What #1562–#1564 and #1567's Legacy part need from the game, answered in the beta before 0.5 ships.

- [ ] Clicking an icon (#1564) stages, and commits under (b), with the talent window open and closed.
- [ ] `C_Traits.GetConfigIDByTreeID` for 1187, 1188 and 1189 returns a config each, and `GetNodeInfo` reads ranks on all three with the Legacy window closed.
- [ ] `C_Traits.PurchaseRank` into a Legacy tree from an addon, then `C_Traits.CommitConfig`: goes through, and what the cap does when a purchase would pass it (refused, or an error).
- [ ] The Legacy points available: `C_Traits.GetTreeCurrencyInfo` on each tree, or currency 4225.
- [ ] The Legacy window's frame (`LegacySystemFrame`) and where a panel sits beside it.

Depends on: #1562, #1564, #1566.
Done when: each box has the game's answer, and #1567 is changed to fit any surprise.

**#1566. Site: a Legacy plan code, and Copy for addon on the Legacy tab** · S · site; new; label `project: legacy`

The Legacy tab already writes a plan as 27 characters (`assets/app/legacy.js` `code()`: each perk's rank in base 36, tree by tree in `data/legacy.js`'s order) and shares it as `/legacy/<code>`. The addon needs the same with a prefix, the client build the perk order came from, and a name.

- [ ] `public/content/legacy-code.js`, a sibling of `build-code.js`: `FAL1-<build>-<name>-<ranks>`, versioned readers, `find` in a paste.
- [ ] Copy for addon on the Legacy tab's plan bar, beside Share, with the calculator's copy feedback.
- [ ] Import on the Legacy tab reads a `FAL1-` code back.
- [ ] `test/legacy-code.test.cjs`, and a changelog entry.

Depends on: nothing.
Done when: a plan copied from the Legacy tab reads back on the site as the same ranks, and the addon's fixture matches.

**#1567. Addon: Legacy plans beside the Legacy window** · M · new; extends #872's Apply

"Talents would include legacy, so you can import legacy talent builds as well". Import `FAL1-` codes through the same box. Keep them per account, since Legacy is account-wide. Beside the Legacy window, show the plan against the account's ranks: the perks still to buy, the next one lit, an Apply that buys them.

- [ ] `LegacyCode.lua` reads and writes `FAL1-`; the import box reads it beside `FAT` and `FAG`.
- [ ] The 27 perks' node ids in the site's order, in a small table stamped with the client build (`1.60.1.70425`). A code from another build says so rather than buying the wrong perk.
- [ ] A panel beside `LegacySystemFrame` (`Blizzard_LegacySystem`, load on demand): the plan, ranks had and wanted per perk, the next perk lit on the tree with the same overlay as talents.
- [ ] Apply: `C_Traits.PurchaseRank` on each tree's config (`GetConfigIDByTreeID`), then `C_Traits.CommitConfig` per tree, all or none per tree, up to the points available and the cap. The confirm names the perks.
- [ ] `/fa legacy`, and a `legacy` switch in `FA.PARTS`.
- [ ] Tests against a stub of three trait configs: a plan from nothing, a partial plan, the cap, a refused purchase rolling back.

Depends on: #1566 (site code), #1565 (beta checks).
Done when: a plan copied from the site's Legacy tab imports, shows the right next perk, and Apply buys it on the beta.

### 0.6.0: Foundations, bestiary and journal

**#1568. Site: export the addon's data tables** · M · site; new; label `project: game data`

Professions, the bestiary and the journal ship data in the addon. That data has to come from the site's files, by a script, stamped with the client build, so a beta build that changes a beast or a drop is one command away. The site already generates files this way (`tools/build-legacy.py`).

- [ ] `tools/addon-data.mjs` writes Lua files into a given addon checkout, `Data/Bestiary.lua`, `Data/Journal.lua`, `Data/Professions.lua`, each with the site commit and the client build it came from.
- [ ] Only ids, numbers and short names: no tooltip prose, no polylines. Item and spell names come from the game.
- [ ] World-yard coordinates (pins.js) converted to each zone's map x/y here, not in the game.
- [ ] Prints each file's size. A test fails if a table loses records against the site's counts (670 beasts, 266 bosses, 290 guide steps).
- [ ] A README section in the addon repo: how to regenerate.

Depends on: nothing.
Done when: one command writes the three files from `origin/main`, and they load with `luac -p` / the test harness.

**#1569. Addon: a Forever Armoury window with a tab for each part** · M · new

With five parts, the addon needs a home: one window, opened by `/fa` and a minimap button, with a tab per part in the site's order and words. Each part's switch moves there. This is where "look and feel like the website" is made concrete: the site's part names and icons, its colours for headings and marks within the game's frame kit, the same words for the same things (Copy for addon, Import, the part names).

- [ ] A window with tabs: Talents, Legacy, Gear, Professions, Bestiary, Journal, Settings. A part that's off has no tab.
- [ ] `/fa` opens it, and `/fa talents` keeps today's behaviour (the talent window with the panel).
- [ ] A minimap button (drag to move, a setting to hide), with no library dependency unless you choose LibDBIcon. See the questions.
- [ ] A style note in `docs/`: the site's colours mapped to the game's font objects and backdrop, the icons each part uses, the words.
- [ ] The Talents and Gear tabs show the build list and the route summary, with a button to the game window where the panel lives.

Depends on: #1568 only for the tabs that need data. The window itself depends on nothing.
Done when: a new player can find every part from the minimap button without a slash command.

**#1570. Addon: a size budget in the release script** · XS · extends #1537's `scripts/release.sh`

The owner's size worry, as a check. The release script prints the zip's size and each file's, and refuses a release over a budget set in the script.

- [ ] `scripts/release.sh` lists each `.lua` file's size and the total, and fails over the budget.
- [ ] The budget starts at 300 KB for the shipped `.lua` (today about 88 KB; the MVP's data adds about 110 KB).
- [ ] `/fa debug memory` prints `GetAddOnMemoryUsage` after a full collect, for the beta.

Depends on: nothing.
Done when: a release over budget stops with the file to blame.

**#1571. Addon: the bestiary** · M · new; label `project: bestiary`

"As a hunter I open the bestiary and see the same pet information as on the site and where to find them." A tab listing the site's 670 tameable beasts, filtered by family, level range, zone and the ability they teach. A beast shows its family, levels, zones, what it teaches at which rank, its attack speed, and where it spawns. A map pin is a choice, not the default, as the meeting said.

- [ ] The list and filters from `Data/Bestiary.lua` (#1568): family, level, zone, ability taught. "Near me" sorts by the player's zone.
- [ ] A beast's card: name, family, level range, rank (elite or rare), zones, abilities taught and their ranks, speed.
- [ ] Spawn points as a list of zone and coordinates, and a "Set waypoint" button per point (`C_Map.SetUserWaypoint` + `C_SuperTrack`). That's the game's own pin and arrow, with no map drawing of ours.
- [ ] The tab only shows for hunters, unless a setting shows it for every class.
- [ ] Tests over the data: every beast has a family the families table knows; every pin's map converts.

Depends on: #1568, #1569.
Done when: on the beta, a level 30 hunter finds the beasts teaching Bite 4 near them, and a waypoint goes to one.

**#1572. Addon: what a beast teaches, in its tooltip** · S · extends #1571; optional

The cheapest in-game win of the bestiary: hovering a tameable beast in the world adds "Tameable: Bite 4, Dash 2" to its tooltip, from the same table.

- [ ] A tooltip hook on units: an NPC id from the unit's GUID, looked up in the bestiary.
- [ ] Hunters only, behind the bestiary's switch.

Depends on: #1571.
Done when: hovering a tameable beast on the beta shows what it teaches.

**#1573. Addon: the dungeon and raid journal** · M · new; label `project: journal`

"An in-game reference for dungeons and raids." A tab listing the site's instances. Each instance lists its bosses. Each boss shows its loot as the game's item links, and its abilities as the game's spell links with the site's role tags (tank, healer, everyone). There's no prose yet: the site's boss notes are empty, so the tab says where the site has more.

- [ ] Instances and bosses from `Data/Journal.lua` (#1568): instance, level range, bosses (encounter id, NPC id, name), loot item ids, ability spell ids and role tags.
- [ ] Loot as item links: hover shows the game's tooltip, shift-click links it. Items load through `C_Item.RequestLoadItemDataByID` as the gear part does.
- [ ] Loot the character's gear route wants (I2) is marked, so "run Deadmines soon" and the journal agree.
- [ ] Opens on the instance you're in (`GetInstanceInfo`'s instance id), and from the gear panel's source line.
- [ ] Before building: check whether the `forever` branch has `Blizzard_EncounterJournal` and whether it's populated for Forever's own dungeons. If it is, say how ours differs, in the issue.

Depends on: #1568, #1569.
Done when: on the beta, inside Deadmines, `/fa` opens Deadmines' bosses with every loot item named.

### 0.7.0: Professions and the shopping list

**#1574. Spike: the Forever auction house from an addon** · S · **spike**

Before building the auction house search, find out how Forever's auction house behaves, in the beta, with a throwaway script.

- [ ] The frame (`AuctionHouseFrame`, `Blizzard_AuctionHouseUI`) and where an icon can sit on it.
- [ ] Whether common reagents (Linen Cloth, Copper Bar) are commodities (`C_AuctionHouse.GetItemCommodityStatus`) or items. That decides `SendSearchQuery` or `SearchForItemKeys` per reagent.
- [ ] A queue of 20 searches from one click: do they all answer, at what pace, and what do `AUCTION_HOUSE_THROTTLED_MESSAGE_*` say?
- [ ] That none of them needs a hardware event on this client (the docs flag none; prove it).
- [ ] What `SetFavoriteItem` / `SearchForFavorites` do, as a cheaper alternative to our own search.

Depends on: nothing (beta access).
Done when: a comment answers each box, with a recommendation for #1578's approach.

**#1575. Addon: the profession guide beside the profession window** · M · new; label `project: professions`

"Professions leveling would be cool." Beside the profession window, show the site's guide for that profession at the character's skill: the current step (recipe, how many to craft, from and to skill), the next steps, and where the trainer or recipe vendor is. A step whose recipe the character doesn't know says where to learn it.

- [ ] Read the character's professions and skill (`GetProfessions` / `GetProfessionInfo`). If this client answers otherwise, find out first in the beta.
- [ ] The guide's steps from `Data/Professions.lua` (#1568), for the character's faction, as computed by the site's engine. The addon follows, it doesn't re-plan.
- [ ] A panel beside the profession window (find its frame name on the `forever` branch): the current step lit, the next three, crafts left at this step.
- [ ] Recipe and product names from the game by item id.
- [ ] A tab in #1569's window listing every profession's guide, not only the character's.
- [ ] Tests over the data: the steps for every guide are continuous from 1 to the guide's tested cap.

Depends on: #1568, #1569.
Done when: on the beta, a tailor at 75 sees the site's step for 75.

**#1576. Addon: remember each character's bags and bank** · M · new

"Like Bagnon tracks character information: what mats are on your other characters." The game has no API for another character's bags (section 1), so the addon records each character's bags on login and as they change, and their bank when it's opened. The shopping list then counts them.

- [ ] Per character (realm and name) in `ForeverArmouryDB`: item id → count, for bags (on `BAG_UPDATE_DELAYED`), bank (on the bank frame opening), mail (on the mailbox opening, optional), with the time recorded.
- [ ] The account bank, read with `C_Item.GetItemCount(id, …, includeAccountBank)` or the account bank tabs. Check in the beta what reads away from a banker.
- [ ] "On your characters": a function the shopping list calls, with each character's count and how old it is.
- [ ] A setting to forget a character, and a note in the README that it all stays in the game's own saved file.
- [ ] Tests for counting and merging over two characters.

Depends on: #1569 (its settings).
Done when: logging an alt, then a main, the main sees the alt's Linen Cloth.

**#1577. Addon: the shopping list for a profession's next steps** · M · new

From #1575's guide, the reagents for the next steps you choose (by default up to the next trainer cap): what you need, minus what this character and your others hold (#1576), as a list with counts. It opens from an icon on the auction house window and from the profession panel.

- [ ] Pick a range: "to 150", or ticking steps. Reagents = crafts × each recipe's reagents, minus held, here and on alts (each alt line marked "on Alt, 2 days ago").
- [ ] Vendor-sold reagents (thread, dyes) marked "from a vendor", from the site's weight classes, so they aren't searched at the auction house.
- [ ] An icon on the auction house frame opens it (placed as #1574 found).
- [ ] The list is kept per character until the steps are done.

Depends on: #1575, #1576, #1574 (the icon's place).
Done when: on the beta, a tailor at 50 opens the auction house and sees how much Linen Cloth to buy for 50 to 125, counting the cloth on their alt.

**#1578. Addon: search the auction house for the whole shopping list** · L · new; depends on spike #1574

Devon's "work like Auctioneer: look for each one and give me results for all of them". One click on the list runs a search per reagent, paced to the game's throttle, and shows the cheapest price and quantity for each. Buying stays the auction house's own click for each purchase: `PlaceBid` and `StartCommoditiesPurchase` are restricted functions in the client's docs, so an addon can't buy for you.

- [ ] A Search all button: queues the list's searches (`SearchForItemKeys` or `SendSearchQuery`, per #1574), at most 100 a minute, waiting on the throttle events.
- [ ] Results per reagent: cheapest unit price, quantity at that price, total for what you need.
- [ ] Clicking a result selects it in the auction house frame, so the player's own click buys it.
- [ ] Stops cleanly when the auction house closes mid-queue.
- [ ] Tests against a stub of `C_AuctionHouse`: queueing, throttling, closing mid-run.

Depends on: #1574, #1577.
Done when: on the beta, Search all for a ten-reagent list fills in a price for each, in under a minute.

### 1.0.0: The MVP complete

**#1579. Addon: the server status line** · XS · new; label `project: server status`; the gag

"Servers are online." On the home window (#1569), a line: "Servers: online. You're in game." A tooltip links the site's status page for the real thing. There's no API for realm status in the game, and if the addon is running you're connected, so the line is always true.

- [ ] The line and tooltip.
- [ ] Nothing else: no timers, no network.

Depends on: #1569.
Done when: it says online.

**#1580. Addon: 1.0 release: every part's checks, the README, the site's Addon page** · S · extends #1538

The MVP is out when every part's beta checks are answered, the README and the CurseForge description describe every part, and the site's Addon page (#1538) does too.

- [ ] Every beta-check issue closed: #1536, #1559, #1565, #1574, and #1571/#1573/#1575's "on the beta" lines.
- [ ] #1570's budget holds; `/fa debug memory` recorded in the release notes.
- [ ] README, CurseForge description and #1538's page cover all five parts and the home window.
- [ ] `CHANGELOG.md` 1.0.0.

Depends on: everything above in 0.4–0.7, and #1538.
Done when: `v1.0.0` is on CurseForge and the site's Addon page links it.

### Spikes, any time

**#1581. Spike: directions in the game** · S · **spike**; label `project: flight paths`

The meeting's GPS, scoped to what the client allows: no trail in the 3D world (there's no API for drawing in the world), but a line on the world map, the minimap, and the game's own waypoint arrow are possible. Find out which way gets a route into the game best.

- [ ] Route A, pasted: the site's directions (`route-worker.js`) write the route's waypoints as a code (about 10 characters a step, 20–60 steps). The addon sets each as the user waypoint in turn (`C_Map.SetUserWaypoint`, `C_SuperTrack`), advancing as you arrive, and draws the line on the world map (`AddDataProvider`, `CreateLine`).
- [ ] Route B, in the addon: a road and flight graph (about 30 KB a continent, from `roads.js` `ROADS.net` and the flight edges), searched in Lua, with known flight points from `C_TaxiMap.GetTaxiNodesForMap`'s `isUndiscovered`. Compare one route's answer with the site's.
- [ ] Whether `C_Map.GetPlayerMapPosition` works everywhere the route goes, and whether `TakeTaxiNode` is callable from an addon at a flight master (undocumented, so check in the beta).
- [ ] A recommendation, with the size of each route.

Depends on: nothing.
Done when: a comment recommends A, B or neither, with one route tried in the beta.

**#1582. Spike: popular builds in the game** · XS · **spike**; label `project: popular builds`

An addon can't ask the site for popular builds, and a snapshot in the addon (about 17 KB for five builds per spec) is stale the day after a release. Check the cheaper alternative and close the spike with an issue for it.

- [ ] Confirm the import box reads a paste of 15 to 30 `FAT2-` codes at once (a class's top builds, about 1.9 KB).
- [ ] Propose: a **Copy top builds for addon** button on the site's popular builds page, writing the class's top builds as one paste. That's a site issue of size S.
- [ ] Decide whether the addon marks builds that came from the popular list (a flag in the code, or not).

Depends on: nothing.
Done when: the site issue is filed or the idea is dropped, in a comment.

**#1583. Spike: a macro builder in the game** · S · **spike**; label `area: macros`

"A macro builder in game that's more intuitive than the included one." The site has a builder and 218 class kit macros. Find out whether bringing the site's macros into the game (Copy for addon, then the addon creates them) is enough, or whether an editor in Lua is worth building.

- [ ] In the beta: `CreateMacro` and `EditMacro` from an addon out of combat, and in combat (expect refused). The 120 account / 30 character limits.
- [ ] A macro code from the site's builder: one or many macros (name, icon, body ≤255 characters), what it costs in characters.
- [ ] The class kits (12 KB) as a shipped list to pick from, against a code.
- [ ] A recommendation.

Depends on: nothing.
Done when: a comment recommends a code, a shipped kit, an editor, or none.

### Size summary

| Milestone | Issues | Sizes |
| --- | --- | --- |
| 0.3.0 | #1536, #1537, #1558 | existing + XS |
| 0.4.0 | #1539, #1559, #1560, #1561 (if needed) | existing + S, S, S |
| 0.5.0 | #1540, #1541, #1562–#1567 | existing + M, S, M, S, S, M |
| 0.6.0 | #1568, #1569, #1570, #1571, #1572, #1573 | M, M, XS, M, S, M |
| 0.7.0 | #1574–#1578 | S, M, M, M, L |
| 1.0.0 | #1579, #1580, #1538 | XS, S, existing |
| any time | #1581, #1582, #1583 | S, XS, S |

Which can run on cheaper models with a short brief: the beta-check lists (#1559, #1565, #1574's script), #1568's export, #1570, #1571, #1572, #1579, #1573 and the spikes' research. Which need the top model for design: #1562's layout, #1564's decision, #1567's Legacy Apply across three configs, #1569's home window and style, #1578's queue.

---

## 5. Questions for the owner and Devon

1. **What does 0.3.0 ship?** The gear part is already on `main`. Tag talents-only from `f66ae54`, or both parts? (#1558)
2. **Click to take a talent: stage only, or stage and commit?**
   - (a) leaves the game's own Apply button as the last press.
   - (b) is one click, as the addon's Apply already is.

   Either is allowed by the client's API as far as the docs show. And is click-to-take in 0.5 at all, given "keep it simple to start", when Apply already does the whole build? (#1564)
3. **The icon column's place and length.** Is it a strip between the talent window and the panel, or the top of the panel, with the build list scrolling below? How many past and upcoming? The draft says 3 and 5. (#1562)
4. **Did the meeting know about Apply?** The addon already spends a whole build after a trainer reset in one confirm (#872). The meeting's "load build" and "is this even allowed" read as if not. Keep Apply as it is, or move it behind a setting?
5. **Legacy: how does a plan meet the seasonal cap?** The site's cap is 16. Should Apply buy in the plan's order up to the points you have, and what's that order, since the site's code is ranks, not an order? (#1566, #1567)
6. **The order of 0.6 and 0.7.** The reference parts (bestiary, journal) before professions, as drafted, or professions first because it's the one the owner wants most?
7. **The auction house search in the MVP?** If spike #1574 finds it awkward, does professions ship with the list and alts' counts only, and the search in 0.7.1?
8. **The size budget.** Is 300 KB of shipped Lua acceptable? Is memory the worry, or download size? If memory, the data parts can be separate load-on-demand folders (`ForeverArmoury_Data`), loaded only when a tab opens. But that's more folders in the zip for players to keep together.
9. **Libraries.** The addon uses none today. A minimap button is easiest with LibDBIcon / LibDataBroker, which other addons share. Are libraries OK, or keep it library-free?
10. **Names in other languages.** Boss and beast names ship in English (the site's). Is English only fine for the MVP?
11. **BIS lists on the gear panel?** The site's BIS lists are twink PvP brackets only (5/10/19/30). In the MVP, or after?
12. **The journal: does Forever's own Encounter Journal exist and cover its dungeons?** This draft didn't check `Blizzard_EncounterJournal` on the branch. If it does, what's ours for: the site's role tags and the gear route's picks?
13. **The bestiary for non-hunters?** Hidden unless you're a hunter, or always shown?
14. **Lanes.** Who owns which milestone? A natural split from what each has built: the owner on talents, Legacy and the releases (0.3, 0.5, 1.0); Devon on gear, then the data export and the reference parts (0.4, 0.6). Professions (0.7) is the biggest and could be split: the guide and alts to one, the auction house to the other.
15. **Data freshness.** When the beta changes a build, who runs #1568's export and releases? Every beta build, or only when a part's data changed?
