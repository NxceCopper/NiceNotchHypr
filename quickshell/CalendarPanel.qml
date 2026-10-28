import QtQuick
import Quickshell

// ── Calendar panel — two views, per the reference walkthrough:
//      week  — the island clock over a 7-day strip around the selected
//              day; the selected day shows its name above the number
//      month — the full month grid behind a ‹ month › header
//    Clicking the strip switches to the month view; the pill itself
//    morphs because shell.qml sizes it from `view`.
Item {
    id: calPanel

    property string view: "week"          // "week" | "month"
    property var selected: new Date()
    property int displayMonth: selected.getMonth()
    property int displayYear: selected.getFullYear()

    readonly property color todayColor: "#e5484d"

    property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    // Sunday-first, matching the reference
    property var dayInitials: ["S", "M", "T", "W", "T", "F", "S"]
    property var dayNames: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    // Month-grid header — three-letter weekday names
    property var monthDayHeads: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function getDaysInMonth(m, y) { return new Date(y, m + 1, 0).getDate() }
    function firstDayIndex(m, y) { return new Date(y, m, 1).getDay() }   // Sun = 0
    function sameDay(a, b) {
        return a.getDate() === b.getDate() && a.getMonth() === b.getMonth()
            && a.getFullYear() === b.getFullYear()
    }
    function isToday(d) { return sameDay(d, new Date()) }

    function openMonth() {
        displayMonth = selected.getMonth()
        displayYear = selected.getFullYear()
        // Reset the slide carousel so a stale outgoing month never shows
        gridPrev.visible = false
        gridCur.x = 0
        view = "month"
    }
    function backToWeek() {
        selected = new Date()
        view = "week"
    }

    // A fresh open always starts on the week strip
    onVisibleChanged: {
        if (!visible) {
            view = "week"
            selected = new Date()
        }
    }

    // ── Week view: clock + 7-day strip ────────────────────────────────────
    Item {
        id: weekView
        anchors.fill: parent
        visible: calPanel.view === "week"
        opacity: calPanel.view === "week" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // Bigger rolling clock — digits tumble over on the minute change.
        RollingClock {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 9
        }

        Row {
            id: strip
            anchors.horizontalCenter: parent.horizontalCenter
            y: 43

            Repeater {
                model: 7

                delegate: Item {
                    required property int index

                    width: 27
                    height: 44

                    property var date: {
                        var d = new Date(calPanel.selected.getTime())
                        d.setDate(d.getDate() + index - 3)
                        return d
                    }
                    readonly property bool sel: calPanel.sameDay(date, calPanel.selected)
                    readonly property bool today: calPanel.isToday(date)
                    // Weekend columns (Sat/Sun) get the red highlight; today
                    // is exempt and keeps the accent.
                    readonly property bool weekend: date.getDay() === 0 || date.getDay() === 6
                    readonly property bool edge: index === 0 || index === 6

                    // Soft pill behind the selected day
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.06)
                        visible: sel
                    }

                    // Weekday — a single letter, the full name over the
                    // selected day; red on weekends, accent on today
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 3
                        text: sel ? calPanel.dayNames[date.getDay()]
                                  : calPanel.dayInitials[date.getDay()]
                        color: sel ? SettingsService.textPrimary
                                   : (today ? SettingsService.accentColor
                                        : (weekend ? calPanel.todayColor : SettingsService.textMuted))
                        font {
                            pixelSize: sel ? 9 : 8
                            weight: Font.Bold
                            family: "SF Pro Text"
                        }
                        opacity: edge ? 0.25 : 1
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 19
                        text: date.getDate()
                        color: sel ? SettingsService.accentColor
                                   : (today ? SettingsService.accentColor
                                        : (weekend ? calPanel.todayColor : SettingsService.textPrimary))
                        font {
                            pixelSize: 14
                            weight: (sel || today || weekend) ? Font.Bold : Font.Medium
                            family: "SF Pro Text"
                        }
                        opacity: edge ? 0.22 : 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            calPanel.selected = date
                            calPanel.openMonth()
                        }
                    }
                }
            }
        }
    }

    // ── Month view: ‹ month › header + 6 × 7 grid ─────────────────────────
    Item {
        id: monthView
        anchors.fill: parent
        visible: calPanel.view === "month"
        opacity: calPanel.view === "month" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // Prev / next month — small rounded buttons at the corners
        component NavBtn: Rectangle {
            property var action: function () {}
            width: 26
            height: 26
            radius: 8
            color: navHover.containsMouse ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.055)
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: parent.arrow
                color: SettingsService.textPrimary
                font { pixelSize: 12; family: "SF Pro Text" }
            }
            property string arrow: "←"
            MouseArea {
                id: navHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.action()
            }
        }

        NavBtn {
            x: 16
            y: 16
            arrow: "←"
            action: function () { monthView.stepMonth(-1) }
        }

        // Month title — click to fold back to the week strip
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 21
            text: calPanel.monthNames[calPanel.displayMonth] + " " + calPanel.displayYear
            color: SettingsService.textPrimary
            font {
                pixelSize: 13
                weight: Font.Bold
                family: "SF Pro Text"
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: calPanel.backToWeek()
            }
        }

        NavBtn {
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 16
            arrow: "→"
            action: function () { monthView.stepMonth(1) }
        }

        // Weekday letters
        Row {
            id: weekdayRow
            x: 14
            y: 56
            width: parent.width - 28

            Repeater {
                model: calPanel.monthDayHeads
                delegate: Item {
                    required property string modelData
                    width: weekdayRow.width / 7
                    height: 14

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: SettingsService.textMuted
                        font {
                            pixelSize: 10
                            weight: Font.DemiBold
                            family: "SF Pro Text"
                        }
                    }
                }
            }
        }

        // ── 6 × 7 date grid, parameterised so a second copy can linger
        //    on screen while the months slide past each other ──
        component MonthGrid: Item {
            id: mgrid
            property int month
            property int year

            readonly property int daysInMonth: calPanel.getDaysInMonth(month, year)
            readonly property int firstDay: calPanel.firstDayIndex(month, year)
            readonly property int prevMonthDays: calPanel.getDaysInMonth(
                month === 0 ? 11 : month - 1,
                month === 0 ? year - 1 : year)
            readonly property real cellW: width / 7
            readonly property real cellH: height / 6

            Repeater {
                model: 42

                delegate: Item {
                    required property int index

                    x: (index % 7) * mgrid.cellW
                    y: Math.floor(index / 7) * mgrid.cellH
                    width: mgrid.cellW
                    height: mgrid.cellH

                    readonly property int dayIndex: index - mgrid.firstDay + 1
                    readonly property bool inMonth: dayIndex >= 1 && dayIndex <= mgrid.daysInMonth
                    readonly property int displayDay: {
                        if (dayIndex < 1) return mgrid.prevMonthDays + dayIndex
                        if (dayIndex > mgrid.daysInMonth) return dayIndex - mgrid.daysInMonth
                        return dayIndex
                    }
                    readonly property var date: new Date(mgrid.year, mgrid.month, displayDay)
                    readonly property bool sel: inMonth && calPanel.sameDay(date, calPanel.selected)
                    readonly property bool today: inMonth && calPanel.isToday(date)

                    // Accent disc behind the selected date
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: 14
                        color: SettingsService.accentColor
                        visible: sel

                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    // Hover disc for ordinary in-month days
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.06)
                        visible: !sel && !today && cellHover.containsMouse && inMonth
                    }

                    Text {
                        anchors.centerIn: parent
                        text: displayDay
                        color: {
                            if (sel) return "#0d0d0d"
                            if (today) return calPanel.todayColor
                            if (!inMonth) return SettingsService.textMuted
                            return SettingsService.textPrimary
                        }
                        opacity: inMonth ? 1 : 0.5
                        font {
                            pixelSize: 12
                            weight: (sel || today) ? Font.Bold : Font.Medium
                            family: "SF Pro Text"
                        }
                    }

                    MouseArea {
                        id: cellHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (inMonth) calPanel.selected = date
                    }
                }
            }
        }

        Item {
            id: gridArea
            x: 14
            y: 80
            width: parent.width - 28
            height: parent.height - 16 - y
            clip: true

            // The resting grid — rebinds to the new month the moment a
            // slide starts, then travels in from the side.
            MonthGrid {
                id: gridCur
                width: gridArea.width
                height: gridArea.height
                month: calPanel.displayMonth
                year: calPanel.displayYear
            }

            // Frozen copy of the month being left; parked on top for the
            // slide, then hidden again.
            MonthGrid {
                id: gridPrev
                width: gridArea.width
                height: gridArea.height
                visible: false
            }
        }

        // ── Month slide ──
        NumberAnimation {
            id: slideCur
            target: gridCur
            property: "x"
            duration: 270
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: slidePrev
            target: gridPrev
            property: "x"
            duration: 270
            easing.type: Easing.OutCubic
            onFinished: gridPrev.visible = false
        }

        function stepMonth(dir) {
            // Freeze the month we're leaving into the outgoing layer
            gridPrev.month = gridCur.month
            gridPrev.year = gridCur.year
            gridPrev.x = 0
            gridPrev.visible = true

            // Advance the source of truth (the title reads from it)
            if (dir > 0) {
                if (calPanel.displayMonth === 11) {
                    calPanel.displayMonth = 0
                    calPanel.displayYear++
                } else {
                    calPanel.displayMonth++
                }
            } else {
                if (calPanel.displayMonth === 0) {
                    calPanel.displayMonth = 11
                    calPanel.displayYear--
                } else {
                    calPanel.displayMonth--
                }
            }

            // New month slides in from the side it comes from; the old
            // one slides fully off the opposite side, lock-step — the two
            // grids stay edge to edge like pages of one carousel.
            gridCur.x = dir > 0 ? gridArea.width : -gridArea.width
            slideCur.to = 0
            slideCur.start()
            slidePrev.to = dir > 0 ? -gridArea.width : gridArea.width
            slidePrev.start()
        }
    }
}
