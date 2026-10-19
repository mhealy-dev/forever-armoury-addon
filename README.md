# Forever Armoury (addon)

Your [Forever Armoury](https://foreverarmoury.app) talent builds in the game. Copy a build on the site (**Copy for addon**, in the calculator's build menu or the character's Talent builds picker), paste it into the addon, and the next talent of the build you follow lights up in the talent window.

The addon is made of parts, each with its own switch in its settings. The **level plan** is the first; macros and the UI layout may follow.

## Install

Copy the folder into `World of Warcraft\_forever_\Interface\AddOns\ForeverArmoury` (the folder's name has to be `ForeverArmoury`), or install it from CurseForge once it's listed there.

## Use

- `/fa` opens the talent window, with the addon's panel beside it: your builds for this class, the one you follow marked, and its next talent named and lit in the trees. Click a build to follow it; the **x** beside it forgets it.
- **Import** (or `/fa import`) opens the box to paste a code into. One paste can hold every build of a class, or several codes.
- **Export** (or `/fa export`) puts the code for every build of your class in the box, to paste into the site's Import box. Each build keeps the game build it was imported from, so builds from different game builds come out as a code each, one per line; the site reads them all from one paste.
- **Apply** (or `/fa apply`) spends your unspent points as the build you follow says, in its order, after one confirm that names them. It's all or none: if the game refuses a point, or fails the commit, nothing is spent. The button says how many points it would spend, or why it can't.
- `/fa plan off` turns the level plan part off; `/fa options` opens the settings; `/fa debug` lists every talent by tree, row and column as the addon reads them, with each node's position, the grid each tree was sorted by, and any talent left out and why.

With the Legacy perk **Talented**, your first talent point comes earlier, a level for each rank; the addon reads your rank from the game and moves the build's levels to match.

A build is kept for the account, so every character of its class can follow it. Pasting a build again, after changing it on the site, updates the one with that name.

### Swapping builds

Click another build in the panel to follow it. If your points fit it, Apply carries on with it. If you have points it doesn't, the panel names them and says what it takes:

- **Your other spec fits it** (with dual spec): activate that spec in the talent window, then Apply.
- **Otherwise**: reset your talents at a class trainer. When the trainer asks, the addon says how many points Apply will spend afterwards; the reset and its cost stay the game's own dialog. Then open your talents and press Apply once.

## The code

```
FAT2-70170-warrior-Arms%20PvP-0a0a0a0b0b0b1c
FAT <version> - <build> - <class> - <name> - <picks> { . <class> - <name> - <picks> }
```

The site writes it (`public/content/build-code.js` in forever-armoury) and `BuildCode.lua` reads it. The build is the game client's build number the talents are from (`GetBuildInfo`'s second answer): a talent that moves between the beta's builds changes what a cell means, so the site carries a code's picks to the trees it has by it; the addon writes the build it runs on and applies a code's cells to the game's own trees, which are the truth in-game. A `FAT1-` code, from before the build was written in, still reads. The picks are the build's points in the order spent, two characters each: the tree, then the talent's cell (tier and column).

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
- `TalentUI.lua`: the panel beside the talent window, the highlight, Apply's confirm, the import box, the settings page.
- `test/run.py`: everything checked in the game's Lua 5.1 (LuaJIT when lupa has it) against a stub of the game: both talent APIs, the trait system's staging with tier gates, commit, a commit failed late, and rollback, dual spec, combat, Talented, and the panel drawn against a mock of the frame API. `pip install lupa`, then `python test/run.py`; it passes under any locale, and with `LC_ALL=C`.
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

- **In the beta** (forever-armoury#1536): that the nodes' positions sort into the same rows and columns as the site's trees, and nothing is left out (`/fa debug`); what `CanChangeTalents` answers before and after a point is staged; that Apply's purchases and commit go through from an addon outside the window, and what a commit cast that's interrupted leaves; that the unspent count and Talented's rank read as the addon expects; the panel's place beside the window, and the highlight's look on the round buttons.
- **The CurseForge listing** (forever-armoury#1537): the project, its ID in the `.toc`, and the release process.
- **Talented in the code** (forever-armoury#1540): the site's codes still say point n is taken at level n + 9; the addon moves the levels by the rank it reads.
