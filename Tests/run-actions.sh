#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Checks
xcrun swiftc -warnings-as-errors -module-cache-path build/ModuleCache.noindex \
  NotchIsland/Core/IslandCoordinator.swift \
  NotchIsland/Core/IslandModel.swift \
  NotchIsland/Core/LiveActivityManager.swift \
  NotchIsland/Core/NotchDetector.swift \
  NotchIsland/Settings/IslandSettings.swift \
  NotchIsland/Features/Actions/QuickActionsModel.swift \
  NotchIsland/Features/Launcher/AppLauncherModel.swift \
  NotchIsland/Features/Downloads/DownloadModel.swift \
  Tests/ActionDownloadChecks.swift -o build/Checks/ActionDownloadChecks
build/Checks/ActionDownloadChecks
