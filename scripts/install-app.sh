#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
source_app="$PWD/dist/JustClick.app"
destination="$HOME/Applications/JustClick.app"
test -d "$source_app"
codesign --verify --deep --strict "$source_app"
if [[ -d "$destination" ]] && diff -qr "$source_app" "$destination" >/dev/null; then
  print "Already installed unchanged: $destination"
  exit 0
fi
mkdir -p "$HOME/Applications"
staging="$(mktemp -d "$HOME/Applications/.justclick-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$source_app" "$staging/JustClick.app"
registry='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
unregister_app() {
  local diagnostic
  if diagnostic="$("$registry" -u "$1" 2>&1)"; then return 0; fi
  # -10814 means this generated copy is not registered, which is already the desired state.
  if [[ "$diagnostic" == *'-10814'* ]]; then return 0; fi
  print -u2 -- "$diagnostic"
  return 1
}
if [[ -e "$destination" ]]; then
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
  [[ "$bundle_id" == "local.justclick.app" ]] || { print -u2 '现有目标不是 JustClick，未替换。'; exit 1; }
  backup_root="$HOME/Library/Application Support/JustClick/app-backups"
  mkdir -p "$backup_root"
  backup_archive="$backup_root/JustClick-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM.app.zip"
  ditto -c -k --sequesterRsrc --keepParent "$destination" "$backup_archive"
  unzip -t "$backup_archive" >/dev/null
  # Runnable .app backups collide in LaunchServices and can receive the new app's permissions.
  unregister_app "$destination"
  mv "$destination" "$staging/previous.app"
fi
mv "$staging/JustClick.app" "$destination"
unregister_app "$source_app"
"$registry" -f "$destination"
print "Installed: $destination"
print '请退出旧版本后打开此应用，并在系统设置中为这个固定路径授权辅助功能。'
