# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Color-coded task manager widget for KDE Plasma 6. Fork of the built-in Icons-and-Text Task Manager with color-based window grouping. C++20/Qt6/QML, built with CMake.

## Build & Install

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build
kquitapp6 plasmashell && plasmashell &   # restart to load changes
```

Requires: CMake 3.22+, Qt 6.6+, KF6 6.0+, ECM, plus KDE Plasma 6 development headers (plasma-workspace, libksysguard, plasma-activities).

There are no tests or linting infrastructure.

## Architecture

### C++ Layer
- **backend.cpp/h** — Native utilities exposed to QML: jump list actions, places/recent documents, and critically `parentPid(pid)` (process tree walking) and `launcherPidsFromCgroup(pid)` (reads /proc cgroup to find launcher PIDs).
- **colormanager.cpp/h** — Maps window IDs to color indices (1–8). Persists assignments to Plasmoid config. Emits change signals for QML bindings.
- **smartlauncherbackend/item** — DBus integration for Unity launcher badges and progress bars.

### QML Layer
- **main.qml** (~900 lines) — Core applet logic. Owns the color system, contiguity enforcement, activation tracking, and color inheritance. This is where most feature work happens.
- **Task.qml** — Individual taskbar button: color indicator, split focus display, badges, audio icons.
- **TaskList.qml** — Layout manager handling horizontal/vertical panel modes.
- **MouseHandler.qml** — Drag/drop with per-frame coalescing and color-aware movement.
- **GroupHeader.qml** — Color group headers in vertical single-stripe mode, with click-to-edit names.
- **ContextMenu.qml** — Right-click menu including color assignment submenu.

### Key Mechanisms

**Color Inheritance** — When a new window appears, three strategies run in order to auto-assign a color:
1. Same-PID sibling: if another window from the same process already has a color
2. Cgroup launcher detection: parses /proc/{pid}/cgroup to find the launcher PID
3. Parent process tree: walks up to 5 levels of parent PIDs looking for colored ancestors

**Contiguity Enforcement** — `enforceColorContiguity()` keeps same-colored tasks adjacent via drag-reordering. Triggered by a timer after model changes.

**Activation Tracking** — Records most recent active window per PID with a 150ms settlement timer to filter rapid focus bouncing (e.g., Konsole tab creation). Used to disambiguate multi-window processes with different colors.

### Configuration
- **main.xml** — KConfig schema for all settings. Color assignments stored as StringLists (`"windowId=colorIndex"`). Custom group names stored similarly.
- **metadata.json** — Plasma applet metadata, plugin ID: `org.kde.plasma.groupedtaskmanager`.
