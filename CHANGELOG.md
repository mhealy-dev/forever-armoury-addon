# Changelog

## 0.6.0 (2026-10-25)

The first release. Forever Armoury brings your plans from [foreverarmoury.app](https://foreverarmoury.app) into the game: plan on the site, choose **Copy for addon**, then type `/fa import` in the game and paste. Install it with the CurseForge app, or unzip it into your AddOns folder as `ForeverArmoury`.

### Talents

- **Your build beside the talent window.** Paste a build code from the site (it starts `FAT3-`; older `FAT2-` and `FAT1-` codes read too). `/fa` opens the talent window with your builds listed beside it. Click a build to follow it, or the **x** to forget it.
- **A strip of icons in the build's order.** The points you took are faded with a green check. The next one glows with a gold border and says **Now** when you can take it, or the level it comes at. The rest show their levels. Scroll with the mouse wheel when the build is longer than the window.
- **Hover an icon** to light that talent in the tree and see its tooltip.
- **Click the next icon** to take that point. **Shift-click** it, or press **Apply** (`/fa apply`), to spend every point that's due after one confirm. If the game refuses a point, nothing is spent. When a click can't work, in combat for one, the tooltip says why.
- **Talented.** With the Legacy perk Talented your first talent point comes earlier, and the build's levels move to match.
- **Changing builds.** If your points don't fit the build you pick, the addon names the points in the way and tells you whether your other spec fits it or you need a trainer reset. When you accept the reset, it says how many points Apply will spend afterwards.
- **Builds are kept for your account**, so every character of the class can follow them. Two builds with the same name and different points stay two builds.
- **Export** (`/fa export`) gives your class's builds back as codes for the site's Import box.
- If a build has a talent the addon can't find in your trees, it shows the rest of the build and tells you which talent is missing.

### Leveling gear

- **Every route is built in.** The site's leveling routes for every class, spec and side ship with the addon, so `/fa gear` works with nothing pasted. It opens the character window with the route beside it.
- **To get now** lists the pieces for your level that you don't wear or carry yet, each with where it drops: the dungeon and boss, or the quest. **Coming** lists the pieces for later levels.
- **Forever's own loot is on the routes**, from places like the Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands and City of Dalaran.
- **Hover a piece** for its tooltip, with the comparison to what you wear beside it. **Shift-click** to link it in chat.
- **Your spec** follows the build you follow. With no build, the spec button picks one.
- **A route from the site** (a `FAG1-` code) takes over from the built-in one for its class, spec and side. Use it when the site has changed a route since this release.

### Legacy

- **Your Legacy plan beside the Legacy window.** On the site's Legacy tab, choose **Copy for addon** and paste the `FAL1-` code. Plans are kept for your whole account. `/fa legacy` opens the Legacy window on its trees with the plan beside it.
- **The panel** shows each perk the plan wants with the ranks you have, your Legacy points, how much of the season's cap you've spent, and the next perk to buy, lit in the tree.
- **A strip of icons** shows the perks in the order they're bought. The next one says **Now** when you have a point to spend, or **wait**. The ones coming show their tree: **Prof**, **Adv** or **Res**.
- **Click the next icon** to buy that rank. If it's in another tree, the window switches to it first. **Shift-click**, or press **Apply**, to buy everything that's due across all three trees after one confirm.
- **Apply is all or none in each tree.** If a tree's purchase fails, that tree goes back as it was and the others keep theirs. It stops at the points you have and the cap, and it never takes points back.
- A plan made for a different version of the game is shown, but never bought.
- **Export** gives your Legacy plans back as codes.

### The windows and commands

- **The FA button** at the top right of the talent, character and Legacy windows hides the addon's panel and brings it back. If that part is switched off, the button turns it on.
- The panels and strips fit the height of their windows, and long lists scroll.
- **Settings** (`/fa options`) has a switch for each part, the icon size, and how many points the strip shows before and after the next one.
- **Commands:** `/fa`, `/fa gear`, `/fa legacy`, `/fa import`, `/fa export`, `/fa apply`, `/fa options`, `/fa debug`. Each part also has a switch: `/fa plan off`, `/fa gear off`, `/fa legacy off`, and `on` to bring it back.

New, built on the Forever beta. Something off? [Tell us on GitHub](https://github.com/mhealy-dev/forever-armoury-addon/issues) with what `/fa debug` says.
