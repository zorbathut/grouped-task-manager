/*
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

import org.kde.plasma.workspace.trianglemousefilter

import org.kde.taskmanager as TaskManager
import plasma.applet.org.kde.plasma.groupedtaskmanager as TaskManagerApplet
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: tasks

    // For making a bottom to top layout since qml flow can't do that.
    // We just hang the task manager upside down to achieve that.
    // This mirrors the tasks and group dialog as well, so we un-rotate them
    // to fix that (see Task.qml and GroupDialog.qml).
    rotation: Plasmoid.configuration.reverseMode && Plasmoid.formFactor === PlasmaCore.Types.Vertical ? 180 : 0

    readonly property bool shouldShrinkToZero: tasksModel.count === 0
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool iconsOnly: Plasmoid.pluginName === "org.kde.plasma.icontasks"

    property Task toolTipOpenedByClick
    property Task toolTipAreaItem

    // Color group system
    readonly property var colorGroupColors: [
        "#e74c3c", "#3498db", "#2ecc71", "#f1c40f",
        "#e67e22", "#9b59b6", "#1abc9c", "#e91e63"
    ]
    readonly property var colorGroupNames: [
        "Red", "Blue", "Green", "Yellow",
        "Orange", "Purple", "Teal", "Pink"
    ]

    // Custom category names
    property var _customNameMap: ({})
    property int colorAssignmentGeneration: 0
    readonly property real groupHeaderHeight: Kirigami.Units.gridUnit * 0.9

    // Row layout for vertical single-stripe mode: interleaves header rows before each color group
    property var _rowLayout: ({ taskRows: [], headerRows: {}, headerCount: 0 })
    readonly property int activeHeaderCount: _rowLayout.headerCount || 0

    function _recomputeRowLayout() {
        let count = taskRepeater.count;
        if (!vertical || taskList.stripeCount !== 1 || count === 0) {
            _rowLayout = { taskRows: [], headerRows: {}, headerCount: 0 };
            return;
        }
        let taskRows = [];
        let headerRows = {};
        let offset = 0;
        for (let i = 0; i < count; i++) {
            let color = getColorForTaskIndex(i);
            if (color > 0 && (i === 0 || getColorForTaskIndex(i - 1) !== color)) {
                headerRows[color] = i + offset;
                offset++;
            }
            taskRows.push(i + offset);
        }
        _rowLayout = { taskRows: taskRows, headerRows: headerRows, headerCount: offset };
    }

    onColorAssignmentGenerationChanged: _recomputeRowLayout()

    function _parseCustomNames() {
        let map = {};
        let entries = Plasmoid.configuration.colorGroupCustomNames;
        for (let i = 0; i < entries.length; i++) {
            let eq = entries[i].indexOf("=");
            if (eq > 0) {
                let idx = parseInt(entries[i].substring(0, eq));
                let name = entries[i].substring(eq + 1);
                if (idx >= 1 && idx <= 8 && name.length > 0) {
                    map[idx] = name;
                }
            }
        }
        _customNameMap = map;
    }

    function getColorGroupName(colorIndex) {
        if (_customNameMap[colorIndex]) return _customNameMap[colorIndex];
        if (colorIndex >= 1 && colorIndex <= 8) return colorGroupNames[colorIndex - 1];
        return "";
    }

    function setColorGroupName(colorIndex, name) {
        let newMap = Object.assign({}, _customNameMap);
        name = name.trim();
        if (name === "" || name === colorGroupNames[colorIndex - 1]) {
            delete newMap[colorIndex];
        } else {
            newMap[colorIndex] = name;
        }
        _customNameMap = newMap;
        let entries = [];
        for (let k in newMap) {
            entries.push(k + "=" + newMap[k]);
        }
        Plasmoid.configuration.colorGroupCustomNames = entries;
    }

    readonly property TaskManagerApplet.ColorManager colorManager: TaskManagerApplet.ColorManager {
        id: colorManager
        onColorAssignmentsChanged: {
            Plasmoid.configuration.colorGroupAssignments = colorAssignments;
        }
        onWindowColorChanged: (windowId, colorIndex) => {
            enforceContiguityTimer.restart();
            tasks.colorAssignmentGeneration++;
        }
        Component.onCompleted: {
            colorAssignments = Plasmoid.configuration.colorGroupAssignments;
        }
    }

    property bool _enforcing: false

    Timer {
        id: enforceContiguityTimer
        interval: 50
        onTriggered: tasks.enforceColorContiguity()
    }

    // Deferred color inheritance: queue windows and process them on the
    // next event loop iteration, after all windows from the current batch
    // (e.g. session restore) have been added to the repeater. This ensures
    // the "all siblings colored" check sees the full set of windows.
    property var _pendingInheritance: []
    Timer {
        id: inheritanceTimer
        interval: 0
        onTriggered: tasks.processPendingInheritance()
    }

    // Deferred stale cleanup: must run after the Repeater has finished
    // processing the row removal, otherwise model data objects still
    // have pre-removal indices and colorAssignmentsChanged handlers
    // read WinIdList from the wrong row.
    Timer {
        id: staleCleanupTimer
        interval: 0
        onTriggered: {
            let activeIds = [];
            for (let i = 0; i < taskRepeater.count; i++) {
                let wid = tasks.getWindowIdForTask(taskRepeater.itemAt(i));
                if (wid !== "") activeIds.push(wid);
            }
            colorManager.removeStale(activeIds);
        }
    }

    function processPendingInheritance() {
        let pending = _pendingInheritance;
        _pendingInheritance = [];
        for (let item of pending) {
            processColorInheritance(item.winId, item.pid);
        }
        // Ensure colored tasks are grouped contiguously after the
        // initial batch is processed (covers both inherited colors
        // and colors loaded from config).
        enforceContiguityTimer.restart();
    }

    function processColorInheritance(winId, pid) {
        if (colorManager.getColor(winId)) return; // already colored

        // Strategy 0: Same PID — inherit only if ALL same-PID siblings
        // share one color. If any sibling is uncolored, the user chose
        // not to color it, so new windows shouldn't auto-inherit.
        let pidColor = 0;
        let pidColorConsistent = true;
        let hasSiblings = false;
        for (let i = 0; i < taskRepeater.count; i++) {
            let other = taskRepeater.itemAt(i);
            if (!other || other.pid !== pid) continue;
            let otherWinId = getWindowIdForTask(other);
            if (otherWinId === winId) continue;
            hasSiblings = true;
            let c = colorManager.getColor(otherWinId);
            if (c > 0) {
                if (pidColor === 0) {
                    pidColor = c;
                } else if (pidColor !== c) {
                    pidColorConsistent = false;
                    break;
                }
            } else {
                // Uncolored sibling exists — don't inherit.
                pidColorConsistent = false;
                break;
            }
        }
        if (hasSiblings && pidColor > 0 && pidColorConsistent) {
            colorManager.setColor(winId, pidColor);
            return;
        }

        // Strategy 1: cgroup-based launcher detection
        let launcherPids = backend.launcherPidsFromCgroup(pid);
        for (let p = 0; p < launcherPids.length && !colorManager.getColor(winId); p++) {
            let lPid = launcherPids[p];
            for (let i = 0; i < taskRepeater.count; i++) {
                let other = taskRepeater.itemAt(i);
                if (other && other.pid === lPid) {
                    let otherWinId = getWindowIdForTask(other);
                    let parentColor = colorManager.getColor(otherWinId);
                    if (parentColor > 0) {
                        colorManager.setColor(winId, parentColor);
                        break;
                    }
                }
            }
        }

        // Strategy 2: PID tree walk (direct parent-child)
        if (!colorManager.getColor(winId)) {
            let walkPid = pid;
            for (let depth = 0; depth < 5 && walkPid > 1; depth++) {
                walkPid = backend.parentPid(walkPid);
                if (walkPid <= 0) break;
                for (let i = 0; i < taskRepeater.count; i++) {
                    let other = taskRepeater.itemAt(i);
                    if (other && other.pid === walkPid) {
                        let otherWinId = getWindowIdForTask(other);
                        let parentColor = colorManager.getColor(otherWinId);
                        if (parentColor > 0) {
                            colorManager.setColor(winId, parentColor);
                            break;
                        }
                    }
                }
                if (colorManager.getColor(winId) > 0) break;
            }
        }
    }

    function getWindowIdForTask(task) {
        if (!task || !task.model || !task.model.WinIdList) return "";
        let ids = task.model.WinIdList;
        return ids.length > 0 ? String(ids[0]) : "";
    }

    function getColorForTaskIndex(idx) {
        let task = taskRepeater.itemAt(idx);
        return colorManager.getColor(getWindowIdForTask(task));
    }

    function enforceColorContiguity() {
        if (_enforcing) return;
        if (tasksModel.sortMode !== TaskManager.TasksModel.SortManual) return;
        if (dragSource) return; // Don't enforce during active drags

        _enforcing = true;

        // Build a map of which indices have which colors
        let count = taskRepeater.count;
        // For each color, find all task indices that have it
        let colorGroups = {}; // colorIndex -> [taskIndices]
        for (let i = 0; i < count; i++) {
            let c = getColorForTaskIndex(i);
            if (c > 0) {
                if (!colorGroups[c]) colorGroups[c] = [];
                colorGroups[c].push(i);
            }
        }

        // For each color group, check if indices are contiguous.
        // If not, move stray members to be adjacent to the first member.
        let moved = false;
        for (let color in colorGroups) {
            let indices = colorGroups[color];
            if (indices.length <= 1) continue;

            // Check contiguity: all indices should be consecutive
            let isContiguous = true;
            for (let j = 1; j < indices.length; j++) {
                if (indices[j] !== indices[j-1] + 1) {
                    isContiguous = false;
                    break;
                }
            }

            if (!isContiguous) {
                // Move all members to be after the first member's position
                let anchor = indices[0];
                for (let j = 1; j < indices.length; j++) {
                    let currentIdx = indices[j];
                    let targetIdx = anchor + j;
                    if (currentIdx !== targetIdx) {
                        tasksModel.move(currentIdx, targetIdx);
                        moved = true;
                        // After a move, indices shift — restart the whole check
                        _enforcing = false;
                        enforceContiguityTimer.restart();
                        return;
                    }
                }
            }
        }

        colorAssignmentGeneration++;
        _enforcing = false;
    }

    function findColorGroupBounds(color) {
        let first = -1;
        let last = -1;
        for (let i = 0; i < taskRepeater.count; i++) {
            if (getColorForTaskIndex(i) === color) {
                if (first === -1) first = i;
                last = i;
            }
        }
        return { first: first, last: last };
    }

    function moveColorGroup(color, draggedIndex, targetIndex) {
        // Collect all indices of tasks with this color, in order
        let groupIndices = [];
        for (let i = 0; i < taskRepeater.count; i++) {
            if (getColorForTaskIndex(i) === color) {
                groupIndices.push(i);
            }
        }
        if (groupIndices.length === 0) return;

        // Find position of dragged item within the group
        let dragPosInGroup = groupIndices.indexOf(draggedIndex);
        if (dragPosInGroup === -1) return;

        // Calculate where the group should start so the dragged item
        // ends up at or near targetIndex
        let groupStart = targetIndex - dragPosInGroup;
        groupStart = Math.max(0, Math.min(groupStart, taskRepeater.count - groupIndices.length));

        let originalFirst = groupIndices[0];
        if (groupStart === originalFirst) return; // already in place

        // The group is contiguous (enforced by enforceColorContiguity),
        // so after each move we know exactly where members are without
        // rescanning. Moving left: items above source don't shift.
        // Moving right: items below source don't shift.
        if (groupStart < originalFirst) {
            for (let j = 0; j < groupIndices.length; j++) {
                tasksModel.move(originalFirst + j, groupStart + j);
            }
        } else {
            for (let j = groupIndices.length - 1; j >= 0; j--) {
                tasksModel.move(originalFirst + j, groupStart + j);
            }
        }
        colorAssignmentGeneration++;
    }

    readonly property Component contextMenuComponent: Qt.createComponent("ContextMenu.qml")
    readonly property Component pulseAudioComponent: Qt.createComponent("PulseAudio.qml")

    property alias taskList: taskList

    preferredRepresentation: fullRepresentation

    Plasmoid.constraintHints: Plasmoid.CanFillArea

    Plasmoid.onUserConfiguringChanged: {
        if (Plasmoid.userConfiguring && groupDialog !== null) {
            groupDialog.visible = false;
        }
    }

    Layout.fillWidth: vertical ? true : Plasmoid.configuration.fill
    Layout.fillHeight: !vertical ? true : Plasmoid.configuration.fill
    Layout.minimumWidth: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        return vertical ? 0 : TaskManagerApplet.LayoutMetrics.preferredMinWidth();
    }
    Layout.minimumHeight: {
        if (shouldShrinkToZero) {
            return Kirigami.Units.gridUnit; // For edit mode
        }
        return !vertical ? 0 : TaskManagerApplet.LayoutMetrics.preferredMinHeight();
    }

//BEGIN TODO: this is not precise enough: launchers are smaller than full tasks
    Layout.preferredWidth: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            return Kirigami.Units.gridUnit * 10;
        }
        return taskList.Layout.maximumWidth
    }
    Layout.preferredHeight: {
        if (shouldShrinkToZero) {
            return 0.01;
        }
        if (vertical) {
            return taskList.Layout.maximumHeight
        }
        return Kirigami.Units.gridUnit * 2;
    }
//END TODO

    property Item dragSource

    signal requestLayout

    onDragSourceChanged: {
        if (dragSource === null) {
            tasksModel.syncLaunchers();
            // Re-enforce contiguity after drag ends
            enforceContiguityTimer.restart();
            colorAssignmentGeneration++;
        }
    }

    function windowsHovered(winIds: var, hovered: bool): DBus.DBusPendingReply {
        if (!Plasmoid.configuration.highlightWindows) {
            return;
        }
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.HighlightWindow", path: "/org/kde/KWin/HighlightWindow", iface: "org.kde.KWin.HighlightWindow", member: "highlightWindows", arguments: [hovered ? winIds : []], signature: "(as)"});
    }

    function cancelHighlightWindows(): DBus.DBusPendingReply {
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.HighlightWindow", path: "/org/kde/KWin/HighlightWindow", iface: "org.kde.KWin.HighlightWindow", member: "highlightWindows", arguments: [[]], signature: "(as)"});
    }

    function activateWindowView(winIds: var): DBus.DBusPendingReply {
        if (!effectWatcher.registered) {
            return;
        }
        cancelHighlightWindows();
        return DBus.SessionBus.asyncCall({service: "org.kde.KWin.Effect.WindowView1", path: "/org/kde/KWin/Effect/WindowView1", iface: "org.kde.KWin.Effect.WindowView1", member: "activate", arguments: [winIds.map(s => String(s))], signature: "(as)"});
    }

    function publishIconGeometries(taskItems: /*list<Item>*/var): void {
        if (TaskManagerApplet.TaskTools.taskManagerInstanceCount >= 2) {
            return;
        }
        for (let i = 0; i < taskItems.length - 1; ++i) {
            const task = taskItems[i];

            if (!task.model) continue;
            if (!task.model.IsLauncher && !task.model.IsStartup) {
                tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(task.index),
                    backend.globalRect(task), task);
            }
        }
    }

    readonly property TaskManager.TasksModel tasksModel: TaskManager.TasksModel {
        id: tasksModel

        readonly property int logicalLauncherCount: {
            if (Plasmoid.configuration.separateLaunchers) {
                return launcherCount;
            }

            let startupsWithLaunchers = 0;

            for (let i = 0; i < taskRepeater.count; ++i) {
                const item = taskRepeater.itemAt(i) as Task;

                // During destruction required properties such as item.model can go null for a while,
                // so in paths that can trigger on those moments, they need to be guarded
                if (item?.model?.IsStartup && item.model.HasLauncher) {
                    ++startupsWithLaunchers;
                }
            }

            return launcherCount + startupsWithLaunchers;
        }

        virtualDesktop: virtualDesktopInfo.currentDesktop
        screenGeometry: Plasmoid.containment.screenGeometry
        activity: activityInfo.currentActivity

        filterByVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByScreen: Plasmoid.configuration.showOnlyCurrentScreen
        filterByActivity: Plasmoid.configuration.showOnlyCurrentActivity
        filterNotMinimized: Plasmoid.configuration.showOnlyMinimized

        hideActivatedLaunchers: tasks.iconsOnly || Plasmoid.configuration.hideLauncherOnStart
        sortMode: sortModeEnumValue(Plasmoid.configuration.sortingStrategy)
        launchInPlace: tasks.iconsOnly && Plasmoid.configuration.sortingStrategy === 1
        separateLaunchers: {
            if (!tasks.iconsOnly && !Plasmoid.configuration.separateLaunchers
                && Plasmoid.configuration.sortingStrategy === 1) {
                return false;
            }

            return true;
        }

        groupMode: groupModeEnumValue(Plasmoid.configuration.groupingStrategy)
        groupInline: !Plasmoid.configuration.groupPopups && !tasks.iconsOnly
        groupingWindowTasksThreshold: (Plasmoid.configuration.onlyGroupWhenFull && !tasks.iconsOnly
            ? TaskManagerApplet.LayoutMetrics.optimumCapacity(tasks.width, tasks.height) + 1 : -1)

        onLauncherListChanged: {
            Plasmoid.configuration.launchers = launcherList;
        }

        onGroupingAppIdBlacklistChanged: {
            Plasmoid.configuration.groupingAppIdBlacklist = groupingAppIdBlacklist;
        }

        onGroupingLauncherUrlBlacklistChanged: {
            Plasmoid.configuration.groupingLauncherUrlBlacklist = groupingLauncherUrlBlacklist;
        }

        function sortModeEnumValue(index: int): /*TaskManager.TasksModel.SortMode*/ int {
            switch (index) {
            case 0:
                return TaskManager.TasksModel.SortDisabled;
            case 1:
                return TaskManager.TasksModel.SortManual;
            case 2:
                return TaskManager.TasksModel.SortAlpha;
            case 3:
                return TaskManager.TasksModel.SortVirtualDesktop;
            case 4:
                return TaskManager.TasksModel.SortActivity;
            // 5 is SortLastActivated, skipped
            case 6:
                return TaskManager.TasksModel.SortWindowPositionHorizontal;
            default:
                return TaskManager.TasksModel.SortDisabled;
            }
        }

        function groupModeEnumValue(index: int): /*TaskManager.TasksModel.GroupMode*/ int {
            switch (index) {
            case 0:
                return TaskManager.TasksModel.GroupDisabled;
            case 1:
                return TaskManager.TasksModel.GroupApplications;
            }
        }

        Component.onCompleted: {
            launcherList = Plasmoid.configuration.launchers;
            groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
            groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;

            // Only hook up view only after the above churn is done.
            taskRepeater.model = tasksModel;
        }
    }

    readonly property TaskManagerApplet.Backend backend: TaskManagerApplet.Backend {
        id: backend

        onAddLauncher: url => {
            tasks.addLauncher(url);
        }
    }

    DBus.DBusServiceWatcher {
        id: effectWatcher
        busType: DBus.BusType.Session
        watchedService: "org.kde.KWin.Effect.WindowView1"
    }

    readonly property Component taskInitComponent: Component {
        Timer {
            interval: 200
            running: true

            onTriggered: {
                const task = parent as Task;
                if (task) {
                    tasks.tasksModel.requestPublishDelegateGeometry(task.modelIndex(), tasks.backend.globalRect(task), task);
                }
                destroy();
            }
        }
    }

    Connections {
        target: Plasmoid

        function onLocationChanged(): void {
            if (TaskManagerApplet.TaskTools.taskManagerInstanceCount >= 2) {
                return;
            }
            // This is on a timer because the panel may not have
            // settled into position yet when the location prop-
            // erty updates.
            iconGeometryTimer.start();
        }
    }

    Connections {
        target: Plasmoid.containment

        function onScreenGeometryChanged(): void {
            iconGeometryTimer.start();
        }
    }

    Mpris.Mpris2Model {
        id: mpris2Source
    }

    Item {
        anchors.fill: parent

        TaskManager.VirtualDesktopInfo {
            id: virtualDesktopInfo
        }

        TaskManager.ActivityInfo {
            id: activityInfo
            readonly property string nullUuid: "00000000-0000-0000-0000-000000000000"
        }

        Loader {
            id: pulseAudio
            sourceComponent: tasks.pulseAudioComponent
            active: tasks.pulseAudioComponent.status === Component.Ready
        }

        Timer {
            id: iconGeometryTimer

            interval: 500
            repeat: false

            onTriggered: {
                tasks.publishIconGeometries(taskList.children, tasks);
            }
        }

        Binding {
            target: Plasmoid
            property: "status"
            value: (tasksModel.anyTaskDemandsAttention && Plasmoid.configuration.unhideOnAttention
                ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.PassiveStatus)
            restoreMode: Binding.RestoreBinding
        }

        Connections {
            target: Plasmoid.configuration

            function onLaunchersChanged(): void {
                tasksModel.launcherList = Plasmoid.configuration.launchers
            }
            function onGroupingAppIdBlacklistChanged(): void {
                tasksModel.groupingAppIdBlacklist = Plasmoid.configuration.groupingAppIdBlacklist;
            }
            function onGroupingLauncherUrlBlacklistChanged(): void {
                tasksModel.groupingLauncherUrlBlacklist = Plasmoid.configuration.groupingLauncherUrlBlacklist;
            }
        }

        Connections {
            target: tasksModel

            function onRowsInserted(): void {
                enforceContiguityTimer.restart();
            }
            function onRowsRemoved(): void {
                staleCleanupTimer.restart();
                enforceContiguityTimer.restart();
            }
        }

        Component {
            id: busyIndicator
            PlasmaComponents3.BusyIndicator {}
        }

        // Save drag data
        Item {
            id: dragHelper

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
            Drag.onDragFinished: dropAction => {
                tasks.dragSource = null;
            }
        }

        KSvg.FrameSvgItem {
            id: taskFrame

            visible: false

            imagePath: "widgets/tasks"
            prefix: TaskManagerApplet.TaskTools.taskPrefix("normal", Plasmoid.location)
        }

        MouseHandler {
            id: mouseHandler

            anchors.fill: parent

            target: taskList

            onUrlsDropped: urls => {
                // If all dropped URLs point to application desktop files, we'll add a launcher for each of them.
                const createLaunchers = urls.every(item => tasks.backend.isApplication(item));

                if (createLaunchers) {
                    urls.forEach(item => addLauncher(item));
                    return;
                }

                if (!hoveredItem) {
                    return;
                }

                // Otherwise we'll just start a new instance of the application with the URLs as argument,
                // as you probably don't expect some of your files to open in the app and others to spawn launchers.
                tasksModel.requestOpenUrls((hoveredItem as Task).modelIndex(), urls);
            }
        }

        ToolTipDelegate {
            id: openWindowToolTipDelegate
            visible: false
        }

        ToolTipDelegate {
            id: pinnedAppToolTipDelegate
            visible: false
        }

        TriangleMouseFilter {
            id: tmf
            filterTimeOut: 300
            active: tasks.toolTipAreaItem && tasks.toolTipAreaItem.toolTipOpen
            blockFirstEnter: false

            edge: {
                switch (Plasmoid.location) {
                case PlasmaCore.Types.BottomEdge:
                    return Qt.TopEdge;
                case PlasmaCore.Types.TopEdge:
                    return Qt.BottomEdge;
                case PlasmaCore.Types.LeftEdge:
                    return Qt.RightEdge;
                case PlasmaCore.Types.RightEdge:
                    return Qt.LeftEdge;
                default:
                    return Qt.TopEdge;
                }
            }

            LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Application.layoutDirection, tasks.vertical)
            anchors {
                left: parent.left
                top: parent.top
            }

            height: taskList.height
            width: taskList.width

            TaskList {
                id: taskList

                LayoutMirroring.enabled: tasks.shouldBeMirrored(Plasmoid.configuration.reverseMode, Application.layoutDirection, tasks.vertical)
                anchors {
                    left: parent.left
                    top: parent.top
                }

                count: tasksModel.count
                extraRows: tasks.vertical && stripeCount === 1 ? tasks.activeHeaderCount : 0

                readonly property int totalItemCount: taskRepeater.count + extraRows
                readonly property real widthOccupation: totalItemCount / columns
                readonly property real heightOccupation: totalItemCount / rows

                Layout.maximumWidth: {
                    const totalMaxWidth = children.reduce((accumulator, child) => {
                            if (!child.visible || !isFinite(child.Layout.maximumWidth)) {
                                return accumulator;
                            }
                            return accumulator + child.Layout.maximumWidth
                        }, 0);
                    return Math.round(totalMaxWidth / widthOccupation);
                }
                Layout.maximumHeight: {
                    const totalMaxHeight = children.reduce((accumulator, child) => {
                            if (!child.visible || !isFinite(child.Layout.maximumHeight)) {
                                return accumulator;
                            }
                            return accumulator + child.Layout.maximumHeight
                        }, 0);
                    return Math.round(totalMaxHeight / heightOccupation);
                }
                width: {
                    if (tasks.shouldShrinkToZero) {
                        return 0;
                    }
                    if (tasks.vertical) {
                        return tasks.width * Math.min(1, widthOccupation);
                    } else {
                        return Math.min(tasks.width, Layout.maximumWidth);
                    }
                }
                height: {
                    if (tasks.shouldShrinkToZero) {
                        return 0;
                    }
                    if (tasks.vertical) {
                        return Math.min(tasks.height, Layout.maximumHeight);
                    } else {
                        return tasks.height * Math.min(1, heightOccupation);
                    }
                }

                flow: {
                    if (tasks.vertical) {
                        return Plasmoid.configuration.forceStripes ? Grid.LeftToRight : Grid.TopToBottom
                    }
                    return Plasmoid.configuration.forceStripes ? Grid.TopToBottom : Grid.LeftToRight
                }

                onAnimatingChanged: {
                    if (!animating) {
                        tasks.publishIconGeometries(children, tasks);
                    }
                }

                Repeater {
                    id: taskRepeater
                    onCountChanged: tasks._recomputeRowLayout()

                    delegate: Task {
                        tasksRoot: tasks
                    }
                }

                Repeater {
                    id: headerRepeater
                    model: 8

                    delegate: GroupHeader {
                        tasksRoot: tasks
                    }
                }
            }
        }
    }

    readonly property Component groupDialogComponent: Qt.createComponent("GroupDialog.qml")
    property GroupDialog groupDialog

    readonly property bool supportsLaunchers: true

    function hasLauncher(url: url): bool {
        return tasksModel.launcherPosition(url) !== -1;
    }

    function addLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable) {
            tasksModel.requestAddLauncher(url);
        }
    }

    function removeLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable) {
            tasksModel.requestRemoveLauncher(url);
        }
    }

    // This is called by plasmashell in response to a Meta+number shortcut.
    // TODO: Change type to int
    function activateTaskAtIndex(index: var): void {
        if (typeof index !== "number") {
            return;
        }

        const task = taskRepeater.itemAt(index) as Task;
        if (task) {
            TaskManagerApplet.TaskTools.activateTask(task.modelIndex(), task.model, null, task, Plasmoid, this, effectWatcher.registered);
        }
    }

    function createContextMenu(rootTask, modelIndex, args = {}) {
        const initialArgs = Object.assign(args, {
            visualParent: rootTask,
            modelIndex,
            mpris2Source,
            backend,
        });
        return contextMenuComponent.createObject(rootTask, initialArgs);
    }

    function shouldBeMirrored(reverseMode, layoutDirection, vertical): bool {
        // LayoutMirroring is only horizontal
        if (vertical) {
            return layoutDirection === Qt.RightToLeft;
        }

        if (layoutDirection === Qt.LeftToRight) {
            return reverseMode;
        }
        return !reverseMode;
    }

    Component.onCompleted: {
        TaskManagerApplet.TaskTools.taskManagerInstanceCount += 1;
        requestLayout.connect(iconGeometryTimer.restart);
        _parseCustomNames();
        _recomputeRowLayout();
    }

    Component.onDestruction: {
        TaskManagerApplet.TaskTools.taskManagerInstanceCount -= 1;
    }
}
