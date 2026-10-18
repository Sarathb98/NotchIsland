#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Checks
xcrun swiftc -warnings-as-errors -module-cache-path build/ModuleCache.noindex \
 NotchIsland/Features/DropZone/DropZoneModel.swift NotchIsland/Features/Clipboard/ClipboardModel.swift \
 Tests/ShelfClipboardChecks.swift -o build/Checks/ShelfClipboardChecks
build/Checks/ShelfClipboardChecks
