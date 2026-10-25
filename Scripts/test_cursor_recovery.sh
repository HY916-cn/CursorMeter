#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cursor-recovery
swiftc -swift-version 5 -default-isolation MainActor -parse-as-library \
  CodexMeter/Core/*.swift Tests/CursorRecoveryIntegration/main.swift \
  -lsqlite3 -o .build/cursor-recovery/recovery-tests
.build/cursor-recovery/recovery-tests
