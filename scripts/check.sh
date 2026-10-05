#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift run JustClickChecks
./scripts/build-app.sh
codesign --verify --deep --strict dist/JustClick.app
plutil -lint dist/JustClick.app/Contents/Info.plist
test_dir="$(mktemp -d /tmp/justclick-smoke.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
JUSTCLICK_DATA_DIR="$test_dir" dist/JustClick.app/Contents/MacOS/JustClick --smoke-test > "$test_dir/result.json"
python3 - "$test_dir/result.json" <<'PY'
import json, sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
assert result['windowVisible'], result
assert result['hotKeyRegistered'] or result['hotKeyConflictReported'], result
assert 320 <= result['sidebarWidth'] <= 520, result
assert result['menuItems'] >= 12, result
assert result['promptCount'] == result['builtinCount'] == 80, result
assert result['clipboardRoundTrip'], result
assert result['modelRoundTrip'], result
assert result['editingMenuReady'], result
assert Path(result['dataFile']).is_file(), result
print(json.dumps(result, ensure_ascii=False, indent=2))
print('PASS native application launch checks')
if not result['hotKeyRegistered']:
    print('NOTE hotkey occupied by an existing app; conflict handling passed, registration was not verified in this run')
PY
