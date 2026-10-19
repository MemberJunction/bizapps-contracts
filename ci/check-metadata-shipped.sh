#!/usr/bin/env bash
#
# The installer runs migrations. It never reads metadata/. So a metadata change reaches a
# customer ONLY through a hand-written `*__Metadata_Sync.sql` migration — the convention this
# repo already follows. Nothing verified that one was written, so metadata could change, pass
# every check, bump the version, publish, and reach nobody.
#
# This is a GATE check, not a door one, deliberately: a feature PR may legitimately land
# metadata before its sync migration is written. What must be true is that by release time,
# every substantive metadata change since the last release has one.
set -euo pipefail

. "$(dirname "$0")/lib/release-surface.sh"

LAST_TAG=$(git tag --list 'v*' --sort=-v:refname | head -1)
if [ -z "$LAST_TAG" ]; then
  echo "No v* tag yet — nothing to compare against"
  exit 0
fi

METADATA=$(substantive_metadata_changes "$LAST_TAG" HEAD || true)
if [ -z "$METADATA" ]; then
  echo "No substantive metadata change since $LAST_TAG — nothing to ship"
  exit 0
fi

SYNC=$(git --no-pager diff --name-only --diff-filter=A "$LAST_TAG" HEAD -- migrations/ \
       | grep -iE 'metadata_sync.*\.sql$' || true)
if [ -n "$SYNC" ]; then
  # A sync migration existing is not enough: it carries metadata/ as it was when the sync was
  # generated. A metadata change merged after that point reaches nobody, and the check used to
  # pass anyway (issue #112: a TemplateRequired change landed after the release's sync was
  # generated). So every changed file must read the same, ignoring sync bookkeeping, at the
  # commit that added the newest sync migration as it does at HEAD. A file gone at HEAD is
  # skipped: a regenerated sync is built from metadata/ as it is, so it could not carry a removal.
  SYNC_COMMIT=$(printf '%s\n' "$SYNC" | xargs git log -1 --format=%H --diff-filter=A "$LAST_TAG..HEAD" --)
  STALE=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    git cat-file -e "HEAD:$file" 2>/dev/null || continue
    at_sync=$(git show "$SYNC_COMMIT:$file" 2>/dev/null | normalize_metadata_json 2>/dev/null || echo "<absent>")
    at_head=$(git show "HEAD:$file" 2>/dev/null | normalize_metadata_json 2>/dev/null || echo "<absent>")
    [ "$at_sync" = "$at_head" ] || STALE="${STALE}${file}"$'\n'
  done <<EOF
$METADATA
EOF

  if [ -z "$STALE" ]; then
    echo "Metadata changed since $LAST_TAG and a sync migration ships it:"
    printf '%s\n' "$SYNC" | sed 's/^/  /'
    exit 0
  fi

  echo "::error::metadata/ changed after the newest Metadata_Sync migration was generated (added in ${SYNC_COMMIT:0:12}), so the release would not carry these changes to any host. Generate a new '*__Metadata_Sync.sql' migration (and its .pg.sql counterpart) from the current metadata/. Changed since that sync:"
  printf '%s' "$STALE" | sed 's/^/  /'
  exit 1
fi

echo "::error::metadata/ changed since $LAST_TAG but no Metadata_Sync migration was added. The installer runs migrations and never reads metadata/, so these changes would publish and reach nobody. Add a '*__Metadata_Sync.sql' migration (and its .pg.sql counterpart). Metadata changed:"
printf '%s\n' "$METADATA" | sed 's/^/  /'
exit 1
