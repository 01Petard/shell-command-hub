#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/hub-interaction-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
# Compile the real app classes without starting the application event loop.
awk '/^if bundle.object\(forInfoDictionaryKey: "HubInterface"\)/ {exit} {print}' "$ROOT/app/HubApp.swift" > "$work/main.swift"
cat "$ROOT/tests/test_app_interactions.swift" >> "$work/main.swift"
/usr/bin/xcrun swiftc -swift-version 5 -framework AppKit "$work/main.swift" -o "$work/test-app-interactions"
"$work/test-app-interactions"
