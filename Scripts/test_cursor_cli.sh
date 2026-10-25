#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cursor-integration
swiftc -swift-version 5 -default-isolation MainActor -o .build/cursor-integration/cursor-tests \
  CodexMeter/Core/QuotaModels.swift \
  CodexMeter/Core/HistoryModels.swift \
  CodexMeter/Core/PopoverContentConfiguration.swift \
  CodexMeter/Core/CodexProcessSupport.swift \
  CodexMeter/Core/CursorUsageParser.swift \
  CodexMeter/Core/CursorTerminalScreen.swift \
  CodexMeter/Core/CursorCLIClient.swift \
  CodexMeter/Core/CursorRefreshSchedule.swift \
  Tests/CursorIntegration/main.swift
.build/cursor-integration/cursor-tests "$@"
