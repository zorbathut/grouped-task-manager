/*
    SPDX-FileCopyrightText: 2026 Ben Rog-Wilhelm

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "colormanager.h"

#include <QSet>

ColorManager::ColorManager(QObject *parent)
    : QObject(parent)
{
}

QStringList ColorManager::colorAssignments() const
{
    QStringList result;
    result.reserve(m_colors.size());
    for (auto it = m_colors.constBegin(); it != m_colors.constEnd(); ++it) {
        result.append(it.key() + QLatin1Char('=') + QString::number(it.value()));
    }
    return result;
}

void ColorManager::setColorAssignments(const QStringList &assignments)
{
    QHash<QString, int> newColors;
    for (const QString &entry : assignments) {
        const int sep = entry.lastIndexOf(QLatin1Char('='));
        if (sep > 0 && sep < entry.length() - 1) {
            bool ok = false;
            const int colorIndex = entry.mid(sep + 1).toInt(&ok);
            if (ok && colorIndex >= 1 && colorIndex <= 8) {
                newColors.insert(entry.left(sep), colorIndex);
            }
        }
    }

    if (newColors != m_colors) {
        m_colors = newColors;
        Q_EMIT colorAssignmentsChanged();
    }
}

int ColorManager::getColor(const QString &windowId) const
{
    return m_colors.value(windowId, 0);
}

void ColorManager::setColor(const QString &windowId, int colorIndex)
{
    if (colorIndex < 1 || colorIndex > 8) {
        clearColor(windowId);
        return;
    }

    if (m_colors.value(windowId, 0) != colorIndex) {
        m_colors.insert(windowId, colorIndex);
        Q_EMIT windowColorChanged(windowId, colorIndex);
        Q_EMIT colorAssignmentsChanged();
    }
}

void ColorManager::clearColor(const QString &windowId)
{
    if (m_colors.remove(windowId)) {
        Q_EMIT windowColorChanged(windowId, 0);
        Q_EMIT colorAssignmentsChanged();
    }
}

void ColorManager::removeStale(const QStringList &activeWindowIds)
{
    const QSet<QString> activeSet(activeWindowIds.constBegin(), activeWindowIds.constEnd());
    bool changed = false;

    auto it = m_colors.begin();
    while (it != m_colors.end()) {
        if (!activeSet.contains(it.key())) {
            it = m_colors.erase(it);
            changed = true;
        } else {
            ++it;
        }
    }

    if (changed) {
        Q_EMIT colorAssignmentsChanged();
    }
}

#include "moc_colormanager.cpp"
