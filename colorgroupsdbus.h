/*
    SPDX-FileCopyrightText: 2026 Ben Rog-Wilhelm

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QDBusArgument>
#include <QDBusContext>
#include <QJSValue>
#include <QList>
#include <QObject>
#include <QQmlParserStatus>
#include <qqmlregistration.h>

#include <optional>

struct ColorGroupsDBusWindow {
    QString id;
    QString title;
    int color = 0;
};

QDBusArgument &operator<<(QDBusArgument &argument, const ColorGroupsDBusWindow &window);
const QDBusArgument &operator>>(const QDBusArgument &argument, ColorGroupsDBusWindow &window);

class ColorGroupsDBus : public QObject, public QQmlParserStatus, protected QDBusContext
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    Q_CLASSINFO("D-Bus Interface", "net.pavlovian.groupedtaskmanager.ColorGroups")
    QML_ELEMENT

    // QML functions the bus methods forward to. `this` inside them is not the object that declares them, so they must reach the applet through ids.
    Q_PROPERTY(QJSValue windowLister READ windowLister WRITE setWindowLister)
    Q_PROPERTY(QJSValue windowAssigner READ windowAssigner WRITE setWindowAssigner)

public:
    explicit ColorGroupsDBus(QObject *parent = nullptr);
    ~ColorGroupsDBus() override;

    QJSValue windowLister() const;
    void setWindowLister(const QJSValue &lister);
    QJSValue windowAssigner() const;
    void setWindowAssigner(const QJSValue &assigner);

    void classBegin() override;
    void componentComplete() override;

public Q_SLOTS:
    Q_SCRIPTABLE QList<ColorGroupsDBusWindow> WindowList();
    Q_SCRIPTABLE int WindowAssign(const QString &windowId, int colorIndex, const QString &groupName);

private:
    std::optional<QJSValue> call(QJSValue &callback, const char *name, const QJSValueList &args);
    void fail(const QString &error, const QString &message);

    QJSValue m_windowLister;
    QJSValue m_windowAssigner;
    bool m_owner = false;
};
