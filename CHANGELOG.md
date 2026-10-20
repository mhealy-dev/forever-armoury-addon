# Changelog

## 0.5.0 (unreleased)

The Talented rank in the build code (forever-armoury #1540):

- **`FAT3-` codes**: each build ends with its rank of the Legacy perk Talented, one digit 0 to 5 (`FAT3-70170-warrior-Arms%20PvP-0a0a0a0b0b0b1c1c-3`), as the site now writes them. `FAT1-` and `FAT2-` codes still read, with rank 0. A rank that isn't 0 to 5 is refused with a sentence, as the site does.
- **Import keeps the rank** with the saved build, and Export writes a `FAT3-` code with each build's rank. A build from a `FAT1-` or `FAT2-` code exports with rank 0 (a `FAT1-` build's game build is written as 0, which the site reads as the first trees).
- **The first point's level** is 10 minus the rank the game says, as before; when the game won't say (the Legacy config can't be read) the build's own rank is used, and 10 when neither is known. `/fa debug` says which rank is in use and where it came from.

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
