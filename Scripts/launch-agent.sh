#!/bin/bash
# Explicit opt-in only. No credentials or authentication configuration are changed.
set -euo pipefail
label=com.daltan.codexusage.refresh
plist="$HOME/Library/LaunchAgents/$label.plist"
case "${1:-status}" in
  install)
    executable="$HOME/Applications/Codex Usage.app/Contents/MacOS/Codex Usage"
    [[ -x "$executable" ]] || { echo 'Install the Release app first.' >&2; exit 1; }
    [[ ! -e "$plist" ]] || { echo 'Agent already exists; use status or uninstall first.' >&2; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents"
    /usr/bin/python3 - "$plist" "$executable" "$label" <<'PY'
import os, plistlib, sys
path, executable, label = sys.argv[1:]
with open(path, 'wb') as stream:
    plistlib.dump({'Label': label, 'ProgramArguments': [executable, '--refresh-once'],
                  'StartInterval': 3600, 'RunAtLoad': True, 'ProcessType': 'Background',
                  'StandardOutPath': '/dev/null', 'StandardErrorPath': '/dev/null'}, stream)
os.chmod(path, 0o600)
PY
    launchctl bootstrap "gui/$(id -u)" "$plist"
    launchctl print "gui/$(id -u)/$label"
    ;;
  uninstall)
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    if [[ -f "$plist" ]]; then
      mkdir -p "$HOME/.Trash"
      mv "$plist" "$HOME/.Trash/$label.$(date +%s).plist"
    fi
    echo 'Agent removed; application and cached usage retained.'
    ;;
  status) launchctl print "gui/$(id -u)/$label" ;;
  *) echo 'Usage: launch-agent.sh install|uninstall|status' >&2; exit 2 ;;
esac
