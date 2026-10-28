import Quickshell
import QtQuick

// Clock with per-digit roll-over: when the minute ticks, each changed
// digit slides up and out while the new one slides in from below —
// 12:03 -> 12:04 rolls just the last digit. Used by the calendar's mini
// (week) view at 24px and, via the NotchClock wrapper, by the idle pill
// at 18px.
Item {
    id: clockRoot
    // A touch bigger than the pill clock (18px) so the mini view reads
    // as the focal point before the full month grid.
    property int pixelSize: 24

    // Digit slots hug their glyphs; the colon is static.
    width: row.width
    height: row.height

    // Seconds precision on purpose: a Minute-precision clock can come up
    // with an invalid date and never fire again (the digits froze at
    // 00:00). With Seconds the date is valid within a tick, and since
    // timeStr only *changes* on minute boundaries the rolls stay
    // minute-precise.
    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property string timeStr: Qt.formatDateTime(clock.date, "hh:mm")
    // The clock date can be briefly invalid at engine startup (digits
    // would seed as 00:00 and, with no later change event, freeze).
    // Seeding retries until the string carries the real time; after that
    // every change is a roll.
    property bool seeded: false
    function seed() {
        if (seeded || timeStr.length !== 5 || timeStr === "00:00")
            return
        seeded = true
        h0.digit = timeStr.charAt(0)
        h1.digit = timeStr.charAt(1)
        m0.digit = timeStr.charAt(3)
        m1.digit = timeStr.charAt(4)
    }
    Timer {
        // Safety net while unseeded; stops itself once seeded.
        interval: 500
        repeat: true
        running: !clockRoot.seeded
        onTriggered: clockRoot.seed()
    }

    component RollDigit: Item {
        id: slot
        property string digit: "0"
        // The glyph currently owning the slot (resident until its first
        // roll, then the newest ghost).
        property Text cur: live
        // Glyphs that have slid out, waiting for the reaper. A ghost must
        // NEVER be reclaimed while it is still cur — the next roll would
        // hit a dead reference (the old self-destruct timer did exactly
        // that and left the slot empty).
        property var retiring: []
        // Everything outside the slot box is clipped so digits slide
        // through the "folding machine" edge instead of floating over it.
        clip: true

        // Sizing reference — never animated, never destroyed.
        Text {
            id: metrics
            visible: false
            text: "0"
            font {
                weight: 800
                family: "SF Pro"
                pixelSize: clockRoot.pixelSize
            }
        }
        width: metrics.width
        height: metrics.height

        // The resident digit. Slides out on the first change; every later
        // change rolls ghost copies. Deliberately NOT self-destructing on
        // creation — it joins the retiring queue when superseded.
        Text {
            id: live
            text: slot.digit
            color: SettingsService.textPrimary
            font {
                weight: 800
                family: "SF Pro"
                pixelSize: clockRoot.pixelSize
            }
        }

        Component {
            id: ghostComp
            Text {
                color: SettingsService.textPrimary
                font {
                    weight: 800
                    family: "SF Pro"
                    pixelSize: clockRoot.pixelSize
                }
            }
        }

        Component {
            id: animComp
            NumberAnimation {
                duration: 280
                easing.type: Easing.OutCubic
            }
        }

        // Reclaims retired glyphs once their slide-out has finished.
        Timer {
            id: reaper
            interval: 340
            repeat: true
            onTriggered: {
                while (slot.retiring.length) {
                    var t = slot.retiring.pop()
                    if (t)
                        t.destroy()
                }
                if (!slot.retiring.length)
                    reaper.stop()
            }
        }

        function roll(to) {
            if (to === digit)
                return
            var old = cur
            // Sever the live↔digit binding (assigning to a bound property
            // replaces the binding) so the outgoing glyph keeps ITS digit
            // while sliding out instead of morphing into the new one.
            if (old)
                old.text = old.text
            digit = to
            var fresh = ghostComp.createObject(slot, { "text": to, "y": slot.height })
            cur = fresh
            fresh.z = 2
            if (old) {
                slot.retiring.push(old)
                reaper.start()
            }
            slideTo(old, -old.height)
            slideTo(fresh, 0)
        }
        function slideTo(t, target) {
            var a = animComp.createObject(slot)
            a.target = t
            a.property = "y"
            a.from = t.y
            a.to = target
            a.start()
        }
    }

    Row {
        id: row
        RollDigit { id: h0 }
        RollDigit { id: h1 }
        Text {
            text: ":"
            color: SettingsService.textPrimary
            font {
                weight: 800
                family: "SF Pro"
                pixelSize: clockRoot.pixelSize
            }
        }
        RollDigit { id: m0 }
        RollDigit { id: m1 }
    }

    Component.onCompleted: seed()
    onTimeStrChanged: {
        if (!seeded) {
            seed()
            return
        }
        h0.roll(timeStr.charAt(0))
        h1.roll(timeStr.charAt(1))
        m0.roll(timeStr.charAt(3))
        m1.roll(timeStr.charAt(4))
    }
}
