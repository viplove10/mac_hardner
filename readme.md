# mac\_harden.sh — macOS Host Hardening with Public/Home/Strict Profiles

Harden a Mac quickly and safely from the Terminal. This script enables core protections (Firewall, Gatekeeper, SIP checks, FileVault status), disables risky remote services, sets a safer Safari download behavior, and offers *environment-aware* profiles:

- **Home** (default): Sensible security without breaking AirDrop/Handoff/AirPlay.
- **Public**: Extra protection for coffee shops/airports — blocks all inbound traffic and locks down sharing.
- **Strict** (flag): Apply Public-style inbound blocking and sharing lockdown even while at Home.

> ✅ Compatible with macOS **12–15** (Monterey → Sequoia), Intel & Apple Silicon.

---

## Table of Contents

- [Features](#features)
- [What It Changes](#what-it-changes)
- [What It ](#what-it-does-not-change)[**Does Not**](#what-it-does-not-change)[ Change](#what-it-does-not-change)
- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
- [Profiles](#profiles)
- [Examples](#examples)
- [Sample Output](#sample-output)
- [Troubleshooting](#troubleshooting)
- [Rollback / Undo](#rollback--undo)
- [Why These Choices](#why-these-choices)
- [Security & Ethics](#security--ethics)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Update awareness**: Checks for macOS/app updates; optional install now or prompt at end.
- **FileVault**: Verifies full‑disk encryption; opens the Settings pane if off (user approval required).
- **Firewall**: Enables Application Firewall + stealth mode; **Block All Incoming** in Public/Strict.
- **Gatekeeper**: Ensures app assessment is on.
- **SIP**: Reports System Integrity Protection status.
- **Remote services**: Turns **off** Remote Login (SSH) & Remote Apple Events; disables Wake-on-Network in Public/Strict.
- **Sharing lockdown**: Disables Screen Sharing & Apple Remote Desktop in Public/Strict (if active).
- **Safari safety**: Sets `AutoOpenSafeDownloads=false` **in the logged‑in user’s GUI session** and restarts Safari if running.
- **Decision-aware**: Prompts for **Home/Public** if not specified; supports `--strict` for quiet home networks.
- **Bash 3.2 friendly**: Works with macOS’s default legacy bash.
- **Logging**: Writes a time‑stamped hardening log to `~/macos_hardening_YYYYMMDD_HHMMSS.log`.

---

## What It Changes

- **Firewall**: `socketfilterfw --setglobalstate on`, `--setstealthmode on`, `--setblockall on` (Public/Strict only), allow signed Apple.
- **Gatekeeper**: `spctl --master-enable` if needed.
- **SIP**: Read‑only status via `csrutil status`.
- **FileVault**: Status via `fdesetup status`; opens Settings deep link if off.
- **Remote access**: `systemsetup -setremotelogin off`, `-setremoteappleevents off`.
- **Wake on network**: `systemsetup -setwakeonnetworkaccess off` (Public/Strict).
- **Sharing**: `screensharingd`/ARD disabled via `launchctl` & ARD kickstart (Public/Strict).
- **Safari**: Writes preference inside the user session via `launchctl asuser … defaults write` and restarts Safari if running.

### What It **Does Not** Change

- It **doesn’t** enable FileVault automatically (Apple requires user approval).
- It **doesn’t** kill core discovery services (mDNSResponder, rapportd, ControlCenter). Inbound blocking in Public/Strict protects them.
- It **doesn’t** manage MDM, kernel/system extensions, or third‑party tools.

---

## Requirements

- macOS 12–15, admin account with `sudo`.
- Terminal access.

---

## Install

```bash
mkdir -p ~/scripts && cd ~/scripts
# Save the script here as mac_harden.sh
chmod 755 mac_harden.sh
```

---

## Usage

```bash
sudo ./mac_harden.sh [--apply-updates] [--profile public|home] [--strict] [--help]
```

**Flags**

- `--profile public|home` — Non‑interactive profile selection. If omitted, the script will prompt.
- `--strict` — Apply Public‑style inbound blocking & sharing lockdown even on Home.
- `--apply-updates` — Install available updates immediately (may require restart). Otherwise you’ll be prompted at the end.
- `--help` — Show usage.

---

## Profiles

- **Home (default)**: Firewall + stealth **on**, inbound **allowed**, SSH/Apple Events **off**, sharing left as‑is.
- **Public**: Everything in Home **plus** Block‑All‑Incoming, Wake‑on‑Network **off**, and screen sharing/ARD disabled if active.
- **Strict (flag)**: Same as Public **even when profile=home**.

> Tip: Use Public/Strict when on untrusted Wi‑Fi; switch back to Home later for AirDrop/AirPlay convenience.

---

## Examples

```bash
# Typical home harden
sudo ./mac_harden.sh --profile home

# Coffee shop lockdown
sudo ./mac_harden.sh --profile public

# Quiet/locked‑down even at home
sudo ./mac_harden.sh --profile home --strict

# Run and install updates at the end only if they exist
sudo ./mac_harden.sh --profile public

# Force immediate update install (may reboot)
sudo ./mac_harden.sh --apply-updates --profile public
```

---

## Sample Output

```text
== mac_harden.sh started: Sun Aug 17 19:19:34 IST 2025 ==
[i] Selected profile: home

---- 1) Checking for software updates ----
No new software available.
[i] Skipping installation now. You'll be prompted at the end if updates are available.

---- 3) Firewall ----
Firewall state: Firewall is enabled. (State = 1)
Stealth mode:  Firewall stealth mode is on
Block All:     Firewall has block all state set to disabled.

---- 6) Remote services and sharing ----
Remote Login (SSH): Remote Login: Off
Remote Apple Events: Remote Apple Events: Off
[i] Home profile (non-strict): leaving Screen Sharing/ARD as-is.

---- Safari download safety ----
[i] AutoOpenSafeDownloads = 0 (expect 0)
[*] Safari is running for creed — restarting to apply setting...
[✓] Safari restarted.

---- Final update prompt ----
[i] No updates available. Nothing to install.
```

---

## Troubleshooting

### `bad substitution` error on `${PROFILE,,}`

macOS’s default bash (3.2) doesn’t support `${var,,}`. The script is already patched to use `tr` instead. Ensure you have the latest version of this script.

### `Could not write domain … com.apple.Safari`

Sometimes `defaults` fails when run as root outside the GUI session. This script writes the preference **inside the user’s session** using `launchctl asuser`. If you still see it:

```bash
CU=$(stat -f%Su /dev/console); UID_CU=$(id -u "$CU")
sudo launchctl asuser "$UID_CU" defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
```

### `command not found` for the script

Make sure you’re in the directory and the file is executable:

```bash
cd ~/scripts
chmod 755 mac_harden.sh
sudo ./mac_harden.sh --profile home
```

### AirDrop/AirPlay stopped working

You’re likely in **Public** or `--strict` mode (Block‑All‑Incoming). To relax:

```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
```

Or rerun the script with `--profile home` (no `--strict`).

---

## Rollback / Undo

- **Block All Incoming (off):**
  ```bash
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
  ```
- **Re‑enable Remote Login/Apple Events (not recommended):**
  ```bash
  sudo systemsetup -setremotelogin on
  sudo systemsetup -setremoteappleevents on
  ```
- **Re‑enable Screen Sharing / ARD:** Open System Settings → General → **Sharing**, toggle as needed. (If you previously disabled via `launchctl`, a reboot or manual re‑enable in Sharing should restore.)
- **Safari setting:**
  ```bash
  defaults write com.apple.Safari AutoOpenSafeDownloads -bool true
  ```

---

## Why These Choices

- **Block All Incoming** on untrusted networks is the safest, reversible way to neutralize listening services without hacking on Apple system daemons.
- **Stealth mode** helps resist unsolicited scans.
- **Disabling SSH/Remote Apple Events** removes common remote control paths.
- **FileVault** protects data at rest (especially for laptops).
- **Safari download safety** prevents auto‑opening "safe" files — a long‑standing phishing/malware foothold.

---

## Security & Ethics

- This script is for **defensive** hardening of Macs **you own or administer**.
- It avoids destructive changes and prefers reversible settings.
- Always verify your organization’s policies before use.

---

## Contributing

Issues and PRs welcome! Ideas:

- Detect current network trust (e.g., known SSIDs) to auto‑select profile
- Optional Sysmon for macOS config
- Export a JSON “state diff” before/after

---

## License

MIT — see `LICENSE` for details.

