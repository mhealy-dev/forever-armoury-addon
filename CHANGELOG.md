# Changelog

## 0.3.0 (unreleased)

The leveling gear part (forever-armoury #280, `docs/gear-route.md`):

- **Gear routes from the site**: the Leveling plate's route for a class, spec and side, as a `FAG1-` code pasted into the import box (one paste can hold a build code and a gear code). Routes are kept for the account by class, one per spec and side.
- **The panel beside the character window**: the pieces of the route to get at your level, each marked when you wear or carry it, then the ones coming, each as the game's item link with where it comes from (the dungeon and boss, or the quest). The route's spec is the heaviest tree of the build you follow, or one picked with the panel's button.
- `/fa gear` opens the character window with the panel, `/fa gear on|off` is the part's switch, and the settings page has it too.

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
