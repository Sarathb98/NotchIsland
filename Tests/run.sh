#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Checks
xcrun swiftc -module-cache-path build/ModuleCache.noindex \
  NotchIsland/Core/NotchDetector.swift \
  NotchIsland/Core/LiveActivityManager.swift \
  NotchIsland/Core/IslandCoordinator.swift \
  NotchIsland/Core/IslandModel.swift \
  NotchIsland/Settings/IslandSettings.swift \
  NotchIsland/Features/Timer/TimerModel.swift \
  NotchIsland/Features/Calendar/CalendarModel.swift \
  NotchIsland/Features/System/SystemMonitor.swift \
  Tests/CoreChecks.swift -o build/Checks/CoreChecks
build/Checks/CoreChecks
