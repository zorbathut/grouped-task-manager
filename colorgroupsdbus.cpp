/*
    SPDX-FileCopyrightText: 2026 Ben Rog-Wilhelm

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "colorgroupsdbus.h"

#include "log_settings.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QJSEngine>

using namespace Qt::StringLiterals;

static constexpr QLatin1StringView s_service("net.pavlovian.groupedtaskmanager");
static constexpr QLatin1StringView s_path("/ColorGroups");
static constexpr QLatin1StringView s_errorPrefix("net.pavlovian.groupedtaskmanager.Error.");

QDBusArgument &operator<<(QDBusArgument &argument, const ColorGroupsDBusWindow &window)
{
    argument.beginStructure();
    argument << window.id << window.title << window.color;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, ColorGroupsDBusWindow &window)
{
    argument.beginStructure();
    argument >> window.id >> window.title >> window.color;
    argument.endStructure();
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const ColorGroupsDBusGroup &group)
{
    argument.beginStructure();
    argument << group.color << group.name;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, ColorGroupsDBusGroup &group)
{
    argument.beginStructure();
    argument >> group.color >> group.name;
    argument.endStructure();
    return argument;
}

ColorGroupsDBus::ColorGroupsDBus(QObject *parent)
    : QObject(parent)
{
}

ColorGroupsDBus::~ColorGroupsDBus()
{
    if (m_owner) {
        QDBusConnection::sessionBus().unregisterService(s_service);
    }
}

QJSValue ColorGroupsDBus::windowLister() const
{
    return m_windowLister;
}

void ColorGroupsDBus::setWindowLister(const QJSValue &lister)
{
    m_windowLister = lister;
}

QJSValue ColorGroupsDBus::windowAssigner() const
{
    return m_windowAssigner;
}

void ColorGroupsDBus::setWindowAssigner(const QJSValue &assigner)
{
    m_windowAssigner = assigner;
}

QJSValue ColorGroupsDBus::groupLister() const
{
    return m_groupLister;
}

void ColorGroupsDBus::setGroupLister(const QJSValue &lister)
{
    m_groupLister = lister;
}

QJSValue ColorGroupsDBus::orderLister() const
{
    return m_orderLister;
}

void ColorGroupsDBus::setOrderLister(const QJSValue &lister)
{
    m_orderLister = lister;
}

QJSValue ColorGroupsDBus::orderSetter() const
{
    return m_orderSetter;
}

void ColorGroupsDBus::setOrderSetter(const QJSValue &setter)
{
    m_orderSetter = setter;
}

void ColorGroupsDBus::classBegin()
{
}

void ColorGroupsDBus::componentComplete()
{
    qDBusRegisterMetaType<ColorGroupsDBusWindow>();
    qDBusRegisterMetaType<QList<ColorGroupsDBusWindow>>();
    qDBusRegisterMetaType<ColorGroupsDBusGroup>();
    qDBusRegisterMetaType<QList<ColorGroupsDBusGroup>>();

    auto sessionBus = QDBusConnection::sessionBus();

    // The object path is the only reliable sign that another applet instance got here first: registerService() succeeds when this connection already owns the name, and unregisterService() isn't refcounted, so an instance that lost this race must never touch the name.
    if (!sessionBus.registerObject(s_path, this, QDBusConnection::ExportScriptableSlots)) {
        qCWarning(TASKMANAGER_DEBUG) << "Failed to register" << s_path << "- another instance of the applet already provides it";
        return;
    }

    if (!sessionBus.registerService(s_service)) {
        qCWarning(TASKMANAGER_DEBUG) << "Failed to register service" << s_service;
        return;
    }
    m_owner = true;
}

QList<ColorGroupsDBusWindow> ColorGroupsDBus::WindowList()
{
    const auto result = call(m_windowLister, "windowLister", {});
    if (!result) {
        return {};
    }

    if (!result->isArray()) {
        qCWarning(TASKMANAGER_DEBUG) << "windowLister returned" << result->toString() << "instead of an array";
        fail(u"Failed"_s, u"The applet produced a malformed window list"_s);
        return {};
    }

    QList<ColorGroupsDBusWindow> windows;
    const int length = result->property(u"length"_s).toInt();
    windows.reserve(length);
    for (int i = 0; i < length; ++i) {
        const QJSValue entry = result->property(i);
        windows.append({entry.property(u"id"_s).toString(), entry.property(u"title"_s).toString(), entry.property(u"color"_s).toInt()});
    }
    return windows;
}

int ColorGroupsDBus::WindowAssign(const QString &windowId, int colorIndex, const QString &groupName)
{
    const auto result = callChecked(m_windowAssigner, "windowAssigner", {windowId, colorIndex, groupName});
    if (!result) {
        return 0;
    }
    if (!result->hasProperty(u"color"_s)) {
        qCWarning(TASKMANAGER_DEBUG) << "windowAssigner returned" << result->toString() << "with neither a color nor an error";
        fail(u"Failed"_s, u"The applet produced a malformed assignment result"_s);
        return 0;
    }
    return result->property(u"color"_s).toInt();
}

QList<ColorGroupsDBusGroup> ColorGroupsDBus::GroupList()
{
    const auto result = call(m_groupLister, "groupLister", {});
    if (!result) {
        return {};
    }

    if (!result->isArray()) {
        qCWarning(TASKMANAGER_DEBUG) << "groupLister returned" << result->toString() << "instead of an array";
        fail(u"Failed"_s, u"The applet produced a malformed group list"_s);
        return {};
    }

    QList<ColorGroupsDBusGroup> groups;
    const int length = result->property(u"length"_s).toInt();
    groups.reserve(length);
    for (int i = 0; i < length; ++i) {
        const QJSValue entry = result->property(i);
        groups.append({entry.property(u"color"_s).toInt(), entry.property(u"name"_s).toString()});
    }
    return groups;
}

QStringList ColorGroupsDBus::OrderList()
{
    const auto result = callChecked(m_orderLister, "orderLister", {});
    if (!result) {
        return {};
    }
    const QJSValue order = result->property(u"order"_s);
    if (!order.isArray()) {
        qCWarning(TASKMANAGER_DEBUG) << "orderLister returned" << result->toString() << "instead of an array";
        fail(u"Failed"_s, u"The applet produced a malformed task order"_s);
        return {};
    }

    QStringList ids;
    const int length = order.property(u"length"_s).toInt();
    ids.reserve(length);
    for (int i = 0; i < length; ++i) {
        ids.append(order.property(i).toString());
    }
    return ids;
}

void ColorGroupsDBus::OrderSet(const QStringList &windowIds)
{
    QJSEngine *engine = qjsEngine(this);
    if (!engine) {
        qCWarning(TASKMANAGER_DEBUG) << "OrderSet called on an object with no QML engine";
        fail(u"Failed"_s, u"The applet is not ready to handle this call"_s);
        return;
    }
    callChecked(m_orderSetter, "orderSetter", {engine->toScriptValue(windowIds)});
}

// Empty when the callback couldn't be run; the failure has been reported by then.
std::optional<QJSValue> ColorGroupsDBus::call(QJSValue &callback, const char *name, const QJSValueList &args)
{
    if (!callback.isCallable()) {
        qCWarning(TASKMANAGER_DEBUG) << name << "is not set to a function";
        fail(u"Failed"_s, u"The applet is not ready to handle this call"_s);
        return std::nullopt;
    }

    const QJSValue result = callback.call(args);
    if (result.isError()) {
        qCWarning(TASKMANAGER_DEBUG) << name << "threw:" << result.toString();
        fail(u"Failed"_s, result.toString());
        return std::nullopt;
    }
    return result;
}

// Like call(), but also reports a callback's {error, message} answer as a bus error.
std::optional<QJSValue> ColorGroupsDBus::callChecked(QJSValue &callback, const char *name, const QJSValueList &args)
{
    const auto result = call(callback, name, args);
    if (!result) {
        return std::nullopt;
    }
    if (result->hasProperty(u"error"_s)) {
        fail(result->property(u"error"_s).toString(), result->property(u"message"_s).toString());
        return std::nullopt;
    }
    return result;
}

void ColorGroupsDBus::fail(const QString &error, const QString &message)
{
    if (calledFromDBus()) {
        sendErrorReply(s_errorPrefix + error, message);
    }
}

#include "moc_colorgroupsdbus.cpp"
