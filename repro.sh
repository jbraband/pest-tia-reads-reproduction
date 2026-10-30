#!/usr/bin/env bash
# Shows the bug on stock Pest, then the same steps with patches/read-capture.patch applied.
# Needs PCOV or Xdebug (coverage mode), and a committed git working tree.
set -euo pipefail

# Without a coverage driver Pest skips TIA and every --tia run is a full run.
if ! php -m | grep -qiE '^(pcov|xdebug)$'; then
    echo "PCOV or Xdebug is not loaded (php -m), so Pest would skip TIA. Install one and re-run." >&2
    exit 1
fi

[ -f .env ] || cp .env.example .env

PATCH=patches/read-capture.patch
PEST_DIR=vendor/pestphp/pest
VIEW=resources/views/welcome.blade.php
patched=0

restore() {
    git checkout -q -- "$VIEW"
    if [ "$patched" = 1 ]; then
        git apply -R --directory="$PEST_DIR" "$PATCH"
    fi
}
trap restore EXIT

edit_view() {
    php -r '$f = $argv[1]; file_put_contents($f, str_replace("<meta name=\"viewport\"", "<meta name=\"x-viewport\"", file_get_contents($f)));' "$VIEW"
    git --no-pager diff -- "$VIEW"
}

echo "== BUG (stock Pest)"
echo "== 1. record a fresh baseline"
vendor/bin/pest --tia --fresh

echo "== 2. edit $VIEW: rename the viewport meta tag"
edit_view

echo "== 3. --tia: expected ConventionsTest re-run and failed, actual it replays (1 affected, 2 replayed)"
vendor/bin/pest --tia || true

echo "== 4. plain run: ConventionsTest fails"
vendor/bin/pest || true

echo "== FIX ($PATCH applied to $PEST_DIR)"
git checkout -q -- "$VIEW"
git apply --directory="$PEST_DIR" "$PATCH"
patched=1

echo "== 5. record a fresh baseline"
vendor/bin/pest --tia --fresh

echo "== 6. same edit"
edit_view

echo "== 7. --tia: 2 affected, ConventionsTest fails"
vendor/bin/pest --tia || true
