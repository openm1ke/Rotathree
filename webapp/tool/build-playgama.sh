#!/usr/bin/env bash
# Builds the archive for Playgama (developer.playgama.com, or its MCP:
# start_archive_upload → PUT → confirm_archive_upload).
#
#   1. `vite build --mode playgama` puts Playgama Bridge on the page and keeps
#      saves, language, pause, sound and ads on it (src/platform/playgama.ts).
#   2. The archive carries the game only: no privacy page, no install files,
#      no links to the site, the stores, the music sources or the author.
#   3. playgama-bridge-config.json goes next to index.html, where Bridge
#      looks for it.
#   4. The checks below follow Playgama's game checklist; any failure stops
#      the script before an archive is written.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/^version: *//p' ../pubspec.yaml | tr '+' '-')"
OUT_DIR="../build/releases/playgama"
OUT="$OUT_DIR/rotathree-playgama-$VERSION.zip"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

npm run build:playgama
cp -R dist-playgama/. "$STAGE/"
find "$STAGE" -name '.DS_Store' -delete

fail() { echo "! $*" >&2; exit 1; }

[[ -f "$STAGE/index.html" ]] || fail "index.html is not at the archive root"
[[ -f "$STAGE/playgama-bridge-config.json" ]] || fail "playgama-bridge-config.json is not at the archive root"
grep -q 'bridge.playgama.com/v2/stable/playgama-bridge.js' "$STAGE/index.html" \
  || fail "Playgama Bridge is not on the page"

# Partner sites serve the archive from their own domains: a file name with a
# space or a non-Latin letter is a broken asset there.
if find "$STAGE" | LC_ALL=C grep -q '[^A-Za-z0-9._/+-]'; then
  find "$STAGE" | LC_ALL=C grep '[^A-Za-z0-9._/+-]' >&2
  fail "file names outside Latin letters, digits, dot, dash and underscore"
fi

# Everything the game needs ships inside: only Bridge comes from outside.
if grep -oE '(src|href)="https?://[^"]+"' "$STAGE/index.html" | grep -v 'bridge.playgama.com' | grep -q .; then
  grep -oE '(src|href)="https?://[^"]+"' "$STAGE/index.html" >&2
  fail "index.html loads something from outside the archive"
fi
if grep -rqE 'url\(["'"'"']?https?://' "$STAGE" --include='*.css'; then
  fail "a stylesheet loads something from outside the archive"
fi

# No external analytics, and nothing that links out of the game.
if grep -rqE 'mc\.yandex\.ru|googletagmanager|google-analytics|metrika' "$STAGE" --include='*.js' --include='*.html'; then
  fail "the archive carries an analytics loader"
fi
FORBIDDEN='github\.(io|com)|openm1ke|mailto:|opengameart|creativecommons|rustore|apps\.apple\.com|play\.google\.com|yandex\.ru|vk\.com|muxaujish'
if grep -rlE "$FORBIDDEN" "$STAGE" --include='*.html' --include='*.js' --include='*.css' --include='*.svg' --include='*.json' | grep -q .; then
  grep -rnoE "$FORBIDDEN" "$STAGE" --include='*.html' --include='*.js' --include='*.css' --include='*.svg' --include='*.json' >&2
  fail "the archive still links out"
fi
if grep -rqE '<a [^>]*href=|target="_blank"|target:"_blank"' "$STAGE" --include='*.html' --include='*.js'; then
  fail "the archive still has a link that opens a page"
fi

SIZE=$(du -sk "$STAGE" | cut -f1)
(( SIZE < 300 * 1024 )) || fail "the archive is over 300 MB"

mkdir -p "$OUT_DIR"
rm -f "$OUT"
(cd "$STAGE" && zip -qr -X "$OLDPWD/$OUT" . -x '.*')
shasum -a 256 "$OUT" | awk '{print $1}' > "$OUT.sha256"

echo
echo "$OUT"
unzip -l "$OUT" | tail -1
du -h "$OUT" | cut -f1 | sed 's/^/size: /'
echo "sha256: $(cat "$OUT.sha256")"
echo "hosts named in the code (not loaded, for review):"
grep -rhoE 'https?://[a-z0-9.-]+' "$STAGE" --include='*.js' --include='*.html' | sort | uniq -c | sort -rn
