#!/bin/zsh
# Build DesktopRoach
set -e
cd "$(dirname "$0")"
swiftc -module-cache-path "${TMPDIR:-/tmp}/desktoproach-module-cache" -O -swift-version 5 -o DesktopRoach main.swift FlyModel.swift LegDynamics.swift Locomotor.swift LocomotorTests.swift BeetleModel.swift RoachModel.swift Sim.swift BrainView.swift \
    Environment.swift -framework Cocoa -framework SceneKit
echo "Built ./DesktopRoach"
