#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Checks
xcrun swiftc -warnings-as-errors -module-cache-path build/ModuleCache.noindex \
 NotchIsland/Settings/IslandSettings.swift NotchIsland/Core/IslandModel.swift \
 NotchIsland/Core/IslandCoordinator.swift NotchIsland/Core/NotchDetector.swift \
 NotchIsland/Core/LiveActivityManager.swift Tests/SettingsChecks.swift -o build/Checks/SettingsChecks
build/Checks/SettingsChecks
