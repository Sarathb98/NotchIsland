#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Checks
xcrun swiftc -module-cache-path build/ModuleCache.noindex NotchIsland/Features/Notes/NotesModel.swift Tests/NotesChecks.swift -o build/Checks/NotesChecks
build/Checks/NotesChecks
