import QtQuick

// The pill's clock: the same rolling fold-over digits as the calendar's
// mini view, at the pill's 18px size. Slot widths are constant (sized
// from a hidden "0"), so the pill width never reflows on digit changes.
RollingClock {
    pixelSize: 18
}
