#!/bin/sh
# Mirrors a commit of this (private) repo to the public github.com/jtannahill/opentime,
# without the licensed NHG font files. Usage: scripts/sync-public.sh [ref], default HEAD.
# Runs from the pre-push hook (scripts/pre-push); safe to run by hand.
set -eu
REF="${1:-HEAD}"
SRC="$(git rev-parse --show-toplevel)"
PUB="${OPENTIME_PUBLIC_DIR:-$HOME/opentime-public}"
SHA="$(git -C "$SRC" rev-parse --short "$REF")"
SUBJECT="$(git -C "$SRC" log -1 --format=%s "$REF")"

[ -d "$PUB/.git" ] || git clone -q https://github.com/jtannahill/opentime.git "$PUB"
git -C "$PUB" pull -q --ff-only

# Replace the working tree with the commit's files, then drop the fonts.
find "$PUB" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git -C "$SRC" archive "$REF" | tar -x -C "$PUB"
rm -f "$PUB"/OpenTimeUI/Sources/OpenTimeUI/Resources/*.ttf "$PUB"/OpenTimeUI/Sources/OpenTimeUI/Resources/*.otf

if find "$PUB" -path "$PUB/.git" -prune -o \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff*' \) -print | grep -q .; then
  echo "sync-public: font files present, not publishing" >&2; exit 1
fi
if command -v gitleaks >/dev/null; then
  gitleaks dir "$PUB" --no-banner --redact >/dev/null 2>&1 || { echo "sync-public: gitleaks found something, not publishing" >&2; exit 1; }
else
  echo "sync-public: gitleaks not installed, not publishing" >&2; exit 1
fi

git -C "$PUB" add -A
if git -C "$PUB" diff --cached --quiet; then echo "sync-public: already in sync ($SHA)"; exit 0; fi
git -C "$PUB" -c user.name=jtannahill -c user.email=161522526+jtannahill@users.noreply.github.com \
  commit -q -m "$SUBJECT" -m "Synced from the private repo at $SHA."
git -C "$PUB" push -q origin main
echo "sync-public: published $SHA to github.com/jtannahill/opentime"
