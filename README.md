# Forever Armoury (addon)

Your [Forever Armoury](https://foreverarmoury.app) talent builds and leveling gear route in the game. Copy a build on the site (**Copy for addon**, in the calculator's build menu or the character's Talent builds picker), paste it into the addon, and the next talent of the build you follow lights up in the talent window. Copy a gear route the same way, and the pieces to get at your level sit beside the character window.

The addon is made of parts, each with its own switch in its settings. The **level plan** and the **leveling gear** are the first; BIS lists, macros and the UI layout may follow.

## Install

Copy the folder into `World of Warcraft\_forever_\Interface\AddOns\ForeverArmoury` (the folder's name has to be `ForeverArmoury`), or install it from CurseForge once it's listed there.

## Use

- `/fa` opens the talent window, with the addon's panel beside it: your builds for this class, the one you follow marked, and its next talent named and lit in the trees. The builds are a section: the **Builds (N)** header opens and closes the list (closed, it names the build you follow; it opens by itself until you follow one, and the character keeps your choice). Click a build to follow it; the **x** beside it forgets it. With more than ten builds, the arrows under the list (or the mouse wheel over the panel) scroll it.
- While you follow a build, a strip of icons sits between the talent window and the panel: the build's talents in its order, an icon for each rank (`r/m` on a talent with ranks). The last points you took are faded with a green check; the next has a gold border and the game's glow, with **Now** under it when you can spend it, else its level; the ones coming show the level they're due at; a **⋮** says more follow. Hover an icon to light that talent in the tree (in blue, beside the next talent's glow) and to see its tooltip, level and rank. The settings page picks how many taken and coming points it shows (3 and 5 to start).
- **Import** (or `/fa import`) opens the box to paste a code into. One paste can hold every build of a class, or several codes, and a gear route code beside them.
- **Export** (or `/fa export`) puts the code for every build of your class in the box, to paste into the site's Import box. Each build keeps the game build it was imported from, so builds from different game builds come out as a code each, one per line; the site reads them all from one paste.
- **Apply** (or `/fa apply`) spends your unspent points as the build you follow says, in its order, after one confirm that names them. It's all or none: if the game refuses a point, or fails the commit, nothing is spent. The button says how many points it would spend, or why it can't (in combat, for one); it follows the fight as it starts and ends.
- `/fa gear` opens the character window with the gear route's panel beside it (see [Leveling gear](#leveling-gear)).
- `/fa plan off` turns the level plan part off and `/fa gear off` the leveling gear; `/fa options` opens the settings; `/fa debug` lists every talent by tree, row and column as the addon reads them, with each node's position, the grid each tree was sorted by, and any talent left out and why.

With the Legacy perk **Talented**, your first talent point comes earlier, a level for each rank; the addon reads your rank from the game (or, when the game won't say, from the build's own, which a `FAT3-` code carries) and moves the build's levels to match.

A build is kept for the account, so every character of its class can follow it. Pasting a build again that's the same name and points updates it in place; a build with the same name and other points is another build, so two Arms builds sit side by side.

### Swapping builds

Click another build in the panel to follow it. If your points fit it, Apply carries on with it. If you have points it doesn't, the panel names them and says what it takes:

- **Your other spec fits it** (with dual spec): activate that spec in the talent window, then Apply.
- **Otherwise**: reset your talents at a class trainer. When you accept the trainer's reset, the addon says how many points Apply will spend afterwards (a cancelled dialog says nothing); the reset and its cost stay the game's own dialog. Then open your talents and press Apply once.

## Leveling gear

The site's leveling route for a class, spec and side is the weapons and key armour pieces worth the trip on the way to 60, each from a dungeon boss or a quest. On the site, open Best in slot, the Leveling plate, pick the spec and side, and **Copy for addon**; paste the code into the addon's import box. A route is kept for the account, one per class, spec and side, so every character of the class has it.

The panel sits beside the character window (`/fa gear` opens it) and shows:

- The route's spec and side, and how many pieces of your level you have. The spec is the heaviest tree of the build you follow; with no build, or a tie, press the spec button to pick one (each press moves it on, and after the third it goes back to the build's). The side is your character's.
- **To get now**: the pieces the route has you wearing at this level that you don't wear or carry (equipped or in your bags), each as the game's item link, with where it comes from under it: the dungeon and the boss, or the quest. Hover a piece for the game's tooltip; shift-click links it in chat.
- **Coming**: the pieces picked up after this level, with their levels.

An off hand is put away by a two-handed main hand picked up after it, as the site has it. The code carries no item or source text: the game names an item from its id, a dungeon from its instance id, a boss through a tooltip, and a quest from its id; where the game won't say, the id shows. `docs/gear-route.md` has the design, the code and what is still to check in the beta.

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
- `TalentUI.lua`: the strip and the panel beside the talent window, the highlights, Apply's confirm, the import box, the settings page.
- `GearCode.lua`: the gear route code, read and written.
- `Gear.lua`: the saved gear routes, the character's route (its side and spec), what it wears and carries, and the next pieces at its level (`FA.Gear.Plan`).
- `GearUI.lua`: the panel beside the character window.
- `docs/gear-route.md`: the leveling gear part's design: the code, what the site adds, and what is still to check in the beta.
- `test/run.py`: everything checked in the game's Lua 5.1 (LuaJIT when lupa has it) against a stub of the game: both talent APIs, the trait system's staging with tier gates, commit, a commit failed late, and rollback, dual spec, combat, Talented, the gear route code read and written (a whole route of the site's round-trips), the next pieces at a level against what is worn and carried, and both panels drawn against a mock of the frame API. `pip install lupa`, then `python test/run.py`; it passes under any locale, and with `LC_ALL=C`.
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

## Licence

MIT, in `LICENSE`.

## Still to settle

- **In the beta** (forever-armoury#1536, #1539): that the events `ACTIVE_COMBAT_CONFIG_CHANGED`, `PLAYER_REGEN_ENABLED` and `PLAYER_REGEN_DISABLED` exist (chat names any the game refuses at login) and the Apply button follows combat; that the trainer's reset dialog is Blizzard's `CONFIRM_TALENT_WIPE` popup, so accepting it says what Apply will spend (chat says at login if the popup isn't there); the build list's arrows and wheel in the panel; that every `C_Traits` function the addon calls is in the client (chat names any that isn't); that the nodes' positions sort into the same rows and columns as the site's trees, and nothing is left out (`/fa debug`); what `CanChangeTalents` answers before and after a point is staged; that Apply's purchases and commit go through from an addon outside the window, and what a commit cast that's interrupted leaves; that the unspent count and Talented's rank read as the addon expects; the panel's place beside the window, and the highlight's look on the round buttons.
- **The leveling gear in the beta** (`docs/gear-route.md`): `GetItemInfo` on Forever's item ids above 270,000 for an item not yet cached, and the load events after it; `C_Container` in interface 16001; whether the game names Forever's own dungeons, bosses and quests from their ids; the panel's place beside the character window.
- **The site's Copy for addon** for routes: the Leveling plate's button and `public/content/gear-code.js`, writing the code `docs/gear-route.md` defines.
- **The CurseForge listing** (forever-armoury#1537): the project, its ID in the `.toc`, and the release process.
