#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Checks
xcrun swiftc -warnings-as-errors -module-cache-path build/ModuleCache.noindex \
  NotchIsland/Features/Media/MediaModel.swift Tests/MediaChecks.swift -o build/Checks/MediaChecks
build/Checks/MediaChecks
