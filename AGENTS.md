# AGENTS.md

This file gives AI coding agents the context, architecture, commands, and strict invariants needed to work safely in the **gpu-monitor** (`GPU Monitor`) repository.

## Project Overview

**GPU Monitor** is a lightweight, local, read-only macOS (`x86_64`) menu bar application written in Swift and SwiftUI. It monitors NVIDIA GPUs running on the **NullMoth** driver (`com.nullmoth.NVAccel` / `NVAccel`) by reading the `PerformanceStatistics` dictionary published by `IOAccelerator` devices in `IORegistry`.

- **Primary UI**: Menu bar extra (`MenuBarExtra` with `.menuBarExtraStyle(.window)`) displaying a `cpu` SF Symbol and `"GPU <N>%"` (or `"GPU —"` when unavailable). No Dock icon (`LSUIElement = true`, `.accessory` activation policy) and no automatic main window.
- **Target platform**: Intel macOS (`x86_64`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, tested on macOS 26.7.3 with Xcode 26.6).
- **Zero external dependencies**: Uses only native Apple frameworks (`SwiftUI`, `AppKit`, `Foundation`, `IOKit`, `Combine`, `XCTest`).

## Architecture & File Map

- `GPUMonitor/GPUMonitorApp.swift`
  - `@main` `GPUMonitorApp` scene (`MenuBarExtra`) and `AppDelegate` (`NSApp.setActivationPolicy(.accessory)`, starts/stops polling on launch/termination).
  - `MenuBarLabelView` renders the `Label` (`cpu` icon + monospaced-digit `menuBarTitle`).
- `GPUMonitor/Info.plist`
  - Sets `LSUIElement = true` and `CFBundleDisplayName = GPU Monitor`.
- `GPUMonitor/Models/GPUMetrics.swift`
  - `MetricValue` (`available(Double)` / `unavailable`), clamping helper for visual bars only (`clampedPercentageFraction`), and out-of-range detection (`isOutOfPercentageRange`).
  - `PercentageMetricKind`: The 5 `PerformanceStatistics` utilization keys and exact Portuguese UI labels (`Núcleo da GPU`, `Uso do dispositivo`, `Utilização da memória`, `Motor de vídeo`, `Decodificação de vídeo`).
  - `GPUPerformanceParser`: Strict numeric parser + little-endian PCI ID / NUL-trimmed string decoders.
  - `RawAcceleratorEntry`, `GPUDeviceDescriptor`, `DeviceSelectionPolicy`: Reliable GPU naming from parent `IOPCIDevice` `"model"` (fallback `"GPU detectada"`) and multi-GPU selection without summing or mislabeling.
  - `MetricFormatter`: Raw-preserving percentage, `°C` temperature, and menu bar title formatting.
- `GPUMonitor/Services/GPUCollecting.swift`
  - `GPUCollecting` protocol and `CompositeGPUCollector` (tries `IOKitGPUCollector` first, falls back to `IORegFallbackCollector`).
- `GPUMonitor/Services/IOKitGPUCollector.swift`
  - Enumerates `IOAccelerator` via `IOServiceGetMatchingServices`, reads targeted properties with `IORegistryEntryCreateCFProperty`, and walks `kIOServicePlane` parents (up to 5 hops) for `IOPCIDevice` (`vendor-id`, `device-id`, `model`).
- `GPUMonitor/Services/IORegFallbackCollector.swift`
  - Runs `/usr/sbin/ioreg -r -c IOAccelerator -d 1 -a` (no shell, timeout-guarded) and parses structured XML plist via `PropertyListSerialization` independent of key order.
- `GPUMonitor/ViewModels/GPUMonitorViewModel.swift`
  - `@MainActor` `ObservableObject` running a 1-second cooperative `Task` polling loop (`Task.detached(priority: .utility)` for collection). Tracks `currentSnapshot`, `lastSuccessfulReadAt`, `lastErrorMessage`, and `selectedDeviceID`.
- `GPUMonitor/Views/MenuBarPanelView.swift` & `GPUMonitor/Views/MetricRowView.swift`
  - Compact native popover (`348pt` width) supporting Light/Dark mode, showing GPU name, optional multi-GPU selector, error banner, 5 percentage bars, separate temperature row in `°C`, limitation notice, last successful read timestamp, and `"Sair"` (`⌘Q`) button.
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

If you need a custom derived data directory during automated runs, pass `-derivedDataPath /tmp/gpumon-dd` (or `.build/DerivedData`, which is gitignored).

## Critical Invariants & Pitfalls

1. **Swift `CFBoolean` vs `NSNumber(0/1)` Bridging Trap**:
   - **Never** check `raw is Bool` on values decoded from `CFDictionary` / `IORegistry` / `PropertyListSerialization`. In Swift, `__NSCFNumber(0)` and `__NSCFNumber(1)` evaluate `is Bool == true`, which would wrongly turn `0%` and `1%` readings into `Indisponível`.
   - Always check `CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID()` to reject booleans while accepting `NSNumber`/`CFNumber` `0` and `1`.
2. **Never Default Unreadable Values to `0%`**:
   - Missing keys, booleans, non-numeric strings/collections, `NaN`, `Infinity`, or failed reads must yield `.unavailable` (`"Indisponível"` in the panel, `"GPU —"` in the menu bar).
   - On read failure after a previous success, keep `lastSuccessfulReadAt` for display, show the error banner, and expose current metrics as `.unavailable` so stale values are not shown as live.
3. **Preserve Raw Numeric Values**:
   - Never clamp numeric text when a driver reports `< 0` or `> 100`. Only clamp the visual progress bar (`clampedPercentageFraction` in `[0, 1]`) and show the unexpected-value indicator.
4. **Never Sum Metrics or GPUs**:
   - All 5 percentage metrics are independent. Multiple `IOAccelerator` devices must never be summed.
   - Only auto-select a GPU as NVIDIA when proven (`vendor-id == 0x10de`, or non-conflicting `10de` / `com.nullmoth.NVAccel` when PCI `vendor-id` is absent). If ambiguous, never label another GPU as NVIDIA and allow user selection.
   - Never invent or look up guessed GPU model names; if `IOPCIDevice` `"model"` is missing or generic (e.g., `"display"`, `"GFX0"`, `"NVAccel"`), display `"GPU detectada"`.
5. **Terminology & Accuracy**:
   - Keep `"Motor de vídeo"` (do **not** rename to `"NVENC"` or `"Encoder"`).
   - Keep `"Decodificação de vídeo"` without claiming app attribution.
   - Preserve the disclaimer: `"Os indicadores são fornecidos pelo driver, podem ter atraso e não identificam o aplicativo ou codec responsável."`
6. **IOKit Resource & CPU Hygiene**:
   - Every `io_iterator_t` and `io_registry_entry_t` must be paired with `IOObjectRelease` via `defer`.
   - Use targeted `IORegistryEntryCreateCFProperty` lookups instead of `IORegistryEntryCreateCFProperties` during polling so large blobs like `IOReportLegend` are not serialized every second.
   - Verify with `/usr/bin/leaks` after changing IOKit code.
7. **Scope & Project Boundaries**:
   - Stay local and read-only: no network calls, no `sudo`, no kext/EFI edits, no login auto-start (`SMAppService`), no historical charts, no telemetry, and no background daemons.
   - `GPUMonitor.xcodeproj/project.pbxproj` is maintained directly (no `xcodegen` dependency). If you add, remove, or rename Swift files, update `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, and `PBXSourcesBuildPhase` in `project.pbxproj` and run `xcodebuild test` to confirm.
