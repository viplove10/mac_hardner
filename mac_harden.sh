#!/bin/bash
# mac_harden.sh — Minimal macOS hardening (macOS 12–15), with Public/Home profile and --strict
# Run with: sudo ./mac_harden.sh [--apply-updates] [--profile public|home] [--strict]
#
# What it does:
# 1) OS update check (optional install with --apply-updates; or prompt at the end)
# 2) FileVault status (opens Settings if OFF)
# 3) Firewall on + stealth (Block All Incoming if Public OR --strict)
# 4) Gatekeeper on
# 5) SIP status
# 6) Remote services off (SSH/Apple Events); aggressive sharing hardening if Public OR --strict
#    Safari: stop auto-opening “safe” downloads (applies to console user), restart if open, verify
#
# Compatible with default macOS bash (3.2).

set -euo pipefail

APPLY_UPDATES=0
PROFILE=""       # "public" or "home"
STRICT_HOME=0    # if 1, enable Block-All + aggressive sharing hardening even on Home
LOGFILE="$HOME/macos_hardening_$(date +%Y%m%d_%H%M%S).log"

usage() {
  cat <<USAGE
Usage: sudo $0 [--apply-updates] [--profile public|home] [--strict]

Options:
  --apply-updates         Install all available software updates immediately (may reboot).
  --profile public|home   Non-interactive; choose the network profile.
  --strict                Apply Public-style inbound blocking and sharing lockdown even on Home.
  -h | --help             Show this help.

If --profile is not provided, you'll be asked to pick Public or Home.
A log will be saved to: $LOGFILE
USAGE
}

# ----- Robust arg parsing (bash 3.2 compatible) -----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply-updates) APPLY_UPDATES=1; shift ;;
    --profile)       PROFILE="${2:-}"; shift 2 ;;
    --profile=*)     PROFILE="${1#*=}"; shift ;;
    --strict)        STRICT_HOME=1; shift ;;
    public|home)     PROFILE="$1"; shift ;;  # shorthand
    -h|--help)       usage; exit 0 ;;
    *)               shift ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
section() { echo; echo "---- $1 ----"; }
console_user() { stat -f%Su /dev/console; }

# If profile not set, prompt (lowercase via tr)
if [[ -z "${PROFILE:-}" ]]; then
  SSID="unknown"
  AIRPORT="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
  if [[ -x "$AIRPORT" ]]; then
    SSID="$("$AIRPORT" -I 2>/dev/null | awk -F': ' '/ SSID/ {print $2; exit}')" || SSID="unknown"
    [[ -z "$SSID" ]] && SSID="unknown"
  fi
  echo
  echo "Detected Wi-Fi SSID: $SSID"
  read -r -p "Are you on Public Wi-Fi or Home Wi-Fi? [public/home] (default: home): " PROFILE
  PROFILE="$(printf '%s' "${PROFILE:-}" | tr '[:upper:]' '[:lower:]')"
  [[ -z "$PROFILE" ]] && PROFILE="home"
else
  PROFILE="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')"
fi

if [[ "$PROFILE" != "public" && "$PROFILE" != "home" ]]; then
  echo "[-] Invalid profile: $PROFILE (use 'public' or 'home')" >&2
  exit 1
fi

# Require sudo/root
if [[ $EUID -ne 0 ]]; then
  echo "[!] Please run with sudo."
  exit 1
fi

# Logging
exec > >(tee -a "$LOGFILE") 2>&1
echo "== mac_harden.sh started: $(date) =="
echo "[i] Selected profile: $PROFILE; strict=$STRICT_HOME"

# 0) System info
section "System info"
sw_vers || true
uname -a || true

# 1) Updates (initial check; install only if --apply-updates passed)
section "1) Checking for software updates"
UPDATES_LIST_OUTPUT=""
if have softwareupdate; then
  UPDATES_LIST_OUTPUT="$(softwareupdate -l 2>&1 || true)"
  printf "%s\n" "$UPDATES_LIST_OUTPUT"
  if [[ $APPLY_UPDATES -eq 1 ]]; then
    echo "[*] Applying all available updates (may require restart)..."
    softwareupdate -ia --verbose || true
  else
    echo "[i] Skipping installation now. You'll be prompted at the end if updates are available."
  fi
else
  echo "[!] 'softwareupdate' not found."
fi

# 2) FileVault
section "2) FileVault status"
if have fdesetup; then
  FV_STATUS="$(fdesetup status || true)"
  echo "$FV_STATUS"
  if echo "$FV_STATUS" | grep -qi "FileVault is Off"; then
    echo "[!] FileVault is OFF. Opening Settings → Privacy & Security → FileVault..."
    open "x-apple.systempreferences:com.apple.preference.security?FileVault" >/dev/null 2>&1 || true
  fi
else
  echo "[!] 'fdesetup' not found."
fi

# 3) Firewall (Application Firewall) — macOS 15-safe flags
section "3) Firewall"
FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
if [[ -x "$FW" ]]; then
  "$FW" --setglobalstate on || true
  "$FW" --setstealthmode on || true
  "$FW" --setallowsigned on || true
  "$FW" --setallowsignedapp on || true

  if [[ "$PROFILE" == "public" || $STRICT_HOME -eq 1 ]]; then
    echo "[*] Enabling Block All Incoming (profile=$PROFILE, strict=$STRICT_HOME)."
    "$FW" --setblockall on || true
  else
    "$FW" --setblockall off || true
  fi

  echo "Firewall state: $("$FW" --getglobalstate)"
  echo "Stealth mode:  $("$FW" --getstealthmode)"
  echo "Block All:     $("$FW" --getblockall)"
else
  echo "[!] socketfilterfw not found."
fi

# 4) Gatekeeper
section "4) Gatekeeper (spctl)"
if have spctl; then
  GK_STATUS="$(spctl --status || true)"
  echo "$GK_STATUS"
  if echo "$GK_STATUS" | grep -qi "disabled"; then
    echo "[*] Enabling Gatekeeper assessments..."
    spctl --master-enable || true
    spctl --status || true
  fi
else
  echo "[!] 'spctl' not found."
fi

# 5) SIP
section "5) System Integrity Protection (SIP)"
if have csrutil; then
  csrutil status || true
  echo "[i] SIP can only be changed from Recovery. Leave it enabled."
else
  echo "[!] 'csrutil' not found."
fi

# 6) Remote services + profile-specific hardening
section "6) Remote services and sharing"
if have systemsetup; then
  RL="$(systemsetup -getremotelogin 2>/dev/null || true)"
  echo "Remote Login (SSH): $RL"
  if echo "$RL" | grep -qi "On"; then
    echo "[*] Disabling Remote Login..."
    systemsetup -setremotelogin off || true
  fi

  RAE="$(systemsetup -getremoteappleevents 2>/dev/null || true)"
  echo "Remote Apple Events: $RAE"
  if echo "$RAE" | grep -qi "On"; then
    echo "[*] Disabling Remote Apple Events..."
    systemsetup -setremoteappleevents off || true
  fi

  # Disable Wake for network access when public or strict
  if [[ "$PROFILE" == "public" || $STRICT_HOME -eq 1 ]]; then
    echo "[*] Disabling Wake for network access."
    systemsetup -setwakeonnetworkaccess off || true
  fi
fi

# Aggressive sharing hardening when public OR strict (Screen Sharing & ARD)
if [[ "$PROFILE" == "public" || $STRICT_HOME -eq 1 ]]; then
  echo "[*] Aggressive sharing hardening (profile=$PROFILE, strict=$STRICT_HOME)."
  # Screen Sharing
  if launchctl print system/com.apple.screensharing >/dev/null 2>&1; then
    echo "[*] Disabling Screen Sharing..."
    launchctl bootout system /System/Library/LaunchDaemons/com.apple.screensharing.plist >/dev/null 2>&1 || true
    launchctl disable system/com.apple.screensharing || true
  fi
  # Remote Management (Apple Remote Desktop)
  ARD_KS="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
  if [[ -x "$ARD_KS" ]]; then
    echo "[*] Disabling Remote Management (ARD)..."
    "$ARD_KS" -deactivate -stop >/dev/null 2>&1 || true
  fi
else
  echo "[i] Home profile (non-strict): leaving Screen Sharing/ARD as-is."
fi

# Safari: stop auto-open of "safe" downloads — apply to console user, restart if open, verify
section "Safari download safety"
CU="$(console_user)"
if id "$CU" >/dev/null 2>&1; then
  UID_CU="$(id -u "$CU")"

  # Write pref inside user's GUI session (more reliable)
  if have launchctl; then
    launchctl asuser "$UID_CU" defaults write com.apple.Safari AutoOpenSafeDownloads -bool false || true
  else
    sudo -u "$CU" defaults write com.apple.Safari AutoOpenSafeDownloads -bool false || true
  fi

  # Verify (expect 0)
  SAFARI_VAL="unset"
  if have launchctl; then
    SAFARI_VAL="$(launchctl asuser "$UID_CU" defaults read com.apple.Safari AutoOpenSafeDownloads 2>/dev/null || echo 'unset')"
  else
    SAFARI_VAL="$(sudo -u "$CU" defaults read com.apple.Safari AutoOpenSafeDownloads 2>/dev/null || echo 'unset')"
  fi
  echo "[i] AutoOpenSafeDownloads = $SAFARI_VAL (expect 0)"

  # Restart Safari if running for the console user
  if have pgrep && pgrep -x -u "$UID_CU" Safari >/dev/null 2>&1; then
    echo "[*] Safari is running for $CU — restarting to apply setting..."
    if have launchctl && have osascript; then
      launchctl asuser "$UID_CU" osascript -e 'tell application "Safari" to quit' >/dev/null 2>&1 || true
      COUNT=0; while pgrep -x -u "$UID_CU" Safari >/dev/null 2>&1 && [[ $COUNT -lt 10 ]]; do sleep 1; COUNT=$((COUNT+1)); done
      launchctl asuser "$UID_CU" open -a Safari >/dev/null 2>&1 || true
    else
      sudo -u "$CU" osascript -e 'tell application "Safari" to quit' >/dev/null 2>&1 || true
      sleep 2
      sudo -u "$CU" open -a Safari >/dev/null 2>&1 || true
    fi
    echo "[✓] Safari restarted."
  else
    echo "[i] Safari not running for $CU; no restart needed."
  fi
else
  echo "[!] Could not determine console user."
fi

# Optional: auto-updates best practices
section "Auto-updates best practices"
if have softwareupdate; then
  softwareupdate --schedule on || true
fi
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -int 1 || true
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -int 1 || true
defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true || true

# Quick listening ports snapshot
section "Listening ports snapshot"
if have lsof; then
  lsof -Pn -i -sTCP:LISTEN || true
else
  echo "[i] 'lsof' not found. Install via: xcode-select --install"
fi

# ---- Final update prompt (only if not already applying updates) ----
if have softwareupdate && [[ $APPLY_UPDATES -eq 0 ]]; then
  echo
  section "Final update prompt"
  if [[ -z "$UPDATES_LIST_OUTPUT" ]]; then
    UPDATES_LIST_OUTPUT="$(softwareupdate -l 2>&1 || true)"
  fi
  if echo "$UPDATES_LIST_OUTPUT" | grep -qi "No new software available"; then
    echo "[i] No updates available. Nothing to install."
  else
    echo "[i] Updates appear to be available."
    read -r -p "Do you want to install them now? (may take time and require restart) [y/N]: " RESP
    RESP="$(printf '%s' "${RESP:-}" | tr '[:upper:]' '[:lower:]')"
    if [[ "$RESP" == "y" || "$RESP" == "yes" ]]; then
      echo "[*] Installing updates now..."
      softwareupdate -ia --verbose || true
      echo "[→] If a restart is required, please reboot when convenient."
    else
      echo "[i] Skipping updates for now. You can run again with --apply-updates."
    fi
  fi
fi

echo
echo "== Completed at: $(date) =="
echo "[✓] Log saved to: $LOGFILE"
if [[ "$PROFILE" == "public" || $STRICT_HOME -eq 1 ]]; then
  echo "[→] Inbound connections are blocked. AirDrop/AirPlay may be limited. Re-run without --strict (or with --profile home) to relax."
fi

