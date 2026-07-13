#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: scripts/create-release.sh VERSION}"
REPO="lordydord/fan"
TAG="v$VERSION"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/releases/v$VERSION"
NOTES="$ROOT_DIR/docs/release-notes/v$VERSION.md"

if [[ ! -f "$NOTES" ]]; then
  printf 'Release notes not found: %s\n' "$NOTES" >&2
  exit 1
fi

for artifact in \
  "$ARTIFACT_DIR/fan-$VERSION-macos.zip" \
  "$ARTIFACT_DIR/fan-$VERSION-macos.zip.sha256" \
  "$ARTIFACT_DIR/fan-$VERSION-macos.dmg" \
  "$ARTIFACT_DIR/fan-$VERSION-macos.dmg.sha256"
do
  [[ -f "$artifact" ]] || { printf 'Missing artifact: %s\n' "$artifact" >&2; exit 1; }
done

gh release create "$TAG" \
  --repo "$REPO" \
  --title "Fan App $VERSION" \
  --latest \
  --notes-file "$NOTES" \
  "$ARTIFACT_DIR/fan-$VERSION-macos.zip" \
  "$ARTIFACT_DIR/fan-$VERSION-macos.zip.sha256" \
  "$ARTIFACT_DIR/fan-$VERSION-macos.dmg" \
  "$ARTIFACT_DIR/fan-$VERSION-macos.dmg.sha256"
