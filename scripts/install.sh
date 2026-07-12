#!/usr/bin/env bash
set -euo pipefail

REPO="lordydord/fan"
APP_NAME="fan"
INSTALL_PATH="/Applications/fan.app"
ARCHIVE="/tmp/fan-latest.zip"
WORK_DIR="/tmp/fan-install"

printf 'fan installer\n\n'

LATEST_TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -n 1)"
if [[ -z "$LATEST_TAG" ]]; then
  printf 'Could not determine the latest release.\n' >&2
  exit 1
fi

DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_TAG/fan-1.0.0-macos.zip"
printf 'Downloading %s...\n' "$LATEST_TAG"
curl -fL "$DOWNLOAD_URL" -o "$ARCHIVE"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
ditto -x -k "$ARCHIVE" "$WORK_DIR"

if [[ ! -d "$WORK_DIR/$APP_NAME.app" ]]; then
  printf 'The downloaded archive does not contain fan.app.\n' >&2
  exit 1
fi

printf 'Installing fan in Applications...\n'
rm -rf "$INSTALL_PATH"
ditto "$WORK_DIR/$APP_NAME.app" "$INSTALL_PATH"

HELPER="$INSTALL_PATH/Contents/Resources/smc-helper"
if [[ -x "$HELPER" ]]; then
  printf 'Installing the fan-control helper. Administrator approval is required.\n'
  sudo mkdir -p /usr/local/bin
  sudo cp "$HELPER" /usr/local/bin/smc-helper
  sudo chown root:wheel /usr/local/bin/smc-helper
  sudo chmod 4755 /usr/local/bin/smc-helper
fi

rm -rf "$WORK_DIR" "$ARCHIVE"
open "$INSTALL_PATH"
printf '\nfan is installed and running.\n'
