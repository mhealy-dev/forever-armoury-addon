#!/usr/bin/env python3
"""Writes Data/Routes.lua, the leveling gear routes the addon ships (forever-armoury#1591), from the site's route files.

    python3 -I tools/routes.py                  reads origin/main of ~/arda/shire/forever-armoury
    python3 -I tools/routes.py --site PATH      another checkout of the site
    python3 -I tools/routes.py --ref REF        another ref of it (a tag, a commit)

It reads public/content/route/<class>.json for the nine classes with `git show` (so the checkout's working tree doesn't
matter; `git fetch origin` there first for the latest), and stops, writing nothing, on anything it doesn't know: a class
without a file, a route that isn't one of the three specs on both sides, a piece with a slot or a source kind the addon
has no number for. A later site script (forever-armoury#1568) is meant to write this file; until then this does.

The file keeps a piece as numbers, to stay small: { id, level, slot, kind, ... }, the slot being the place in
GearCode.SLOTS and the kind 1 (a drop: dungeon, npc) or 2 (a quest: quest). Gear.lua turns one into the
{ id, level, slot, from } the site's files and the pasted codes have. Python 3 standard library only."""
import argparse
import datetime
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLASSES = ("druid", "hunter", "mage", "paladin", "priest", "rogue", "shaman", "warlock", "warrior")
SIDES = ("alliance", "horde")
SPECS = (0, 1, 2)
# the same order as GearCode.SLOTS; test/run.py checks they agree
SLOTS = ("head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
         "finger1", "finger2", "trinket1", "trinket2", "mainhand", "offhand", "ranged")
KINDS = {"drop": (1, 2), "quest": (2, 1)}   # a source's number, and how many ids follow it


def git(site, *args):
    return subprocess.run(["git", "-C", site, *args], check=True, capture_output=True, text=True).stdout


def number(value, what):
    """An id the site writes as a string or a number, as a whole number above 0."""
    try:
        n = int(value)
    except (TypeError, ValueError):
        n = 0
    if n < 1 or str(n) != str(value).strip():
        raise SystemExit("%s: %r isn't a whole number above 0" % (what, value))
    return n


def piece(p, where):
    if p.get("slot") not in SLOTS:
        raise SystemExit("%s: slot %r isn't one of GearCode.SLOTS" % (where, p.get("slot")))
    source = p.get("from") or []
    if not source or source[0] not in KINDS:
        raise SystemExit("%s: source %r isn't a drop or a quest" % (where, source))
    kind, count = KINDS[source[0]]
    if len(source) != count + 1:
        raise SystemExit("%s: a %s source has %d ids, not %d" % (where, source[0], count, len(source) - 1))
    level = number(p.get("level"), where + " level")
    if level > 60:
        raise SystemExit("%s: level %d is over 60" % (where, level))
    ids = [number(x, where + " source") for x in source[1:]]
    nums = [number(p.get("id"), where + " id"), level, SLOTS.index(p["slot"]) + 1, kind] + ids
    return "{" + ",".join(str(n) for n in nums) + "}"


def main():
    ap = argparse.ArgumentParser(description="Writes Data/Routes.lua from the site's route files.")
    ap.add_argument("--site", default=os.path.expanduser("~/arda/shire/forever-armoury"), help="the site's checkout")
    ap.add_argument("--ref", default="origin/main", help="the ref of it to read")
    ap.add_argument("--out", default=os.path.join(ROOT, "Data", "Routes.lua"))
    args = ap.parse_args()

    commit = git(args.site, "rev-parse", args.ref).strip()
    lines, pieces, routes = [], 0, 0
    for cls in CLASSES:
        data = json.loads(git(args.site, "show", "%s:public/content/route/%s.json" % (args.ref, cls)))
        if data.get("class") != cls:
            raise SystemExit("%s.json is for class %r" % (cls, data.get("class")))
        by = {}
        for r in data["routes"]:
            key = (r.get("spec"), r.get("side"))
            if key[0] not in SPECS or key[1] not in SIDES or key in by:
                raise SystemExit("%s: route %r is not a new spec 0 to 2 and a side" % (cls, key))
            by[key] = r
        missing = [(s, d) for s in SPECS for d in SIDES if (s, d) not in by]
        if missing:
            raise SystemExit("%s has no route for %s" % (cls, missing))
        lines.append("%s = {" % cls)
        for spec in SPECS:
            lines.append("[%d] = {" % spec)
            for side in SIDES:
                rows = [piece(p, "%s %d %s #%d" % (cls, spec, side, i + 1)) for i, p in enumerate(by[(spec, side)]["pieces"])]
                if not rows:
                    raise SystemExit("%s %d %s has no pieces" % (cls, spec, side))
                routes, pieces = routes + 1, pieces + len(rows)
                lines.append("%s = {\n%s\n}," % (side, ",\n".join(rows)))
            lines.append("},")
        lines.append("},")

    header = """--[[ The leveling gear routes the addon ships (forever-armoury#1591): the site's public/content/route/<class>.json for
     every class, %d routes (3 specs, both sides) of %d pieces. Written by tools/routes.py: don't edit it, run
     python3 -I tools/routes.py.

     Site commit %s
     Written %s

     FA.RouteData.routes[class][spec][side] is a list of pieces, each numbers: { id, level, slot, kind, ... }, with the
     slot the place in FA.GearCode.SLOTS (1 head ... 17 ranged), and the kind 1 for a drop, then the dungeon's map id
     and the boss's NPC id, or 2 for a quest, then the quest's id. Gear.lua turns one into { id, level, slot, from }. ]]

local _, FA = ...
FA.RouteData = { routes = {
""" % (routes, pieces, commit, datetime.date.today().isoformat())
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(header + "\n".join(lines) + "\n} }\n")
    print("%s: %d routes, %d pieces, %d bytes, site %s" % (os.path.relpath(args.out, ROOT), routes, pieces, os.path.getsize(args.out), commit[:9]))


if __name__ == "__main__":
    sys.exit(main())
