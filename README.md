# Grouped Task Manager

A fork of KDE Plasma's Icons-and-Text Task Manager with color-coded sticky groups.

Right-click any window tab to assign one of 8 colors. Same-colored tabs stay together as a group -- you can drag them around as a unit, and uncolored tabs flow freely between groups. New windows automatically inherit colors from their parent process.

## Features

- **8 color groups** via right-click context menu on any window tab
- **Sticky groups** -- same-colored tabs stay contiguous in the taskbar
- **Group-aware drag and drop** -- dragging a colored tab outside its group moves the whole group; uncolored tabs drag freely and groups reassemble on drop
- **Color inheritance** -- new windows inherit colors from:
  - Other windows of the same process (e.g. new Firefox windows)
  - The launching app via cgroup detection (e.g. apps launched from a colored terminal)
  - Direct parent processes via PID tree walking
- **Split focus indicator** -- active colored tabs show the selection highlight on one half and the color on the other, so both are always visible
- **Works on both horizontal and vertical panels**

When no colors are assigned, behavior is identical to the stock task manager.

## Requirements

- KDE Plasma 6
- Qt 6.6+
- KDE Frameworks 6

### Build dependencies

Your distro's Plasma development packages. On Arch/Manjaro:

```
sudo pacman -S base-devel cmake extra-cmake-modules qt6-base qt6-declarative \
  plasma-desktop plasma-workspace ksystemstats
```

On other distros, install the equivalent `-dev` or `-devel` packages for: Qt6 (Core, Qml, Quick, DBus), KF6 (Config, I18n, KIO, Notifications, Service, WindowSystem), Plasma, PlasmaActivities, KSysGuard, and plasma-workspace (for LibTaskManager and LibNotificationManager). Then send me a pull request to change this file, or just chuck an issue in with a list of the stuff you had to install, that's fine too.

## Building and installing

```bash
git clone https://github.com/ZorbaTHut/grouped-task-manager.git
cd grouped-task-manager
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build
```

Then restart Plasma:

```bash
kquitapp6 plasmashell && plasmashell &
```

Right-click your panel, choose "Add Widgets", and search for "Grouped Task Manager".

## Uninstalling

```bash
sudo rm /usr/lib/qt6/plugins/plasma/applets/org.kde.plasma.groupedtaskmanager.so
sudo rm -rf /usr/share/plasma/plasmoids/org.kde.plasma.groupedtaskmanager
sudo rm -rf /usr/lib/qt6/qml/plasma/applet/org/kde/plasma/groupedtaskmanager
```

## License

GPL-2.0-or-later, same as the original KDE Plasma Task Manager.

Based on the [KDE Plasma Desktop](https://invent.kde.org/plasma/plasma-desktop) task manager applet by Eike Hein and the KDE community.

## Vibes

This whole thing was extremely vibecoded because I don't understand QML. I have honestly not looked at the sourcecode. Perhaps someday I will! I'll update this either when I think of it or when someone posts an issue asking me to do it. Or pesters me on Discord. You can pester me on Discord if you want, but you'll have to figure out my username (this will be extremely easy.)
