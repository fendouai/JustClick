#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
# Never build/sign/install the user's authorized application for this check.
swift run JustClickPasteChecks
swift run JustClickChecks
