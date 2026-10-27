#!/bin/zsh
# Runs the unit tests with the Command Line Tools toolchain (see build.sh for why the SDK is pinned).
set -euo pipefail
cd "$(dirname "$0")"
if [[ -z "${SDKROOT:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
  SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
  [[ -n "$SDK" ]] && export SDKROOT="$SDK"
fi
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [[ -d $PLUGINS ]]; then
  swift test -Xswiftc -plugin-path -Xswiftc $PLUGINS "$@"
else
  swift test "$@"
fi
