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

        if (tasksModel.sortMode !== TaskManager.TasksModel.SortManual || !tasks.dragSource) {
            return;
        }

        // Reject drags between different TaskList instances.
        if (tasks.dragSource.parent !== above.parent) {
            return;
        }

        if (tasks.groupDialog) {
            const insertAt = above.index;
            if (tasks.dragSource !== above && tasks.dragSource.index !== insertAt) {
                tasksModel.move(tasks.dragSource.index, insertAt,
                    tasksModel.makeModelIndex(tasks.groupDialog.visualParent.index));
            }
            return;
        }

        // Block-based reordering: both the dragged selection (its whole
        // color group, or just itself when uncolored) and the hovered
        // target (likewise) are treated as atomic blocks. The dragged
        // block hops to the far side of the hovered block only once the
        // cursor crosses the hovered block's pixel midpoint. That rule is
        // self-stabilizing: right after a hop the cursor is still past
        // the midpoint, so the reverse hop can't trigger — this also
        // covers the small-launcher-over-wide-task oscillation the old
        // ignoredItem timer worked around. Groups stay contiguous for the
        // entire drag, so no post-drop snap-back correction is needed.
        const dragWinId = tasks.getWindowIdForTask(tasks.dragSource);
        const dragColor = dragWinId !== "" ? colorManager.getColor(dragWinId) : 0;
        const dragBlock = dragColor > 0
            ? tasks.findColorGroupBounds(dragColor)
            : { first: tasks.dragSource.index, last: tasks.dragSource.index };

        // Within the dragged block itself: plain single-item rearrange.
        if (above.index >= dragBlock.first && above.index <= dragBlock.last) {
            if (tasks.dragSource !== above && tasks.dragSource.index !== above.index) {
                tasksModel.move(tasks.dragSource.index, above.index);
                tasks._recomputeRowLayout();
            }
            return;
        }

        const aboveWinId = tasks.getWindowIdForTask(above);
        const aboveColor = aboveWinId !== "" ? colorManager.getColor(aboveWinId) : 0;
        const hoverBlock = aboveColor > 0
            ? tasks.findColorGroupBounds(aboveColor)
            : { first: above.index, last: above.index };

        // Pixel extents of a block along the panel's flow axis, in the
        // same coordinate space childAt() was queried in.
        function blockSpan(first, last) {
            let lo = Infinity, hi = -Infinity;
            for (let i = first; i <= last; i++) {
                const item = taskRepeater.itemAt(i);
                if (!item) continue;
                const p0 = tasks.vertical ? item.y : item.x;
                const p1 = p0 + (tasks.vertical ? item.height : item.width);
                lo = Math.min(lo, p0);
                hi = Math.max(hi, p1);
            }
            return { lo: lo, hi: hi };
        }

        const hoverSpan = blockSpan(hoverBlock.first, hoverBlock.last);
        const dragSpan = blockSpan(dragBlock.first, dragBlock.last);
        if (!isFinite(hoverSpan.lo) || !isFinite(dragSpan.lo)) {
            return;
        }

        const hoverMid = (hoverSpan.lo + hoverSpan.hi) / 2;
        const dragCenter = (dragSpan.lo + dragSpan.hi) / 2;
        const cursorPos = tasks.vertical ? y : x;

        // Crossed: the cursor and the dragged block sit on opposite sides
        // of the hovered block's midpoint, so the dragged block goes to
        // the far side. Otherwise it goes to the near side — which skips
        // over any items lying between the two blocks, and is a no-op
        // when they're already adjacent. Geometry-based sign comparison
        // keeps this correct under RTL mirroring and reverse mode.
        const crossed = (cursorPos - hoverMid) * (dragCenter - hoverMid) < 0;

        const dragLen = dragBlock.last - dragBlock.first + 1;
        let blockStart;
        if (hoverBlock.first > dragBlock.last) {
            blockStart = crossed ? hoverBlock.last + 1 - dragLen : hoverBlock.first - dragLen;
        } else {
            blockStart = crossed ? hoverBlock.first : hoverBlock.last + 1;
        }

        if (blockStart !== dragBlock.first) {
            tasks.moveBlock(dragBlock.first, dragBlock.last, blockStart);
            tasks._recomputeRowLayout();
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
