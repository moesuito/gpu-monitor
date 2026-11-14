# GPU Monitor

**GPU Monitor** is a lightweight, native macOS (`x86_64`) menu bar monitor app for **NVIDIA GPUs** using the **NullMoth** driver (`IOAccelerator` / `NVAccel`).

Written natively in Swift and SwiftUI, it lives in the macOS menu bar with an Apple-native, Stats-inspired popover—showing circular temperature and core gauges, an interactive rolling usage history chart, and individual live usage graphs for every percentage metric read directly from `IORegistry`'s `PerformanceStatistics` dictionary.

## Features

### Menu Bar Item
- Subtle `cpu` SF Symbol next to the GPU Core percentage (for example, `GPU 18%`), using monospaced digits.
- Polls roughly every **1 second** even while the popover is closed.
- Displays `GPU —` (never `0%`) whenever `GPU Core Utilization %` is unavailable or fails to read.
- Runs as a pure menu bar utility (`LSUIElement = true`) with no Dock icon and no automatic main window.

### Popover Dashboard
- **GPU Identification**: Reads the parent `IOPCIDevice` `model` property reliably (for example, `NVIDIA GeForce RTX 3060 Laptop GPU`), or falls back to `Detected GPU` without guessing a model name.
- **Multi-GPU Selection** (shown when multiple `IOAccelerator` devices exist): Automatically chooses the NVIDIA device when unambiguously identifiable (`vendor-id == 0x10de` / non-conflicting signals) or lets you pick a device manually without ever summing GPUs or mislabeling another GPU as NVIDIA.
- **Circular Hero Gauges**: Displays **Temperature** (`Temperature(C)` in `°C`, never treated as a percentage) and **GPU Utilization**.
- **Interactive Usage History Graph** (`60s` rolling window): Inspect **GPU Utilization**, **Memory Utilization**, **Video Engine**, **Video Decode**, or **All Percentages** side by side (never summed), or click any metric card below to focus it.
- **2×2 Metric Chart Grid** (`0–100%` visual scale):
  1. **GPU Utilization** — `GPU Core Utilization %`
  2. **Memory Utilization** — `GPU Memory Utilization %`
  3. **Video Engine** — `GPU Video Engine Utilization %`
  4. **Video Decode** — `GPU Video Decode Utilization %`
  *(Note: NullMoth `NVAccel` populates `Device Utilization %` identically from the exact same internal counter as `GPU Core Utilization %`, so the redundant entry is omitted.)*
- **Honest Anomaly Handling**:
  - Missing, boolean, non-numeric, or unreadable properties display `Unavailable` (and leave gaps in time-series graphs rather than dropping to `0%`).
  - Values outside `0–100%` preserve the raw numeric reading and show an unexpected-value warning while clamping only the visual bar/plot bounds.
  - Read errors display an explicit error banner instead of stale numbers.
- **Launch at Login (Opt-in, Disabled by Default)**: Uses native `SMAppService.mainApp` only when you explicitly turn on the **Launch at login** switch in the popover.
- **Quit (`⌘Q`)** button for clean termination and full native **Light / Dark** appearance support.

## How Collection Works

- **Primary Reader (`IOKit`)**: Enumerates `IOAccelerator` entries with `IOServiceGetMatchingServices` and performs targeted `IORegistryEntryCreateCFProperty` lookups—no shell execution, no `sudo`, no permission changes, no kernel extension changes, and no EFI edits.
- **Structured Fallback (`ioreg`)**: If direct `IOKit` reading fails, runs `/usr/sbin/ioreg -r -c IOAccelerator -d 1 -a` in the background with a timeout and parses the XML plist regardless of key order.
- **Local & Read-Only**: Zero internet communication, zero telemetry, and zero background helper daemons.

## Accuracy & Limitations

> Indicators are provided by the driver, may lag, and do not identify the responsible app or codec.

- `GPU Video Engine Utilization %` is intentionally labeled **Video Engine** (not `NVENC` or `Encoder`).
- A positive utilization reading alone does not prove that a specific application is using hardware acceleration.

## Requirements & Build Instructions

- Intel macOS (`x86_64`, `MACOSX_DEPLOYMENT_TARGET = 14.0`) — tested on macOS Tahoe 26.7.3 with NullMoth 3.0.
- Xcode (tested with Xcode 26.6).

### Build & Run from Xcode
1. Open `GPUMonitor.xcodeproj`.
2. Select the **GPUMonitor** scheme (`My Mac`).
3. Press `⌘R` to run or `⌘U` to execute the unit tests.

### Build & Test from Terminal
```bash
# Run unit tests (x86_64)
xcodebuild test -project GPUMonitor.xcodeproj -scheme GPUMonitor -destination 'platform=macOS,arch=x86_64'

# Build Release app bundle (x86_64)
xcodebuild build -project GPUMonitor.xcodeproj -scheme GPUMonitor -configuration Release -destination 'platform=macOS,arch=x86_64'
```

To install, copy the compiled `GPU Monitor.app` bundle into `/Applications` and launch it. (Moving the app to `/Applications` first is recommended before enabling **Launch at login**.)

## Repository Structure

```text
gpu-monitor/
├── AGENTS.md                                  # Context and strict invariants for AI coding agents
├── README.md
├── GPUMonitor.xcodeproj/                      # Xcode project and shared scheme
├── GPUMonitor/
│   ├── GPUMonitorApp.swift                    # MenuBarExtra (.window) + AppDelegate (.accessory)
│   ├── Info.plist                             # LSUIElement = true
│   ├── Models/
│   │   ├── GPUMetrics.swift                   # Types, IORegistry parser, multi-GPU policy, formatters
│   │   └── MetricHistory.swift                # Bounded 60s rolling buffer with unavailable-gap segmentation
│   ├── Services/
│   │   ├── GPUCollecting.swift                # Protocol and CompositeGPUCollector
│   │   ├── IOKitGPUCollector.swift            # Direct IOKit / IORegistry collector
│   │   ├── IORegFallbackCollector.swift       # Structured /usr/sbin/ioreg -a fallback
│   │   └── LoginItemService.swift             # Opt-in SMAppService.mainApp wrapper (off by default)
│   ├── ViewModels/
│   │   └── GPUMonitorViewModel.swift          # Async ~1s polling, history tracking, UI state
│   └── Views/
│       ├── MenuBarPanelView.swift             # Native Apple / Stats-inspired menu bar popover
│       ├── MetricRowView.swift                # Per-metric card with bar and live sparkline
│       └── UsageHistoryChartView.swift        # Native Canvas time-series chart renderer
└── GPUMonitorTests/
    └── GPUMonitorTests.swift                  # Unit and host integration tests
```
