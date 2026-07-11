/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasmoid
import plasma.applet.org.kde.plasma.groupedtaskmanager as TaskManagerApplet

DropArea {
    id: dropArea
    signal urlsDropped(var urls)

    property Item target
    property Item ignoredItem
    property Item hoveredItem
    property bool isGroupDialog: false
    property bool moved: false

    property alias handleWheelEvents: wheelHandler.handleWheelEvents

    // Drag move coalescing: save the latest cursor position and process
    // only the most recent one on the next event loop pass. This skips
    // redundant intermediate moves when the UI can't keep up.
    property real _pendingDragX: 0
    property real _pendingDragY: 0

    Timer {
        id: dragCoalesceTimer
        interval: 0
        onTriggered: dropArea._processDragMove(dropArea._pendingDragX, dropArea._pendingDragY)
    }

    function _processDragMove(x, y) {
        // Never reorder while items are animating to new positions:
        // childAt() hit-tests items at their transient animated spots,
        // which yields bogus targets and oscillating moves. Retry once
        // the layout has settled. (onPositionChanged has this guard for
        // direct events; the coalescing timer must apply it too.)
        if (target.animating) {
            dragCoalesceTimer.restart();
            return;
        }

        let above;
        if (isGroupDialog) {
            above = target.itemAt(x, y);
        } else {
            above = target.childAt(x, y);
        }

        // Only Task delegates are valid drop targets. GroupHeader rows
        // share the same GridLayout, and their .index is a color palette
        // index (0-15), not a model row — using it as a move target
        // teleports the dragged task.
        if (!above || !(above instanceof Task)) {
            return;
        }

        // If we're mixing launcher tasks with other tasks and are moving
        // a (small) launcher task across a non-launcher task, don't allow
        // the latter to be the move target twice in a row for a while, as
        // it will naturally be moved underneath the cursor as result of the
        // initial move, due to being far larger than the launcher delegate.
        // TODO: This restriction (minus the timer, which improves things)
        // has been proven out in the EITM fork, but could be improved later
        // by tracking the cursor movement vector and allowing the drag if
        // the movement direction has reversed, establishing user intent to
        // move back.
        if (!Plasmoid.configuration.separateLaunchers
                && tasks.dragSource?.model.IsLauncher
                && !above.model.IsLauncher
                && above === ignoredItem) {
            return;
        } else {
            ignoredItem = null;
        }

        if (tasksModel.sortMode === TaskManager.TasksModel.SortManual && tasks.dragSource) {
            // Reject drags between different TaskList instances.
            if (tasks.dragSource.parent !== above.parent) {
                return;
            }

            const insertAt = above.index;

            if (tasks.dragSource !== above && tasks.dragSource.index !== insertAt) {
                if (tasks.groupDialog) {
                    tasksModel.move(tasks.dragSource.index, insertAt,
                        tasksModel.makeModelIndex(tasks.groupDialog.visualParent.index));
                } else {
                    // Color group-aware drag logic
                    const dragWinId = tasks.getWindowIdForTask(tasks.dragSource);
                    const dragColor = dragWinId !== "" ? colorManager.getColor(dragWinId) : 0;

                    if (dragColor > 0) {
                        const bounds = tasks.findColorGroupBounds(dragColor);
                        const insideGroup = (insertAt >= bounds.first && insertAt <= bounds.last);

                        if (insideGroup) {
                            // Normal single-item move within the color group
                            tasksModel.move(tasks.dragSource.index, insertAt);
                        } else {
                            // Move the group by 1 position toward the cursor by
                            // moving the adjacent non-group item across the group.
                            // This is O(1) per event and prevents oscillation
                            // (unlike moving all N group members at once).
                            if (insertAt < bounds.first && bounds.first > 0) {
                                tasksModel.move(bounds.first - 1, bounds.last);
                            } else if (insertAt > bounds.last && bounds.last < taskRepeater.count - 1) {
                                tasksModel.move(bounds.last + 1, bounds.first);
                            }
                        }
                    } else {
                        // Uncolored task: allow drag anywhere freely.
                        // Contiguity enforcement will clean up after
                        // the drag ends.
                        tasksModel.move(tasks.dragSource.index, insertAt);
                    }
                }

                tasks._recomputeRowLayout();

                ignoredItem = above;
                ignoreItemTimer.restart();

                // Color group moves advance 1 position per step. If the
                // source hasn't reached the cursor yet, keep going next
                // frame so the group catches up smoothly.
                if (tasks.dragSource !== above && tasks.dragSource.index !== insertAt) {
                    dragCoalesceTimer.restart();
                }
            }
        }
    }

    //ignore anything that is neither internal to TaskManager or a URL list
    onEntered: event => {
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
        }
        if (target.animating) { // Not all targets have an animating property
            target.animating = false;
        }
    }

    onPositionChanged: event => {
        // For drag moves, coalesce events: only process the most recent
        // position on the next event loop pass, skipping intermediate ones.
        // Always record the position, even mid-animation — _processDragMove
        // defers until the layout settles, and dropping the event here
        // would lose the cursor's final resting position.
        if (tasksModel.sortMode === TaskManager.TasksModel.SortManual && tasks.dragSource) {
            _pendingDragX = event.x;
            _pendingDragY = event.y;
            dragCoalesceTimer.restart();
            return;
        }

        if (target.animating) {
            return;
        }

        // Non-drag hover: process immediately for activation timer
        let above;
        if (isGroupDialog) {
            above = target.itemAt(event.x, event.y);
        } else {
            above = target.childAt(event.x, event.y);
        }

        // GroupHeader rows are not hoverable tasks (activationTimer and
        // urlsDropped both assume hoveredItem is a Task).
        if (!above || !(above instanceof Task)) {
            hoveredItem = null;
            activationTimer.stop();
            return;
        }

        if (hoveredItem !== above) {
            hoveredItem = above;
            activationTimer.restart();
        }
    }

    onExited: {
        hoveredItem = null;
        activationTimer.stop();
    }

    onDropped: event => {
        // Reject internal drops.
        if (event.formats.indexOf("application/x-orgkdeplasmataskmanager_taskbuttonitem") >= 0) {
            event.accepted = false;
            return;
        }

        // Reject plasmoid drops.
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
            return;
        }

        if (event.hasUrls) {
            urlsDropped(event.urls);
            return;
        }
    }

    Connections {
        target: tasks

        function onDragSourceChanged(): void {
            if (!dragSource) {
                dropArea.ignoredItem = null;
                ignoreItemTimer.stop();
            }
        }
    }

    Timer {
        id: ignoreItemTimer

        repeat: false
        interval: 750

        onTriggered: {
            dropArea.ignoredItem = null;
        }
    }

    Timer {
        id: activationTimer

        interval: 250
        repeat: false

        onTriggered: {
            if (parent.hoveredItem.model.IsGroupParent) {
                TaskManagerApplet.TaskTools.createGroupDialog(parent.hoveredItem, tasks);
            } else if (!parent.hoveredItem.model.IsLauncher) {
                tasksModel.requestActivate(parent.hoveredItem.modelIndex());
            }
        }
    }

    WheelHandler {
        id: wheelHandler

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property bool handleWheelEvents: true

        enabled: handleWheelEvents && Plasmoid.configuration.wheelEnabled !== 0

        onWheel: event => {
            // magic number 15 for common "one scroll"
            // See https://doc.qt.io/qt-6/qml-qtquick-wheelhandler.html#rotation-prop
            let increment = 0;
            while (rotation >= 15) {
                rotation -= 15;
                increment++;
            }
            while (rotation <= -15) {
                rotation += 15;
                increment--;
            }
            const anchor = dropArea.target.childAt(event.x, event.y);
            if (Plasmoid.configuration.wheelEnabled === 3) {
                const loudest = anchor?.audioStreams?.reduce((loudest, stream) => Math.max(loudest, stream.volume), 0)
                const step = (pulseAudio.item.normalVolume - pulseAudio.item.minimalVolume) * pulseAudio.item.globalConfig.volumeStep / 100;
                anchor?.audioStreams?.forEach((stream) => {
                    let delta = step * increment;
                    if (loudest > 0) {
                        delta *= stream.volume / loudest;
                    }
                    const volume = stream.volume + delta;
                    console.log(volume, Math.max(pulseAudio.item.minimalVolume, Math.min(volume, pulseAudio.item.normalVolume)));
                    stream.model.Volume = Math.max(pulseAudio.item.minimalVolume, Math.min(volume, pulseAudio.item.normalVolume));
                    stream.model.Muted = volume === 0
                })
            return;
            }
            while (increment !== 0) {
                TaskManagerApplet.TaskTools.activateNextPrevTask(anchor, increment < 0, Plasmoid.configuration.wheelSkipMinimized, Plasmoid.configuration.wheelEnabled, tasks);
                increment += (increment < 0) ? 1 : -1;
            }
        }
    }
}
