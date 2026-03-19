/*
    SPDX-FileCopyrightText: 2026 Ben Rog-Wilhelm

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <qqmlregistration.h>

class ColorManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QStringList colorAssignments READ colorAssignments
               WRITE setColorAssignments NOTIFY colorAssignmentsChanged)

public:
    explicit ColorManager(QObject *parent = nullptr);
    ~ColorManager() override = default;

    QStringList colorAssignments() const;
    void setColorAssignments(const QStringList &assignments);

    Q_INVOKABLE int getColor(const QString &windowId) const;
    Q_INVOKABLE void setColor(const QString &windowId, int colorIndex);
    Q_INVOKABLE void clearColor(const QString &windowId);
    Q_INVOKABLE void removeStale(const QStringList &activeWindowIds);

Q_SIGNALS:
    void colorAssignmentsChanged();
    void windowColorChanged(const QString &windowId, int colorIndex);

private:
    QHash<QString, int> m_colors;
};
