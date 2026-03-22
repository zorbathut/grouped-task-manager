/*
    SPDX-FileCopyrightText: 2026 Ben Rog-Wilhelm

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
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
        color: header.colorIndex >= 1 && header.colorIndex <= 8
            ? header.tasksRoot.colorGroupColors[header.colorIndex - 1]
            : "transparent"
        opacity: 0.15
        radius: 2
    }

    Text {
        id: headerLabel
        visible: !headerEditor.visible
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
                headerEditor.text = headerLabel.text;
                headerEditor.visible = true;
                headerEditor.forceActiveFocus();
                headerEditor.selectAll();
            }
        }
    }

    TextInput {
        id: headerEditor
        visible: false
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        font: headerLabel.font
        color: Kirigami.Theme.textColor
        clip: true
        selectByMouse: true
        verticalAlignment: TextInput.AlignVCenter

        onAccepted: commitEdit()
        onActiveFocusChanged: {
            if (!activeFocus && visible) commitEdit();
        }

        Keys.onEscapePressed: {
            visible = false;
        }

        function commitEdit() {
            visible = false;
            header.tasksRoot.setColorGroupName(header.colorIndex, text);
        }
    }
}
