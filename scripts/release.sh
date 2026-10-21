#!/usr/bin/env bash
# Releasing the addon from this machine (forever-armoury#1537), while GitHub Actions is off. It builds the zip with
# the BigWigs packager (github.com/BigWigsMods/packager) from a git tag, checks what is in it, and uploads to
# CurseForge only when asked. See "Releasing" in README.md.
#
#   scripts/release.sh             build the zip from the tag at HEAD, list it and check it; uploads nothing
#   scripts/release.sh --upload    the same, then upload it to CurseForge (needs the project ID and CF_API_TOKEN)
#
# It stops unless: the tree is clean, you are on main, HEAD has a tag vX.Y.Z (git tag -a v0.3.0), and the zip is
# one ForeverArmoury/ folder of the .toc, Lua files (and Data/'s), LICENSE and CHANGELOG.md, with the tag's version
# in the .toc and nothing from test/, scripts/, tools/ or the README. For --upload the tag and main must also be on
# GitHub, the .toc must carry the CurseForge project ID, and CF_API_TOKEN must be set (in .release/.env, or the
# environment).
#
# The packager is fetched into .release/ (gitignored) at a pinned version and checked against its hash.
# It needs bash 4.3 or newer, which macOS doesn't ship: brew install bash.
# Runs with macOS's bash 3.2.
set -euo pipefail

PACKAGER_REF=${PACKAGER_REF:-v2.6.1}
PACKAGER_SHA256=${PACKAGER_SHA256:-59b15a8d851b09e6d0fdec702aec91331b9b49d84dbe778da6c621b48f268703}
ADDON=ForeverArmoury
TAG_FORMAT='^v[0-9]+\.[0-9]+\.[0-9]+$'

fail() { echo "✗ $1" >&2; exit 1; }
say() { echo; echo "→ $1"; }
usage() { sed -n "2,17p" "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

UPLOAD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --upload) UPLOAD=1; shift;;
    -h|--help) usage;;
    *) echo "Unknown option: $1" >&2; usage 1;;
  esac
done

cd "$(dirname "$0")/.."
ROOT=$(pwd)
RELEASE_DIR=$ROOT/.release

say "Checking the checkout"
[ -z "$(git status --porcelain)" ] || fail "the tree isn't clean (commit or stash first):
$(git status --short)"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = main ] || fail "on '$BRANCH', not main"
TAGS=$(git tag --points-at HEAD | grep -E "$TAG_FORMAT" || true)
[ -n "$TAGS" ] || fail "HEAD has no tag like v0.3.0 (git tag -a v0.3.0 -m 'Forever Armoury 0.3.0')"
[ "$(echo "$TAGS" | wc -l | tr -d ' ')" = 1 ] || fail "HEAD has more than one version tag: $(echo $TAGS)"
TAG=$TAGS
VERSION=${TAG#v}
echo "main at $(git rev-parse --short HEAD), tag $TAG"

grep -q '^## Interface: 16001$' "$ADDON.toc" || fail "$ADDON.toc isn't Interface 16001 (the Forever client)"
grep -q '^## Version: @project-version@$' "$ADDON.toc" || fail "$ADDON.toc's Version line isn't @project-version@"
TOC_ID=$(sed -n 's/^## X-Curse-Project-ID:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$ADDON.toc" | head -n1)

# A bash the packager can run with.
BASH4=
for b in "$(command -v bash || true)" /opt/homebrew/bin/bash /usr/local/bin/bash; do
  [ -x "$b" ] || continue
  if "$b" -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]; }' 2>/dev/null; then
    BASH4=$b
    break
  fi
done
[ -n "$BASH4" ] || fail "the packager needs bash 4.3 or newer; macOS has 3.2. brew install bash"

say "The packager ($PACKAGER_REF)"
mkdir -p "$RELEASE_DIR"
PACKAGER=$RELEASE_DIR/release.sh
if [ ! -f "$PACKAGER" ]; then
  curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_REF/release.sh" -o "$PACKAGER.tmp" \
    || { rm -f "$PACKAGER.tmp"; fail "couldn't fetch the packager's release.sh at $PACKAGER_REF"; }
  mv "$PACKAGER.tmp" "$PACKAGER"
  echo "fetched into .release/release.sh"
fi
GOT=$(shasum -a 256 "$PACKAGER" | cut -d' ' -f1)
[ "$GOT" = "$PACKAGER_SHA256" ] || fail ".release/release.sh isn't the pinned $PACKAGER_REF (sha256 $GOT). Delete it to fetch it again, or set PACKAGER_REF and PACKAGER_SHA256 to move to another version."

if [ -f "$RELEASE_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$RELEASE_DIR/.env"
  set +a
  echo "read .release/.env"
fi

if [ "$UPLOAD" = 1 ]; then
  say "Checking the upload"
  [ -n "$TOC_ID" ] || fail "$ADDON.toc has no '## X-Curse-Project-ID: <number>' line: create the CurseForge project and put its ID in (README: Releasing)"
  [ -n "${CF_API_TOKEN:-}" ] || fail "CF_API_TOKEN isn't set: put CF_API_TOKEN=... in .release/.env"
  command -v jq >/dev/null || fail "the packager needs jq to upload (brew install jq)"
  git fetch --quiet origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main isn't the same as origin/main: push it (or pull it) first"
  REMOTE_TAG=$(git ls-remote --tags origin "refs/tags/$TAG^{}" "refs/tags/$TAG" | awk '{print $1}' | tail -n1)
  [ "$REMOTE_TAG" = "$(git rev-parse "$TAG^{commit}")" ] || fail "tag $TAG isn't on GitHub at this commit: git push origin $TAG"
  echo "project $TOC_ID, token set, $TAG pushed"
fi

say "Building $ADDON-$TAG.zip"
rm -rf "${RELEASE_DIR:?}/$ADDON" "$RELEASE_DIR/$ADDON"-*.zip
FLAGS=(-n "{package-name}-{project-version}:{project-version}")
if [ "$UPLOAD" = 1 ]; then
  # CurseForge only: leave out the other sites' tokens if they happen to be in the environment.
  unset WOWI_API_TOKEN WAGO_API_TOKEN GH_API_TOKEN GITHUB_API_TOKEN GITHUB_OAUTH
else
  FLAGS+=(-d)
fi
(cd "$ROOT" && "$BASH4" "$PACKAGER" "${FLAGS[@]}") || fail "the packager failed"

ZIP=$RELEASE_DIR/$ADDON-$TAG.zip
[ -s "$ZIP" ] || fail "no $ZIP was built: $(ls "$RELEASE_DIR"/*.zip 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"

say "The zip: $(basename "$ZIP")"
unzip -l "$ZIP"

say "Checking the zip"
NAMES=$(unzip -Z1 "$ZIP")
TOP=$(echo "$NAMES" | sed 's#/.*##' | sort -u)
[ "$TOP" = "$ADDON" ] || fail "the zip should hold the one folder $ADDON/, but holds: $(echo $TOP)"
EXPECT=$(cd "$ROOT" && git ls-files -- ':(glob)*.lua' ':(glob)Data/*.lua' ':(glob)*.toc' LICENSE CHANGELOG.md | sed "s#^#$ADDON/#" | sort)
GOT=$(echo "$NAMES" | grep -v '/$' | sort)
if [ "$GOT" != "$EXPECT" ]; then
  fail "the zip's files aren't the .toc, Lua files, Data/, LICENSE and CHANGELOG.md:
zip has, repo doesn't: $(comm -23 <(echo "$GOT") <(echo "$EXPECT") | tr '\n' ' ')
repo has, zip doesn't: $(comm -13 <(echo "$GOT") <(echo "$EXPECT") | tr '\n' ' ')"
fi
echo "$NAMES" | grep -Eiq '(^|/)(test|scripts|tools|README|\.git|\.release|\.venv)' && fail "the zip holds something that should stay out"
TOC_VERSION=$(unzip -p "$ZIP" "$ADDON/$ADDON.toc" | sed -n 's/^## Version:[[:space:]]*//p' | tr -d '\r')
[ "$TOC_VERSION" = "$TAG" ] || fail "the zip's .toc says Version '$TOC_VERSION', not '$TAG'"
! unzip -p "$ZIP" | grep -q '@project-version@' || fail "'@project-version@' is still in the zip"
echo "✓ one $ADDON/ folder, $(echo "$GOT" | wc -l | tr -d ' ') files, no test/scripts/tools/README, Version $TOC_VERSION"

if [ "$UPLOAD" = 1 ]; then
  say "Uploaded $(basename "$ZIP") to CurseForge project $TOC_ID: check the page installs."
else
  say "Dry run: nothing uploaded. scripts/release.sh --upload to upload $(basename "$ZIP")."
fi
