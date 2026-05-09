#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p .build/test-products
swiftc \
  Sources/MacGHActionsNotifier/Models/AppStatus.swift \
  Sources/MacGHActionsNotifier/Models/AppConfiguration.swift \
  Sources/MacGHActionsNotifier/Models/WorkflowRun.swift \
  Sources/MacGHActionsNotifier/Services/AppError.swift \
  Sources/MacGHActionsNotifier/Services/StatusAggregator.swift \
  Sources/MacGHActionsNotifier/Services/NotificationDecider.swift \
  Sources/MacGHActionsNotifier/Support/SoftwareUpdateState.swift \
  Sources/MacGHActionsNotifier/Support/TimestampFormatter.swift \
  Tests/LogicTests.swift \
  -o .build/test-products/logic-tests

.build/test-products/logic-tests
