# Forever Armoury (addon)

Your [Forever Armoury](https://foreverarmoury.app) talent builds in the game. Copy a build on the site (**Copy for addon**, in the calculator's build menu or the character's Talent builds picker), paste it into the addon, and the next talent of the build you follow lights up in the talent window.

The addon is made of parts, each with its own switch in its settings. The **level plan** is the first; macros and the UI layout may follow.

## Install

Copy the folder into `World of Warcraft\_forever_\Interface\AddOns\ForeverArmoury` (the folder's name has to be `ForeverArmoury`), or install it from CurseForge once it's listed there.

## Use

- `/fa` opens the talent window, with the addon's panel beside it: your builds for this class, the one you follow marked, and its next talent named and lit in the trees. Click a build to follow it; the **x** beside it forgets it.
- **Import** (or `/fa import`) opens the box to paste a code into. One paste can hold every build of a class, or several codes.
- **Export** (or `/fa export`) puts the code for every build of your class in the box, to paste into the site's Import box.
- **Apply** (or `/fa apply`) spends your unspent points as the build you follow says, in its order, after one confirm that names them. It's all or none: if the game refuses a point, nothing is spent. The button says how many points it would spend, or why it can't.
- `/fa plan off` turns the level plan part off; `/fa options` opens the settings; `/fa debug` lists every talent by tree, row and column as the addon reads them.

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
- Apply stages each point with `C_Traits.PurchaseRank` and applies them with `C_ClassTalents.CommitConfig()`, as the window's own Apply button does; if a point is refused, or the commit is, `C_Traits.RollbackConfig` drops everything staged. It won't start while the window has changes of its own waiting, or in combat.
- The client has dual spec: the window's two tabs are spec groups, each with its own trait config (`C_SpecializationInfo.GetCombatConfigIDForSpecGroup`). The addon follows the active one and reads the other for Swap.

A client that still has the old API gets the same trees from it, so the rest of the addon has one path.

## Files

- `ForeverArmoury.lua`: the namespace, saved variables, parts and their switches, `/fa`, events.
- `BuildCode.lua`: the code, read and written.
- `Talents.lua`: the game's talents as three trees of cells for either spec, spending points, and the talent window.
- `Builds.lua`: the saved builds, the character's active one, where a spec is on it (`FA.Progress`), and what Apply and Swap do.
- `TalentUI.lua`: the panel beside the talent window, the highlight, Apply's confirm, the import box, the settings page.
- `test/run.py`: everything checked in LuaJIT (the game's Lua 5.1) against a stub of the game: both talent APIs, the trait system's staging with tier gates, commit and rollback, dual spec, combat, and the panel drawn against a mock of the frame API. `pip install lupa`, then `python test/run.py`.

## Still to settle

- **In the beta**: that the nodes' positions sort into the same rows and columns as the site's trees (`/fa debug`), that Apply's purchases and commit go through from an addon outside the window, the panel's place beside the window, and the highlight's look on the round buttons.
- **Licence** and the **CurseForge** listing.
