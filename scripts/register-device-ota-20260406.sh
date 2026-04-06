#!/bin/bash
#
# iClaw Device Registration OTA Fix Patch
# Date: 2026-04-06
# Fix: Reset registration fail count that persists across reboots
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/scottzx/iclaw-manager/master/scripts/register-device-ota-20260406.sh | bash
#

set -euo pipefail

FAIL_COUNT_FILE="/var/lib/iclaw/registration_fail_count"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

# Step 1: Clear the persistent fail count file (the bug fix)
if [[ -f "$FAIL_COUNT_FILE" ]]; then
    old_count=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo "unknown")
    rm -f "$FAIL_COUNT_FILE"
    log "Cleared registration_fail_count (previous value: $old_count)"
else
    log "No registration_fail_count file found, nothing to clear"
fi

# Step 2: Download and install the latest register-device.sh
REGISTRY_HOST="${REGISTRY_HOST:-www.dreammate.work}"
SCRIPT_URL="https://www.dreammate.work/scripts/register-device.sh"
TARGET_FILE="/usr/local/bin/register-device.sh"

log "Downloading latest register-device.sh..."

# Backup old script if exists
if [[ -f "$TARGET_FILE" ]]; then
    cp "$TARGET_FILE" "${TARGET_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    log "Backed up old script"
fi

# Download new script
if curl -fsSL "$SCRIPT_URL" -o "$TARGET_FILE"; then
    chmod +x "$TARGET_FILE"
    log "Updated register-device.sh successfully"
else
    # Fallback: try GitHub raw URL
    GITHUB_URL="https://raw.githubusercontent.com/scottzx/iclaw-manager/master/scripts/register-device.sh"
    log "Trying GitHub fallback: $GITHUB_URL"
    if curl -fsSL "$GITHUB_URL" -o "$TARGET_FILE"; then
        chmod +x "$TARGET_FILE"
        log "Updated register-device.sh from GitHub"
    else
        log "WARNING: Could not download latest script, keeping existing"
    fi
fi

# Step 3: Verify installation
if [[ -f "$TARGET_FILE" ]]; then
    log "register-device.sh installed at $TARGET_FILE"
    log "Version check:"
    head -20 "$TARGET_FILE" | grep -E "^#|VERSION|date" || true
fi

log "OTA fix patch completed successfully"
log "Device can now register again after network issues"
