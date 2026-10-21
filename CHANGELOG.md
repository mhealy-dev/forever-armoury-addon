# Changelog

## 0.5.1 (unreleased)

Read every talent node, and keep going when a pick doesn't place (forever-armoury #1590):

- **A node's tree is whichever of its `groupIDs` is one of the trees' groups.** The first beta try (client 1.60.1.70450) showed why the addon read 3 of Arms's talents, 1 of Fury's and 2 of Protection's: each node has 3 to 7 `groupIDs`, and the talent tree's group is not always the first, which was the only one the addon looked at. A node whose groups don't name a tree, or name two, goes to the tree its `posX` falls in or is nearest to, by the x range of the nodes that do have a group (the trees sit thousands apart, the columns 600); with no group on any node, the x values are split into one run per tree at the widest gaps.
- **No node is dropped for its rank count.** `maxRanks` when above 0, else `totalMaxRanks`, else its first entry's `maxRanks`; a node none of them counts is kept with its rank count unknown, drawn as `?` (`Rank 1 of ?`, `1/?`). A node is left unread only when `isVisible` is false, as the talent window skips it too, or it has no position, and `/fa debug` lists it with why.
- **`/fa debug nodes`** prints every node of the active config as the game gives it, a line each: id, `posX`, `posY`, `maxRanks`, `totalMaxRanks`, how many `groupIDs` and `entryIDs`, `isVisible`, `type`, `subTreeID`, and the tree the addon gave it and why. `/fa debug` is as it was, and says how many of a tree's nodes went by position.
- **A pick that doesn't place is marked, not fatal.** A build with a pick no talent of your trees sits under (the site newer than the addon, or a node that did not sort) used to stop at "A talent in this build isn't in your talent trees" with no next talent, no strip and Apply off. Now `FA.Progress` places what it can and lists the rest (`unplaced`, each with its tree and cell). The panel says "N talents of this build aren't in your trees" with their cells (three named, then "and N more") and carries on: the next placeable talent is lit; the strip shows each such pick, in its place in the order, as a greyed question-mark icon whose tooltip names the cell; Apply spends the placeable points in order and stops at the first unplaceable one, saying so in its button tooltip, in the confirm and in chat. Chat says the same when the build is imported, once per build.

## 0.5.0 (unreleased)

Legacy plans (forever-armoury #1567, from #1566):

- **`FAL1-` codes**: the site's Legacy tab writes a Legacy plan as `FAL1-<build>-<name>-<ranks>` (`FAL1-70425-Gatherer%27s%20Path-150000000051000000030001000`): the client build the perks' order is from, the plan's name as a build's, and 27 base-36 digits, one rank a perk, tree by tree. The import box reads them beside build and gear codes (one paste can hold all three), says what came of each, and Export gives the account's Legacy plans back as `FAL1-` codes, one line a build.
- **Legacy plans are the account's**, as Legacy is: kept once for every character, one followed for the account, checked at load like builds (one whose ranks don't read is dropped, a missing name, build or id repaired, with a line in chat saying so).
- **A panel beside the Legacy window** (`LegacySystemFrame`, loaded on demand): the account's plans (click to follow, **x** to forget, arrows and wheel to scroll), the followed plan's perks with the ranks you have and the plan wants, the Legacy points available against the seasonal cap, and the next perk, named and lit in the window's tree with the same glow the talents have (the window shows one tree at a time, so the next perk of the tree on show lights).
- **Apply buys the plan across the three trees**: one confirm naming the perks, then, tree by tree, `C_Traits.PurchaseRank` for each rank in an order the game takes (by row, a perk's prerequisite full and its tree's points spent first) and `C_Traits.CommitConfig` for the tree. It's all or none in each tree: a refused purchase or a failed commit, at once or later (`CONFIG_COMMIT_FAILED`), rolls that tree back and leaves the others. It stops at the points you have and the seasonal cap, never refunds, and won't start in combat or while the Legacy window has changes of its own waiting. The button says how many ranks it would buy, or why it can't.
- **A plan from another client build is shown, never bought**: the addon's table of the 27 perks is of build 1.60.1.70425, so a code from another build, whose places in the ranks may mean other perks, is marked in the list and the panel says so.
- **`/fa legacy`** opens the Legacy window on its trees with the panel beside it, **`/fa legacy on|off`** and a switch on the settings page turn the part on and off.
- Behind it: `LegacyCode.lua`, `Legacy.lua` and `LegacyUI.lua`; `BuildCode.lua` shares its name helpers, `Talents.lua` its guard for trait functions the client may lack (`FA.Talents.Game`), and `TalentUI.lua` its glow (`FA.LightButtons`).

Click to take a talent (forever-armoury #1564):

- **Click the next icon in the strip** and it takes that point: one rank, staged and committed together, as Apply does for a plan of one point (`C_Traits.PurchaseRank`, then `C_ClassTalents.CommitConfig`). It's all or none: a refused purchase or a failed commit, at once or later, rolls back and chat says why, in Apply's words. There is no confirm for one point; the tooltip already names it. Chat says what was taken (`Spent as Arms says: Deflection.`).
- **Shift-click the next icon** is Apply for every point due, through the same confirm.
- **Only the next icon, and only when Apply could spend**: a point to spend, out of combat, none of the window's own changes waiting, the build not off its order. Otherwise the click does nothing and the tooltip's last line says why, with Apply's reasons. When it would work the icon highlights under the mouse and the tooltip ends with **Click to take it** (and **Shift-click to take all N** when more than one is due).
- **While the commit casts, a second click does nothing**, and the tooltip says the point is being applied; the strip moves on when the game answers.
- Behind it: `FA.Apply` and `FA.PlanApply` take an optional number of points, and `FA.Talents.Applying()` says whether the addon's commit is casting.

The Talented rank in the build code (forever-armoury #1540):

- **`FAT3-` codes**: each build ends with its rank of the Legacy perk Talented, one digit 0 to 5 (`FAT3-70170-warrior-Arms%20PvP-0a0a0a0b0b0b1c1c-3`), as the site now writes them. `FAT1-` and `FAT2-` codes still read, with rank 0. A rank that isn't 0 to 5 is refused with a sentence, as the site does.
- **Import keeps the rank** with the saved build, and Export writes a `FAT3-` code with each build's rank. A build from a `FAT1-` or `FAT2-` code exports with rank 0 (a `FAT1-` build's game build is written as 0, which the site reads as the first trees).
- **The first point's level** is 10 minus the rank the game says, as before; when the game won't say (the Legacy config can't be read) the build's own rank is used, and 10 when neither is known. `/fa debug` says which rank is in use and where it came from.

The talent column (forever-armoury #1562, #1563):

- **A strip of icons beside the talent window**: the build you follow, talent by talent in its order, one icon for each rank (a talent with ranks shows `r/m` on it). The last points you took are faded with a green check, the next one has a gold border and the game's glow with **Now** under it when you can spend it (else the level it comes at), and the ones coming have the level they're due at in a corner. A **⋮** under them says more follow. The icon and name come from the game; an icon the game hasn't given yet is a question mark. It shows with the panel and only while you follow a build, redraws as you spend points, change build or swap spec, and the panel sits against it. A build that's off its order shows the points it can place and nothing wrong.
- **How many it shows** is two sliders on the settings page: the taken points (3 by default, up to 5) and the coming ones (5, up to 8).
- **Hover an icon** and that talent lights in the tree, in blue, beside the next talent's glow, which stays; leaving puts it out. The tooltip is the talent's own spell, then its level and rank, and "Taken" for a rank you have. The highlight is a frame of the addon's, never something written on the game's pooled button.
- **The panel's build list is a section**: a **Builds (N)** header with a plus or minus opens and closes it, and closed it says which build you follow. It's open until you follow a build and closed after, and what you choose is kept for the character. The panel is as tall as what it shows, with Import and Export at the bottom.

## 0.4.0 (unreleased)

Small fixes after the first release (forever-armoury #1539):

- **Builds with one name keep each their points**: an import updates a build only when its name and points both match one kept, so two Arms builds, or two unnamed ones, are two builds, not one overwriting the other.
- **The build list scrolls**: an arrow pair under it and the mouse wheel over the panel move it, so an 11th build, and a 100th, can be picked.
- **A name is drawn as typed**: a `|` in a build's name is doubled where the addon draws it (the list, chat, the confirms), so a `|c` colour escape in a name doesn't take effect; a build with no name shows as Unnamed in the confirm and in chat, as in the list.
- **The class is read at load**, not at `PLAYER_LOGIN`, so an import before the login event no longer errors.
- **Refreshes are one a frame**: the panel redraws once however many talent events come, and the addon listens for `ACTIVE_COMBAT_CONFIG_CHANGED`, `PLAYER_REGEN_ENABLED` and `PLAYER_REGEN_DISABLED`, so the Apply button turns off in combat and on again after it. An event name the game doesn't have is said in chat; registering it used to fail without a word.
- **The trainer's reset message** is said when the reset is accepted, not when the dialog comes up (a cancelled dialog says nothing), and counts the points Apply would spend, from the game's own count, not from the level.
- **The reader keeps to the site's** (`build-code.js`): a name is cut to 40 characters with the site's note (and on export, as the site's writer does), a name that isn't UTF-8 is refused, a version is 1 to 3 digits and a game build 1 to 8, Unicode spaces collapse as ASCII ones do, and a long run of dots no longer takes quadratic time (forever-armoury #926). The code's format and version are as they were.
- **A trait function the client lacks** is said in chat once, by name, and the addon carries on without it, instead of a Lua error.
- **Saved builds are checked at load**: one that isn't a table or has no picks is dropped, and a missing name or id is repaired, with a line in chat saying so.

The leveling gear part (forever-armoury #280, `docs/gear-route.md`):

- **Gear routes from the site**: the Leveling plate's route for a class, spec and side, as a `FAG1-` code pasted into the import box (one paste can hold a build code and a gear code). Routes are kept for the account by class, one per spec and side.
- **The panel beside the character window**: the pieces of the route to get at your level, each marked when you wear or carry it, then the ones coming, each as the game's item link with where it comes from (the dungeon and boss, or the quest). The route's spec is the heaviest tree of the build you follow, or one picked with the panel's button.
- `/fa gear` opens the character window with the panel, `/fa gear on|off` is the part's switch, and the settings page has it too.

## 0.3.0 (unreleased)

Fixes before the first release (forever-armoury #1535):

- **Apply** no longer refuses before anything is staged: the game's `CanChangeTalents` is only true once changes are, so it's asked after the first point, and a no rolls back.
- **A commit the game fails after it starts** (its cast) is rolled back, and chat says so.
- **Import keeps each build's game build**, so Export gives a build back as it came: a `FAT2-<build>-` code for each game build, one per line, and `FAT1-` for a build from a `FAT1-` code.
- **The talent sort** takes each tree's grid from its own nodes, and says in chat when a talent doesn't sort into a cell (past the fourth column or the seventh row, or on a cell another has). `/fa debug` prints each node's position, each tree's spacing and first column, and what was left out and why.
- **The active config** falls back to the active spec group's when `GetActiveConfigID` has no answer, as the talent window does.
- **Build names encode the same under every locale**: the encoder spelt letters and digits with `%w`, which takes bytes above 127 for letters under a UTF-8 locale.
- **Talented**: the first point's level is 10 minus the perk's rank, read from the game, for the next talent's level, what Apply can spend and the trainer reset's count.
- `LICENSE` (MIT), `.pkgmeta` for the CurseForge packager, and the version from the git tag.
- `scripts/release.sh` builds and checks the release zip from a tag, and uploads it to CurseForge on a flag (forever-armoury #1537).

## 0.2.0 (unreleased)

- **Apply**: spends your unspent points as the build you follow says, in order, after one confirm; all or none.
- **Swap**: following a build your points don't fit names the points it lacks, and says whether your other spec fits it or a trainer reset is needed. At the trainer's reset, the addon says how many points Apply will spend afterwards.
- `/fa apply` and `/fa debug`.
- Build codes carry the game build the talents are from (`FAT2-70170-…`, forever-armoury #1215), so the site opens a code on the right trees; `FAT1-` codes still read.

## 0.1.0 (unreleased)

- First version: import build codes from the site, a build list beside the talent window, the next talent of the build you follow lit in the trees, export back to the site, and the level plan part's switch.
