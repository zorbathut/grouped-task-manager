/*
    SPDX-FileCopyrightText: 2026 Ben Rog-Wilhelm

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: header

    required property int index
    required property /*main.qml*/ Item tasksRoot

    readonly property int colorIndex: index + 1
    readonly property int headerRow: {
        let hr = header.tasksRoot._rowLayout.headerRows;
        return (hr && hr[header.colorIndex] !== undefined) ? hr[header.colorIndex] : -1;
    }

    visible: headerRow >= 0

    // Reverse-mode counter-rotation to match Task.qml
    rotation: Plasmoid.configuration.reverseMode && Plasmoid.formFactor === PlasmaCore.Types.Vertical ? 180 : 0

    Layout.row: visible ? headerRow : -1
    Layout.column: visible ? 0 : -1
    Layout.fillWidth: true
    Layout.fillHeight: false
    Layout.preferredHeight: header.tasksRoot.groupHeaderHeight
    Layout.maximumHeight: header.tasksRoot.groupHeaderHeight
    Layout.minimumHeight: visible ? header.tasksRoot.groupHeaderHeight : 0

    implicitHeight: header.tasksRoot.groupHeaderHeight
    implicitWidth: parent ? parent.width : 0

    Rectangle {
        anchors.fill: parent
        color: header.colorIndex >= 1 && header.colorIndex <= header.tasksRoot.colorGroupColors.length
            ? header.tasksRoot.colorGroupColors[header.colorIndex - 1]
            : "transparent"
        opacity: 0.15
        radius: 2
    }

    Text {
        id: headerLabel
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        text: {
            void header.tasksRoot._customNameMap;
            return header.tasksRoot.getColorGroupName(header.colorIndex);
        }
        color: Kirigami.Theme.textColor
        opacity: 0.7
        font.pixelSize: parent.height * 0.7
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter

        MouseArea {
            anchors.fill: parent
            onClicked: {
                editPopup.open();
            }
        }
    }

    PlasmaCore.PopupPlasmaWindow {
        id: editPopup

        visualParent: header
        popupDirection: switch (Plasmoid.location) {
            case PlasmaCore.Types.TopEdge:
                return Qt.BottomEdge
            case PlasmaCore.Types.LeftEdge:
                return Qt.RightEdge
            case PlasmaCore.Types.RightEdge:
                return Qt.LeftEdge
            default:
                return Qt.TopEdge
        }

        width: editField.implicitWidth + Kirigami.Units.largeSpacing * 2
        height: editField.implicitHeight + Kirigami.Units.largeSpacing * 2

        property bool cancelled: false

        // Not onActiveChanged: Qt reports a popup as active while focus sits on any other window transient for the same panel (another header's popup, a context menu), so it would never see its own deactivation and could be stranded behind app windows.
        hideOnWindowDeactivate: true

        onVisibleChanged: {
            if (!visible && !cancelled) {
                header.tasksRoot.setColorGroupName(header.colorIndex, editField.text);
            }
        }

        function open() {
            if (!visible) {
                cancelled = false;
                editField.text = headerLabel.text;
                visible = true;
                editField.selectAll();
            }
            // An already-visible popup isn't re-mapped, so re-activate (and thereby raise) it explicitly.
            requestActivate();
            editField.forceActiveFocus();
        }

        PlasmaComponents3.TextField {
            id: editField
            anchors.centerIn: parent
            implicitWidth: Math.max(Kirigami.Units.gridUnit * 10, header.width)

            onAccepted: editPopup.visible = false

            Keys.onEscapePressed: {
                editPopup.cancelled = true;
                editPopup.visible = false;
            }
        }
    }
}
