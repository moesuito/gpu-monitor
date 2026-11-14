# AGENTS.md

This file gives AI coding agents the context, architecture, build commands, and strict invariants needed to work safely in the **gpu-monitor** (`GPU Monitor`) repository.

## Project Overview

**GPU Monitor** is a lightweight, local, read-only macOS (`x86_64`) menu bar application written in Swift and SwiftUI. It monitors NVIDIA GPUs running on the **NullMoth** driver (`com.nullmoth.NVAccel` / `NVAccel`) by reading the `PerformanceStatistics` dictionary published by `IOAccelerator` devices in `IORegistry`.

- **Primary UI**: Menu bar extra (`MenuBarExtra` with `.menuBarExtraStyle(.window)`) displaying a `cpu` SF Symbol and `"GPU <N>%"` (or `"GPU —"` when unavailable). No Dock icon (`LSUIElement = true`, `.accessory` activation policy) and no automatic main window.
- **Target platform**: Intel macOS (`x86_64`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, tested on macOS 26.7.3 with Xcode 26.6).
- **Zero external dependencies**: Uses only native Apple frameworks (`SwiftUI`, `AppKit`, `Foundation`, `IOKit`, `Combine`, `ServiceManagement`, `XCTest`).
- **Repository language**: Everything in the app UI, code, comments, tests, and docs is in **English**.

## Architecture & File Map

- `GPUMonitor/GPUMonitorApp.swift`
  - `@main` `GPUMonitorApp` scene (`MenuBarExtra`) and `AppDelegate` (`NSApp.setActivationPolicy(.accessory)`, starts/stops polling on launch/termination).
  - `MenuBarLabelView` renders the `Label` (`cpu` icon + monospaced-digit `menuBarTitle`).
- `GPUMonitor/Info.plist`
  - Sets `LSUIElement = true` and `CFBundleDisplayName = GPU Monitor`.
- `GPUMonitor/Models/GPUMetrics.swift`
  - `MetricValue` (`available(Double)` / `unavailable`), clamping helper for visual bars/plots only (`clampedPercentageFraction`), and out-of-range detection (`isOutOfPercentageRange`).
  - `PercentageMetricKind`: The 4 distinct `PerformanceStatistics` utilization keys and UI labels (`GPU Utilization` for `GPU Core Utilization %`, `Memory Utilization`, `Video Engine`, `Video Decode`; redundant `Device Utilization %` is intentionally omitted because NullMoth `NVAccel` copies the exact same field).
  - `GPUPerformanceParser`: Strict numeric parser + little-endian PCI ID / NUL-trimmed string decoders.
  - `RawAcceleratorEntry`, `GPUDeviceDescriptor`, `DeviceSelectionPolicy`: Reliable GPU naming from parent `IOPCIDevice` `"model"` (fallback `"Detected GPU"`) and multi-GPU selection without summing or mislabeling.
  - `MetricFormatter`: Raw-preserving percentage, `°C` temperature, and menu bar title formatting (`"Unavailable"` / `"GPU —"`).
- `GPUMonitor/Models/MetricHistory.swift`
  - `MetricHistoryBuffer` (bounded 60-sample rolling history per `PercentageMetricKind`) with `contiguousAvailableSegments(for:)` that splits segments across `.unavailable` readings and resets when switching GPU devices.
- `GPUMonitor/Services/GPUCollecting.swift`
  - `GPUCollecting` protocol and `CompositeGPUCollector` (tries `IOKitGPUCollector` first, falls back to `IORegFallbackCollector`).
- `GPUMonitor/Services/IOKitGPUCollector.swift`
  - Enumerates `IOAccelerator` via `IOServiceGetMatchingServices`, reads targeted properties with `IORegistryEntryCreateCFProperty`, and walks `kIOServicePlane` parents (up to 5 hops) for `IOPCIDevice` (`vendor-id`, `device-id`, `model`).
- `GPUMonitor/Services/IORegFallbackCollector.swift`
  - Runs `/usr/sbin/ioreg -r -c IOAccelerator -d 1 -a` (no shell, timeout-guarded) and parses structured XML plist via `PropertyListSerialization` independent of key order.
- `GPUMonitor/Services/LoginItemService.swift`
  - Opt-in login item wrapper (`LoginItemManaging` / `MainAppLoginItemManager` using `SMAppService.mainApp`), disabled by default unless toggled by the user.
- `GPUMonitor/ViewModels/GPUMonitorViewModel.swift`
  - `@MainActor` `ObservableObject` running a 1-second cooperative `Task` polling loop (`Task.detached(priority: .utility)` for collection). Tracks `currentSnapshot`, `lastSuccessfulReadAt`, `lastErrorMessage`, `history`, `selectedHistoryMode`, `selectedDeviceID`, and `launchAtLoginState`.
- `GPUMonitor/Views/MenuBarPanelView.swift`, `MetricRowView.swift`, & `UsageHistoryChartView.swift`
  - Apple-native, Stats-inspired popover (`384pt` width) supporting Light/Dark mode: circular Temperature (`°C`) & GPU Utilization (`%`) gauges, selectable full-width Usage History chart (`All Percentages` or single metric), 2×2 grid of per-metric chart cards with progress bars, conditional multi-GPU selector / error banner, and a single-row footer combining `"Launch at login"` and `"Quit"` (`⌘Q`).
- `GPUMonitorTests/GPUMonitorTests.swift`
  - Hosted unit tests (`TEST_HOST` is `GPU Monitor.app`).

## Build, Test, and Verification Commands

Run all commands from the repository root (`gpu-monitor/`):

```bash
# Run unit tests (Intel x86_64)
xcodebuild test -project GPUMonitor.xcodeproj -scheme GPUMonitor -destination 'platform=macOS,arch=x86_64'

# Build Release app (Intel x86_64)
xcodebuild build -project GPUMonitor.xcodeproj -scheme GPUMonitor -configuration Release -destination 'platform=macOS,arch=x86_64'

# Verify live IORegistry dictionary for comparison
ioreg -r -c IOAccelerator -d 1
```

If you need a custom derived data directory during automated runs, pass `-derivedDataPath /tmp/gpumon-dd` (or `.build/DerivedData` / `build/`, which are gitignored).

## Critical Invariants & Pitfalls

1. **Swift `CFBoolean` vs `NSNumber(0/1)` Bridging Trap**:
   - **Never** check `raw is Bool` on values decoded from `CFDictionary` / `IORegistry` / `PropertyListSerialization`. In Swift, `__NSCFNumber(0)` and `__NSCFNumber(1)` evaluate `is Bool == true`, which would wrongly turn `0%` and `1%` readings into `Unavailable`.
   - Always check `CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID()` to reject booleans while accepting `NSNumber`/`CFNumber` `0` and `1`.
2. **Never Default Unreadable Values or Chart Gaps to `0%`**:
   - Missing keys, booleans, non-numeric strings/collections, `NaN`, `Infinity`, or failed reads must yield `.unavailable` (`"Unavailable"` in the panel, `"GPU —"` in the menu bar).
   - Unavailable history points and failed polls must break line/area chart segments (leave gaps) rather than dropping to `0%`.
   - On read failure after a previous success, keep `lastSuccessfulReadAt` for display, show the error banner, record an `.unavailable` gap in history, and expose current metrics as `.unavailable`.
3. **Preserve Raw Numeric Values**:
   - Never clamp numeric text when a driver reports `< 0` or `> 100`. Only clamp visual progress bars and chart Y-coordinates (`clampedPercentageFraction` in `[0, 1]`) and show the unexpected-value indicator.
4. **Never Sum Metrics or GPUs**:
   - All 4 percentage metrics are independent and must never be summed or stacked.
   - Multiple `IOAccelerator` devices must never be summed; switching devices resets the rolling `MetricHistoryBuffer`.
   - Only auto-select a GPU as NVIDIA when proven (`vendor-id == 0x10de`, or non-conflicting `10de` / `com.nullmoth.NVAccel` when PCI `vendor-id` is absent). If ambiguous, never label another GPU as NVIDIA and allow user selection.
   - Never invent or guess GPU model names; if `IOPCIDevice` `"model"` is missing or generic (e.g., `"display"`, `"GFX0"`, `"NVAccel"`), display `"Detected GPU"`.
5. **Terminology & Accuracy**:
   - Keep `"Video Engine"` (do **not** rename to `"NVENC"` or `"Encoder"`).
   - Keep `"Video Decode"` without claiming app or codec attribution.
   - Do not overclaim driver accuracy or application/codec attribution in docs or future UI copy.
6. **IOKit Resource & CPU Hygiene**:
   - Every `io_iterator_t` and `io_registry_entry_t` must be paired with `IOObjectRelease` via `defer`.
   - Keep `MetricHistoryBuffer` bounded (default 60 samples) and avoid heavy allocations or continuous animations inside the 1s poll path.
   - Use targeted `IORegistryEntryCreateCFProperty` lookups instead of `IORegistryEntryCreateCFProperties` during polling so large blobs like `IOReportLegend` are not serialized every second.
   - Verify with `/usr/bin/leaks` after changing IOKit code.
7. **Scope & Project Boundaries**:
   - Stay local and read-only: no network calls, no `sudo`, no kext/EFI edits, no telemetry, and no background helper daemons.
   - Login auto-start (`SMAppService.mainApp`) must remain **disabled by default** and may only be changed when the user explicitly toggles `"Launch at login"` in the UI. Never auto-register on launch, and always inject `LoginItemManaging` in unit tests so tests never touch macOS Login Items.
   - `GPUMonitor.xcodeproj/project.pbxproj` is maintained directly (no `xcodegen` dependency). If you add, remove, or rename Swift files, update `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, and `PBXSourcesBuildPhase` in `project.pbxproj` and run `xcodebuild test` to confirm.
