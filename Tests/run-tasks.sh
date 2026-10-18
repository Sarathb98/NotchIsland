#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Checks
xcrun swiftc -warnings-as-errors -module-cache-path build/ModuleCache.noindex \
    NotchIsland/Features/Tasks/TaskListModel.swift Tests/TaskChecks.swift \
    -o build/Checks/TaskChecks
build/Checks/TaskChecks
