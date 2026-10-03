# Forever Armoury (addon)

Your [Forever Armoury](https://foreverarmoury.app) talent builds in the game. Copy a build on the site (**Copy for addon**, in the calculator's build menu or the character's Talent builds picker), paste it into the addon, and the next talent of the build you follow lights up in the talent window.

The addon is made of parts, each with its own switch in its settings. The **level plan** is the first; macros and the UI layout may follow.

## Install

Copy the folder into `World of Warcraft\_forever_\Interface\AddOns\ForeverArmoury` (the folder's name has to be `ForeverArmoury`), or install it from CurseForge once it's listed there.

## Use

- `/fa` opens the talent window, with the addon's panel beside it: your builds for this class, the one you follow marked, and its next talent named and lit in the trees. Click a build to follow it; the **x** beside it forgets it.
- **Import** (or `/fa import`) opens the box to paste a code into. One paste can hold every build of a class, or several codes.
- **Export** (or `/fa export`) puts the code for every build of your class in the box, to paste into the site's Import box.
- `/fa plan off` turns the level plan part off; `/fa options` opens the settings.

A build is kept for the account, so every character of its class can follow it. Pasting a build again, after changing it on the site, updates the one with that name.

## The code

```
FAT1-warrior-Arms%20PvP-0a0a0a0b0b0b1c
FAT <version> - <class> - <name> - <picks> { . <class> - <name> - <picks> }
```

The site writes it (`public/content/build-code.js` in forever-armoury) and `BuildCode.lua` reads it. The picks are the build's points in the order spent, two characters each: the tree, then the talent's cell (tier and column).

## The Forever client

The Forever client (Blizzard's game type `camelot`, 1.60.x, interface `16001`) keeps its talents in the trait system that retail's talent trees use, not in the old `GetTalentInfo` API, which it doesn't have at all (checked in Blizzard's UI source for 1.60.1). So:

- The talent window is `PlayerSpellsFrame.TalentsFrame` (`Blizzard_PlayerSpells`, loaded on demand), and each talent is a trait node with a position. `Talents.lua` sorts the nodes of each tree into columns and rows by position, so the site's cell names the node, and the addon carries no talent data.
- Points are spent with `C_Traits.PurchaseRank` and applied with the window's Apply button (`CommitConfig`), which is what Apply (the next step) will drive.
- The client has dual spec: the window's two tabs are spec groups, each with its own trait config. The addon reads the active one.

A client that still has the old API gets the same trees from it, so the rest of the addon has one path.

## Files

- `ForeverArmoury.lua`: the namespace, saved variables, parts and their switches, `/fa`, events.
- `BuildCode.lua`: the code, read and written.
- `Talents.lua`: the game's talents as three trees of cells, and its talent window.
- `Builds.lua`: the saved builds, the character's active one, and where the character is on it (`FA.Progress`).
- `TalentUI.lua`: the panel beside the talent window, the highlight, the import box, the settings page.
- `test/run.py`: the pure parts checked in a Lua runtime with the game's talent API stubbed both ways. `pip install lupa`, then `python test/run.py`.

## Still to settle

- **In the beta**: that the nodes' positions sort into the same rows and columns as the site's trees (`/fa` with a build pasted shows which talent is lit), the panel's place beside the window, and the highlight's look on the new round buttons.
- **Apply and Swap** (spending the build's points with one click, and swapping builds after a trainer reset or with dual spec) wait on the beta checks listed in forever-armoury#280.
- **Licence** and the **CurseForge** listing.
