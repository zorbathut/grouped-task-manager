# Grouped Task Manager

A fork of KDE Plasma's Icons-and-Text Task Manager with color-coded sticky groups.

Right-click any window tab to assign one of 24 colors. Same-colored tabs stay together as a group -- you can drag them around as a unit, and uncolored tabs flow freely between groups. New windows automatically inherit colors from their parent process.

## Features

- **24 color groups** via right-click context menu on any window tab
- **Sticky groups** -- same-colored tabs stay contiguous in the taskbar
- **Group-aware drag and drop** -- dragging a colored tab outside its group moves the whole group; uncolored tabs drag freely and groups reassemble on drop
- **Color inheritance** -- new windows inherit colors from:
  - Other windows of the same process (e.g. new Firefox windows)
  - The launching app via cgroup detection (e.g. apps launched from a colored terminal)
  - Direct parent processes via PID tree walking
- **Split focus indicator** -- active colored tabs show the selection highlight on one half and the color on the other, so both are always visible
- **Scriptable** -- a small DBus interface lets a script list windows and put them into named color groups (see [Scripting](#scripting))
- **Works on both horizontal and vertical panels**

When no colors are assigned, behavior is identical to the stock task manager.

## Requirements

- KDE Plasma 6.7+
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

## Scripting

The applet publishes a DBus interface so a script can open a set of windows and sort them into named color groups. It lives on the session bus at service `net.pavlovian.groupedtaskmanager`, object `/ColorGroups`, interface `net.pavlovian.groupedtaskmanager.ColorGroups`:

- `WindowList() -> a(ssi)` -- `(windowId, title, colorIndex)` for every window, including ones on other desktops, screens and activities. `colorIndex` is `0` for an uncolored window. Window ids are opaque brace-wrapped UUIDs like `{73e1fd2b-d232-4be9-9fc9-75d8163b89a9}`; quote them in a shell.
- `WindowAssign(s windowId, i colorIndex, s groupName) -> i colorIndex` -- puts the window in color `1`..`24`, or pass `-1` for the lowest color that has no windows. Returns the color actually used, so the rest of a group can be sent to the same place. A non-empty `groupName` renames the group; an empty one leaves its name alone.

Errors are named `net.pavlovian.groupedtaskmanager.Error.WindowUnknown`, `.ColorInvalid`, `.ColorNoneFree`, and `.Failed` for a bug in the applet. `busctl` prints only the message and drops the error name, so use `gdbus` or a real DBus binding if you need to tell them apart.

The applet only answers "which windows exist" and "color this one"; waiting for a window to appear is the script's job. That is what makes apps that open new windows inside an existing process (Konsole, JetBrains IDEs) workable: take a snapshot, launch, and wait for an id that wasn't in the snapshot. With python-dbus:

```python
import shutil, subprocess, time
import dbus

NAME = "net.pavlovian.groupedtaskmanager"
groups = dbus.Interface(dbus.SessionBus().get_object(NAME, "/ColorGroups"), NAME + ".ColorGroups")

def assign_new_window(cmd, color, name, title_hint=None, timeout=120):
    """Run cmd, wait for the window it opens, and put it in a color group. Returns the color used."""
    before = {str(win_id) for win_id, _, _ in groups.WindowList()}
    # setsid -f reports success even when cmd can't be executed, so check up front.
    if shutil.which(cmd[0]) is None:
        raise FileNotFoundError(cmd[0])
    # Own scope plus setsid -f: no ancestor or cgroup shared with this terminal, whose color the window would otherwise inherit first.
    subprocess.run(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--", "setsid", "-f", *cmd], check=True)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for win_id, title, _ in groups.WindowList():
            if str(win_id) in before or (title_hint and title_hint.lower() not in str(title).lower()):
                continue
            try:
                return int(groups.WindowAssign(win_id, color, name))
            except dbus.exceptions.DBusException as e:
                if e.get_dbus_name() != NAME + ".Error.WindowUnknown":
                    raise
                # The window closed between the list and the assign (a splash screen, say); keep waiting.
        time.sleep(0.3)
    raise TimeoutError(f"no new window from {cmd!r} within {timeout}s")

game = assign_new_window(["rider", "/home/me/werk/game"], -1, "Game", title_hint="game")
assign_new_window(["konsole", "--workdir", "/home/me/werk/game"], game, "")
```

Things to know:

- The interface is unauthenticated: anything on your session bus can list your window titles and recolor them. Plasma's own window runner already exposes titles the same way, but this is meant for a personal machine, not as something a distribution should ship enabled. The object is also reachable through plasmashell's other bus names, not just this one.
- Only one instance of the applet provides the interface. If you have it on two panels and remove the one that registered first, the interface is gone until plasmashell restarts.
- A window opened inside an already-running colored process (a second Konsole window, a second Rider project) briefly takes that process's color before the script recolors it; detaching the launch can't prevent that, since the window really does belong to the colored process.
- Naming a group with its built-in name ("Blue" for color 2) just clears any custom name.
- A color counts as free when no window is assigned to it, and a group's custom name is dropped as soon as its last window leaves, including when that window is recolored.

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
