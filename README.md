# Forever Armoury (addon)

Your [Forever Armoury](https://foreverarmoury.app) talent builds, leveling gear route and Legacy plans in the game. Copy a build on the site (**Copy for addon**, in the calculator's build menu or the character's Talent builds picker), paste it into the addon, and the next talent of the build you follow lights up in the talent window. The leveling gear route for your class is built in, and the pieces to get at your level sit beside the character window (Copy for addon on the site is for a route it has changed since the release); copy a Legacy plan, and the perks still to buy sit beside the Legacy window.

The addon is made of parts, each with its own switch in its settings. The **level plan**, the **leveling gear** and the **Legacy plans** are the first; BIS lists, macros and the UI layout may follow.

## Install

Copy the folder into `World of Warcraft\_classic_beta_\Interface\AddOns\ForeverArmoury` (the folder's name has to be `ForeverArmoury`), or install it from CurseForge once it's listed there.

## Use

- `/fa` opens the talent window, with the addon's panel beside it: your builds for this class, the one you follow marked, and its next talent named and lit in the trees. The builds are a section: the **Builds (N)** header opens and closes the list (closed, it names the build you follow; it opens by itself until you follow one, and the character keeps your choice). Click a build to follow it; the **x** beside it forgets it. With more than ten builds, the arrows under the list (or the mouse wheel over the panel) scroll it.
- While you follow a build, a strip of icons sits between the talent window and the panel (the Legacy window has the same strip, see [Legacy plans](#legacy-plans)): the build's talents in its order, an icon for each rank (`r/m` on a talent with ranks). The last points you took are faded with a green check; the next has a gold border and the game's glow, with **Now** under it when you can spend it, else its level; the ones coming show the level they're due at; a **⋮** under the last says more follow. The icons are 44 px and fill the strip's height (the strip is as tall as the talent window), so the whole build shows when it fits; when it doesn't, the **mouse wheel** over the strip moves it an icon a notch and the **arrows** at its ends a page, and it comes back to the next talent when your points change. Hover an icon to light that talent in the tree (in blue, beside the next talent's glow) and to see its tooltip, level and rank. **Click the next icon** to take that point (staged and committed in one click, all or none, with no confirm for a single point); **shift-click** it to spend every point due, after Apply's confirm. The icon highlights, and its tooltip says "Click to take it", only when the click would work; otherwise the tooltip's last line says why (no point to spend, in combat, changes waiting in the talent window, or a build that's off its order). The settings page sets where the view starts (the taken points above the next, 3 to start, and the coming points kept in view, 5) and the icon size (34 to 56, 44 to start), for both strips.
- **Import** (or `/fa import`) opens the box to paste a code into. One paste can hold every build of a class, or several codes, and a gear route code and Legacy plan codes beside them.
- **Export** (or `/fa export`) puts the code for every build of your class in the box, to paste into the site's Import box. Each build keeps the game build it was imported from, so builds from different game builds come out as a code each, one per line; the site reads them all from one paste.
- **Apply** (or `/fa apply`) spends your unspent points as the build you follow says, in its order, after one confirm that names them. It's all or none: if the game refuses a point, or fails the commit, nothing is spent. The button says how many points it would spend, or why it can't (in combat, for one); it follows the fight as it starts and ends.
- `/fa gear` opens the character window with the gear route's panel beside it (see [Leveling gear](#leveling-gear)), and `/fa legacy` the Legacy window with the Legacy plan's (see [Legacy plans](#legacy-plans)).
- `/fa plan off` turns the level plan part off, `/fa gear off` the leveling gear and `/fa legacy off` the Legacy plans; `/fa options` opens the settings; `/fa debug` lists every talent by tree, row and column as the addon reads them, with each node's position, the grid each tree was sorted by, and any talent left out and why; `/fa debug nodes` prints every node of your talent trees as the game gives it (id, position, ranks, how many groups and entries, visibility, type) and the tree the addon put it in.

With the Legacy perk **Talented**, your first talent point comes earlier, a level for each rank; the addon reads your rank from the game (or, when the game won't say, from the build's own, which a `FAT3-` code carries) and moves the build's levels to match.

A build is kept for the account, so every character of its class can follow it. Pasting a build again that's the same name and points updates it in place; a build with the same name and other points is another build, so two Arms builds sit side by side.

### Swapping builds

Click another build in the panel to follow it. If your points fit it, Apply carries on with it. If you have points it doesn't, the panel names them and says what it takes:

- **Your other spec fits it** (with dual spec): activate that spec in the talent window, then Apply.
- **Otherwise**: reset your talents at a class trainer. When you accept the trainer's reset, the addon says how many points Apply will spend afterwards (a cancelled dialog says nothing); the reset and its cost stay the game's own dialog. Then open your talents and press Apply once.

## Leveling gear

The site's leveling route for a class, spec and side is the weapons and key armour pieces worth the trip on the way to 60, each from a dungeon boss or a quest. **The routes are built in**: the addon ships all of them (every class, three specs, both sides), so `/fa gear` shows the one for your class, your side and your spec with nothing pasted. **Copy for addon** is for a route the site has changed since this release: on the site, open Best in slot, the Leveling plate, pick the spec and side, and Copy for addon; paste the code into the addon's import box. A pasted route is kept for the account, one per class, spec and side, so every character of the class has it, and it wins over the shipped one for that class, spec and side; the panel says "Route from the site." for a pasted route and "Route shipped with the addon." otherwise.

The shipped routes are `Data/Routes.lua`, written from the site's route files (`public/content/route/<class>.json`) by `tools/routes.py`; to write it again after the site's routes change, from a checkout of the site with `git fetch origin` run in it:

```
python3 -I tools/routes.py            # reads origin/main of ~/arda/shire/forever-armoury; --site PATH and --ref REF change that
```

The panel sits beside the character window (`/fa gear` opens it) and shows:

- The route's spec and side, and how many pieces of your level you have. The spec is the heaviest tree of the build you follow; with no build, or a tie, press the spec button to pick one (each press moves it on, and after the third it goes back to the build's). The side is your character's.
- **To get now**: the pieces the route has you wearing at this level that you don't wear or carry (equipped or in your bags), each as the game's item link, with where it comes from under it: the dungeon and the boss, or the quest. Hover a piece for the game's tooltip, to the right of the panel, with where it comes from and the level the route has it at; shift-click links it in chat.
- **Coming**: the pieces picked up after this level, with their levels.

An off hand is put away by a two-handed main hand picked up after it, as the site has it. The code carries no item or source text: the game names an item from its id, a dungeon from its instance id, a boss through a tooltip, and a quest from its id; where the game won't say, the id shows. `docs/gear-route.md` has the design, the code and what is still to check in the beta.

## Legacy plans

WoW Forever's Legacy is account-wide: three perk trees (Professions, Adventure, Resourcefulness), 27 perks, and a seasonal cap on the points spent in all of them (16 now). On the site's Legacy tab, **Copy for addon** gives the plan as a `FAL1-` code; paste it into the import box and the plan is kept for the account (not a class), whichever character imports it. The strip and the panel beside the Legacy window (`LegacySystemFrame`, which loads when the game first opens it; `/fa legacy` opens it on its trees) show:

- **The strip**: while you follow a plan that can be bought, a strip of icons hangs on the window's right edge under its side tabs, with the panel against it. It is the talent window's strip (the same size and scroll settings, the same icons and states) for the plan's ranks in the order Apply buys them: tree by tree, by row, a perk's prerequisite full first and the points its tree wants spent before it. An icon for each rank (`r/m` on a perk with ranks); the ranks you have are faded with a green check; the next has a gold border and the game's glow, with **Now** under it when a Legacy point is available and the cap isn't spent, else **wait** (Legacy has no levels); the ones coming wear their tree's short name (**Prof**, **Adv**, **Res**). The icon and name are the game's own for the perk (its trait definition, read through the tree's config), else the site's icon and name.
- **Hover** an icon to light the perk in the window's tree (in blue, beside the next perk's glow) when that icon's tree is the one on show, and to see the game's tooltip for the perk with **Rank r of m**; for a perk of a tree that isn't on show it adds **In the Adventure tree** and lights nothing.
- **Click the next icon** to buy that one rank and commit its tree (`C_Traits.PurchaseRank`, then `C_Traits.CommitConfig` for the tree's config; no confirm for one rank, all or none, rolled back and said in chat if the game refuses or the commit fails). **Shift-click** it for Apply, with its confirm. If the next rank is in a tree the window isn't showing, the click first switches the window to that tree, the way its tree tabs do (the game's `Legacy.SelectTree` event, else the tree panel's `SelectTree`), and buys; where an addon can't switch it, the tooltip names the tab to open and the click does nothing. The icon highlights, and its tooltip says "Click to buy it", only when the click would work; otherwise the tooltip's last line says why (no Legacy point, the cap, in combat, changes waiting in the Legacy window, or that rank is being bought).
- **Plans (N)**: the account's, the one followed marked; click to follow, **x** to forget. The plans are a section: the **Plans (N)** header opens and closes the list (closed, it names the plan you follow; it opens by itself until you follow one, and the account keeps your choice). With more than five, the arrows (or the wheel) scroll. A plan from a client build other than the addon's has a red **!**, and no strip.
- **The followed plan**: each perk it wants with the ranks you have against the ranks it wants (green when done, gold for the next, red for one the plan can't buy as it stands, such as a perk with too few points in its tree before it, or one the game doesn't sell yet), the Legacy points available and how many of the cap are spent, and the next perk named. The next perk of each tree lights in the window's tree with the glow the talents have; the window shows one tree at a time, so the one on show lights.
- **Apply** buys what's next in an order the game takes: tree by tree, by row, a perk's prerequisite full first and the points its tree wants spent before it, one rank at a time through `C_Traits.PurchaseRank`, then `C_Traits.CommitConfig` for the tree. One confirm names the perks first. It's all or none **per tree** (each tree is a config of its own): a refused purchase or a failed commit rolls that tree back, says so, and leaves the trees that went through. It stops at the points you have and the cap, and it never takes points back (ranks you have that the plan doesn't want are counted and left). It won't start in combat or while the Legacy window has changes of its own waiting, and the button says how many ranks it would buy, or why it can't.
- **Import** opens the shared box; **Export** puts the account's plans in it as `FAL1-` codes, one line for each client build.

```
FAL1-70425-Gatherer%27s%20Path-150000000051000000030001000
FAL <version> - <build> - <name> - <ranks> { . <name> - <ranks> }
```

`LegacyCode.lua` reads and writes it, `Legacy.lua` keeps the plans and buys them, `LegacyUI.lua` is the panel. The build is the client build the perks' order is from (`70425` of `1.60.1.70425`); the name is a build's, percent-encoded and cut to 40 characters; the ranks are 27 characters of base 36, one a perk, in the order of `Legacy.PERKS`, which is the site's (`public/data/legacy.js`): Professions, Adventure, Resourcefulness, nine perks each. `Legacy.lua` carries the 27 perks' node ids, tree, most ranks, row and column, prerequisite and points needed, copied by hand from the site's data for build 1.60.1.70425. **A code from another build is kept and shown, and never bought**: a perk that moves between builds changes what a place in the ranks means, and the addon can't know where. A rank past what its perk takes is refused on import, for a code from the build the addon knows.

## The code

```
FAT3-70170-warrior-Arms%20PvP-0a0a0a0b0b0b1c1c-3
FAT <version> - <build> - <class> - <name> - <picks> - <talented> { . <class> - <name> - <picks> - <talented> }
```

The site writes it (`public/content/build-code.js` in forever-armoury) and `BuildCode.lua` reads it. The build is the game client's build number the talents are from (`GetBuildInfo`'s second answer): a talent that moves between the beta's builds changes what a cell means, so the site carries a code's picks to the trees it has by it; the addon writes the build it runs on and applies a code's cells to the game's own trees, which are the truth in-game. The `<talented>` is the build's rank of the Legacy perk Talented (one digit, 0 to 5), which brings the first talent point that many levels early: the level plan counts levels by the rank the game says the character has, and by the build's own when the game won't say. `FAT2-` and `FAT1-` codes, from before the rank and the build were written in, still read, with rank 0; Export writes `FAT3-`. The reader keeps to the site's: a name is cut to 40 characters (with a note; Export cuts it too), must be UTF-8, and has its spaces, Unicode ones too, collapsed; a version is 1 to 3 digits and a build 1 to 8. The picks are the build's points in the order spent, two characters each: the tree, then the talent's cell (tier and column).

The gear route code is its own:

```
FAG1-warrior-0-alliance-18wxddd0Nr0Ul18izdgd0Nr0Un1aOreoqp4J…
FAG <version> - <class> - <spec> - <side> - <pieces>
```

`GearCode.lua` reads and writes it. The spec is the talent tree's index, 0 to 2, and the pieces follow one another with nothing between them, each fixed-width fields in base 62: the item id, the level, the slot's letter, and the source (`d` and the dungeon's and boss's ids, or `q` and the quest's). A route of the site's is 460 to 730 characters. `docs/gear-route.md` is the format's definition.

## The Forever client

The Forever client (Blizzard's game type `camelot`, 1.60.x, interface `16001`) keeps its talents in the trait system that retail's talent trees use, not in the old `GetTalentInfo` API, which it doesn't have at all (checked in Blizzard's UI source for 1.60.1). So:

- The talent window is `PlayerSpellsFrame.TalentsFrame` (`Blizzard_PlayerSpells`, loaded on demand), and each talent is a trait node with a position. `Talents.lua` sorts the nodes of each tree into columns and rows by position, so the site's cell names the node, and the addon carries no talent data.
- A node belongs to whichever of its `groupIDs` is one of the class tree's display groups (the beta gives a node 3 to 7 of them, the talent tree's not always first); a node whose groups name two trees takes the first (`/fa debug nodes` says so), and one whose groups name none goes to the tree its `posX` falls in or is nearest to. No node is dropped for its rank count: `maxRanks`, else `totalMaxRanks`, else its entry's, else the cell is kept with the count unknown (`?`). A node is left unread only when `isVisible` is false (the window skips it too), the game gives no information on it, or it has no position, and `/fa debug` says so.
- A pick of a build that no talent of the trees sits under is marked, not fatal: the panel names the cells, the strip shows a greyed question mark in its place, and Apply stops at the first one.
- Each tree is sorted on its own grid, the spacing of its own nodes, so one tree drawn differently, or one node off its tree's grid, can't misfile the others. A node that lands past the fourth column or the seventh row, or on a cell another node has, is left out and said in chat, and `/fa debug` names it.
- Apply stages each point with `C_Traits.PurchaseRank` and applies them with `C_ClassTalents.CommitConfig()`, as the window's own Apply button does. The commit is a cast, so the game can still fail it after it starts; if a point is refused, or the commit is, at once or later (`CONFIG_COMMIT_FAILED`), `C_Traits.RollbackConfig` drops everything staged. `C_ClassTalents.CanChangeTalents()` is only true once changes are staged, so Apply asks it after the first point, and rolls back if the game says no. It won't start while the window has changes of its own waiting, or in combat.
- The client has dual spec: the window's two tabs are spec groups, each with its own trait config (`C_SpecializationInfo.GetCombatConfigIDForSpecGroup`). The addon follows the active one and reads the other for Swap. When `C_ClassTalents.GetActiveConfigID()` has no answer yet, it takes the active spec group's config, as the window does.
- Talented is node 110298 of the Legacy Adventure tree 1188 (`Constants.LegacyConsts`); its `ranksPurchased` moves the first point from level 10 to 10 minus the rank.

A client that still has the old API gets the same trees from it, so the rest of the addon has one path.

## Files

- `ForeverArmoury.lua`: the namespace, saved variables, parts and their switches, `/fa`, events.
- `BuildCode.lua`: the code, read and written.
- `Talents.lua`: the game's talents as three trees of cells for either spec, spending points, and the talent window.
- `Builds.lua`: the saved builds, the character's active one, where a spec is on it (`FA.Progress`), and what Apply and Swap do.
- `Strip.lua`: the strip of icons both windows share (`FA.Strip.New(owner)`: it draws, scrolls, lights the hovered perk and shows the tooltip; the owner says what the plan is and how a point is spent), and the highlights in the trees (`FA.LightButtons`).
- `TalentUI.lua`: the build's side of the strip and the panel beside the talent window, Apply's confirm, the import box, the settings page.
- `GearCode.lua`: the gear route code, read and written.
- `Data/Routes.lua`: the leveling gear routes the addon ships, written by `tools/routes.py` from the site's route files.
- `tools/routes.py`: writes `Data/Routes.lua`; not part of the release zip.
- `Gear.lua`: the shipped and the saved gear routes, the character's route (its side and spec), what it wears and carries, and the next pieces at its level (`FA.Gear.Plan`).
- `GearUI.lua`: the panel beside the character window.
- `LegacyCode.lua`: the Legacy plan code, read and written.
- `Legacy.lua`: the account's Legacy plans, the 27 perks, where the account is on a plan (`FA.Legacy.Progress`), and Apply across the three trees' configs (`FA.ApplyLegacy`).
- `LegacyUI.lua`: the plan's side of the strip, the panel beside the Legacy window, and `/fa legacy`.
- `docs/gear-route.md`: the leveling gear part's design: the code, what the site adds, and what is still to check in the beta.
- `test/run.py`: everything checked in the game's Lua 5.1 (LuaJIT when lupa has it) against a stub of the game: both talent APIs, the trait system's staging with tier gates, commit, a commit failed late, and rollback, dual spec, combat, Talented, the gear route code read and written (a whole route of the site's round-trips), the next pieces at a level against what is worn and carried, and a Legacy plan code read and written (the site's sample byte for byte) and bought across a stub of the three Legacy configs (the cap, the points, a refused purchase and a failed commit rolling back one tree, combat, the window's staged changes, a plan from another build), and the panels drawn against a mock of the frame API. `pip install lupa`, then `python test/run.py`; it passes under any locale, and with `LC_ALL=C`.
- `.pkgmeta`: what the CurseForge packager builds: the folder `ForeverArmoury`, without the tests, the release script and this file, with the version from the git tag, and `CHANGELOG.md` as the changelog CurseForge shows.
- `scripts/release.sh`: builds the release zip from a tag, checks what is in it, and uploads it to CurseForge when asked. See [Releasing](#releasing).

## Releasing

Releases are made by hand from a laptop (GitHub Actions is off), with the [BigWigs packager](https://github.com/BigWigsMods/packager) behind `scripts/release.sh`. The zip is built from a git tag: the tag is the version, put into the `.toc` for `@project-version@`, and the packager sends the zip to CurseForge for the Forever client (`## Interface: 16001`).

Once, to set up:

1. `brew install bash jq`. The packager needs bash 4.3 or newer (macOS has 3.2) and `jq` to upload; the wrapper itself runs with either.
2. **Create the CurseForge project** at [authors.curseforge.com](https://authors.curseforge.com): *Create project*, game World of Warcraft, category Addons, name *Forever Armoury*. Copy its numeric **Project ID** from the project's overview.
3. **Put the ID in the `.toc`**: replace the commented line `# ## X-Curse-Project-ID: ...` in `ForeverArmoury.toc` with `## X-Curse-Project-ID: <the ID>`, commit it and merge it to `main`.
4. **Make an API token** at [authors.curseforge.com/#/settings/api-tokens](https://authors.curseforge.com/#/settings/api-tokens) and keep it out of git, in the gitignored `.release/.env`:

   ```bash
   mkdir -p .release && printf 'CF_API_TOKEN=%s\n' 'the-token' > .release/.env && chmod 600 .release/.env
   ```

Then, for each release (the first is `v0.3.0`):

1. Date the version in `CHANGELOG.md`, commit, and merge to `main`. Then be on a clean, current `main`: `git checkout main && git pull`.
2. Tag it: `git tag -a v0.3.0 -m "Forever Armoury 0.3.0"` and `git push origin v0.3.0`.
3. Build it without uploading:

   ```bash
   scripts/release.sh
   ```

   It stops unless the tree is clean, you are on `main`, and `HEAD` has a `vX.Y.Z` tag. It fetches the packager into `.release/` the first time (a pinned version, checked against its hash), builds `.release/ForeverArmoury-v0.3.0.zip`, prints the zip's listing, and checks it: one `ForeverArmoury/` folder with the `.toc`, the Lua files, `LICENSE` and `CHANGELOG.md` and nothing else (no `test/`, `scripts/` or `README.md`), with the tag as the `.toc`'s version.
4. Upload it:

   ```bash
   scripts/release.sh --upload
   ```

   It builds again, checks the same things, and sends the zip to CurseForge. It also needs the ID in the `.toc`, `CF_API_TOKEN`, `main` and the tag pushed. It sends to CurseForge only, whatever other upload tokens the environment has.
5. Open the project's page on CurseForge, check the file is listed for the Forever client, and install it from there once.

A tag never moves: a fix is a new tag, `v0.3.1`. If the token route fails, upload the zip from step 3 through the project's *Upload file* form instead.

## Legacy in the client

From Blizzard's UI source for the Forever client (branch `forever` of `Gethe/wow-ui-source`; not yet run in the beta):

- The Legacy window is `LegacySystemFrame` (`Blizzard_LegacySystem`, load on demand), opened by the global `ToggleLegacySystemUI()` of the addon's bootstrap file, which does nothing until the Legacy reward track has begun (`C_MajorFactions.GetCurrentRenownLevel` of the Legacy faction above 0). Its pages are the reward track, the challenges and the trees (page 3, which `/fa legacy` selects with the `Legacy.SelectPage` event).
- Its tree page is `LegacySystemFrame.TreePage.LegacyTreeTraitPanel`, a `LegacyTreeTraitPanelMixin` over the talent frame base, showing one tree at a time (`Legacy.SelectTree`), so `GetTalentButtonByNodeID` answers for the tree on show only.
- The window's tree tabs (`LegacyTreeButtonMixin`, `Blizzard_LegacyTree.lua`) are not clicked by an addon: their click sends `EventRegistry:TriggerEvent("Legacy.SelectTree", index)`, `index` being the tree's place in the global `LegacyTreeData` (`Blizzard_LegacySystemConstants.lua`: Professions, Adventure, Resourcefulness, each with its `treeID`), which the tree panel (`LegacyTreeTraitPanelMixin:SelectTree(index)`, which sets its config and tree) and the tab selection both listen to. The strip's click sends that event (after `Legacy.SelectPage` with the trees page, 3, when the tree panel isn't visible), and falls back to calling the panel's `SelectTree` itself.
- The three trees are ordinary trait trees, 1187 (Professions), 1188 (Adventure, with Talented) and 1189 (Resourcefulness), each with a config from `C_Traits.GetConfigIDByTreeID(treeID)`. The window buys with `C_Traits.PurchaseRank` and applies with `C_Traits.CommitConfig(configID)`, not `C_ClassTalents`, and reads its points from `C_Traits.GetTreeCurrencyInfo(configID, treeID, false)`: `quantity` is the points available and `maxQuantity` the seasonal cap ("You can spend up to your current seasonal cap of %d Legacy Points in total").

## Licence

MIT, in `LICENSE`.

## Still to settle

- **In the beta, after #1590**: that `/fa debug` lists every talent the window draws, a warrior's 17, 17 and 18 by the site's layout (the issue counted Arms as 18; a window with an 18th Arms talent means the site is missing one), with nothing left out, and that `/fa debug nodes` shows each node's tree as `group <id>` rather than by position; the first try's dump showed `maxRanks` above 0 and `isVisible` true on the nodes it read, and 3 to 7 `groupIDs` a node, which is the field the old reading missed.
- **In the beta** (forever-armoury#1536, #1539): that the events `ACTIVE_COMBAT_CONFIG_CHANGED`, `PLAYER_REGEN_ENABLED` and `PLAYER_REGEN_DISABLED` exist (chat names any the game refuses at login) and the Apply button follows combat; that the trainer's reset dialog is Blizzard's `CONFIRM_TALENT_WIPE` popup, so accepting it says what Apply will spend (chat says at login if the popup isn't there); the build list's arrows and wheel in the panel; that every `C_Traits` function the addon calls is in the client (chat names any that isn't); that the nodes' positions sort into the same rows and columns as the site's trees, and nothing is left out (`/fa debug`); what `CanChangeTalents` answers before and after a point is staged; that Apply's purchases and commit go through from an addon outside the window, and what a commit cast that's interrupted leaves; that the unspent count and Talented's rank read as the addon expects; the panel's place beside the window, and the highlight's look on the round buttons.
- **The Legacy plans in the beta** (forever-armoury #1565, #1567), none of it run in the game yet: that `LegacySystemFrame` is the window's name and the panel sits right beside it, and `/fa legacy` opens it (and on the trees page) once the Legacy track has begun; that `LegacySystemFrame.TreePage.LegacyTreeTraitPanel:GetTalentButtonByNodeID` answers for a perk of the tree on show (the glow); that `C_Traits.GetTreeCurrencyInfo` on a Legacy tree's config answers with `quantity` (points available) and `maxQuantity` (the cap) as the Legacy window reads them, and that the currency is the account's, so every tree says the same; what the game does with a purchase past the cap or the points (the addon never asks for one, so a refusal here is only the safety net), and whether a rank costs one point; that a rank's prerequisite means "full" and a perk's points-needed counts the points on the tree's other perks (the addon buys in that order, and rolls the tree back if the game says otherwise); where the window's side tabs end (the trees tab's bottom against the window's top; the panel starts under them, 284 down when the game won't say) and that the panel doesn't cover the Trees tab; whether either trait event (`TRAIT_CONFIG_UPDATED`, `CONFIG_COMMIT_FAILED`) can arrive inside the `CommitConfig` call (both are handled); that `C_Traits.CommitConfig` per tree goes through from an addon outside the window, whether it is instant or a cast that can fail later (`CONFIG_COMMIT_FAILED`, with which config id), and whether `PurchaseRank` on a second tree is accepted while the first tree's commit cast is in flight (Apply goes tree by tree without waiting); that the events `TRAIT_CONFIG_UPDATED` and `TRAIT_NODE_CHANGED` redraw the panel as points are bought or earned; that the table's node ids and max ranks are the client's (`/fa legacy` shows a perk the game doesn't know as an error in the panel's status); the panel's place and height beside the 920-wide window.
- **The Legacy strip in the beta** (forever-armoury #1594), none of it run in the game yet: that the strip hangs on the window's right edge under the side tabs and the panel against it (`LegacyTreeTab:GetBottom()` against the window's top, 284 down when the game won't say), and how many icons fit below the tabs; that `C_Traits.GetNodeInfo`, `GetEntryInfo` and `GetDefinitionInfo` on a Legacy tree's config give the perk's name, icon and spell (the strip falls back to the site's icon and name, and shows the name when there is no spell); that `Legacy.SelectTree` sent from the addon switches the tree panel and the tabs' selection, and that `LegacyTreeData` numbers the trees as the event expects (the strip uses the game's list, else its own order); that the buttons exist right after the switch, so the glow and the hover light the perk (they are looked for again on `TalentFrameBase.ButtonsUpdated`); that buying one rank from the strip with another tree on show goes through (`PurchaseRank` and `CommitConfig` on a tree the window isn't showing), and what the Legacy window's own Apply and Undo buttons do after it; that `Legacy.SelectPage` with 3 opens the trees page from another page; the glow of the blue hover over the Legacy tree's square buttons.
- **The Legacy plan code in the site** (#1566, merged): the sample in `test/run.py` is the one in forever-armoury's PR 1585. The perks' table is copied by hand, so when the site's build moves, `Legacy.lua`'s table and `BUILD` move with it.
- **The leveling gear in the beta** (`docs/gear-route.md`): that `/fa gear` shows the shipped route on a character that has pasted nothing, and that hovering a piece shows the item's tooltip beside the panel on the live client (forever-armoury#1591, #1592); `GetItemInfo` on Forever's item ids above 270,000 for an item not yet cached, and the load events after it; `C_Container` in interface 16001; whether the game names Forever's own dungeons, bosses and quests from their ids; the panel's place beside the character window.
- **The site's Copy for addon** for routes: the Leveling plate's button and `public/content/gear-code.js`, writing the code `docs/gear-route.md` defines.
- **The CurseForge listing** (forever-armoury#1537): the project, its ID in the `.toc`, and the release process.
