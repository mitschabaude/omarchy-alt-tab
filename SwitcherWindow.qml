import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "SwitcherModel.js" as Model

// The switcher's panel: a row of window previews in the middle of the focused
// monitor, laid out like GNOME's window switcher. Each preview carries its
// app's icon in the corner, the selected one sits in a highlight, and the
// selected window's title shows underneath.
//
// The surface covers the monitor and takes the keyboard while the switcher is
// open, so keys pressed with Alt held don't reach the window behind it.
PanelWindow {
  id: window

  required property var switcher

  screen: switcher.screen
  visible: switcher.mapped && switcher.screen !== null
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "alt-tab"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  // GNOME's sizes: a preview box, the app icon in its corner, and the padding
  // around each item and the whole list.
  readonly property real scale: Model.fitScale(
    switcher.entries.length, itemWidth, itemHeight,
    width * 0.9 - listPadding * 2, height * 0.8 - listPadding * 2 - titleHeight)
  readonly property int previewWidth: Math.round(208 * Style.fontScale)
  readonly property int previewHeight: Math.round(144 * Style.fontScale)
  readonly property int itemPadding: Math.round(8 * Style.fontScale)
  readonly property int itemWidth: previewWidth + itemPadding * 2
  readonly property int itemHeight: previewHeight + itemPadding * 2
  readonly property int listPadding: Math.round(12 * Style.fontScale)
  readonly property int titleHeight: Math.round(Style.font.body * 2.5)

  // The pointer selects a preview only once it moves: one that happens to be
  // resting where the panel opens does not.
  property bool pointerMoved: false
  property point pointerStart: Qt.point(-1, -1)

  onVisibleChanged: {
    pointerMoved = false
    pointerStart = Qt.point(-1, -1)
    if (visible) keys.forceActiveFocus()
  }

  HoverHandler {
    onPointChanged: {
      var p = point.position
      if (window.pointerStart.x < 0) window.pointerStart = p
      else if (Math.abs(p.x - window.pointerStart.x) + Math.abs(p.y - window.pointerStart.y) > 4) window.pointerMoved = true
    }
  }

  // A click beside the panel closes the switcher without switching.
  MouseArea {
    anchors.fill: parent
    onClicked: window.switcher.cancel()
  }

  Item {
    id: keys
    focus: true

    Keys.onPressed: function(event) {
      switch (event.key) {
      case Qt.Key_Tab:
      case Qt.Key_Right:
      case Qt.Key_Down:
        window.switcher.next(); break
      case Qt.Key_Backtab:
      case Qt.Key_Left:
      case Qt.Key_Up:
        window.switcher.prev(); break
      case Qt.Key_Return:
      case Qt.Key_Enter:
      case Qt.Key_Space:
        window.switcher.commit(); break
      case Qt.Key_Escape:
        window.switcher.cancel(); break
      default:
        return
      }
      event.accepted = true
    }

    // Hyprland's release binding normally picks the window; this catches the
    // release too, in case the binding was skipped.
    Keys.onReleased: function(event) {
      if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr) {
        window.switcher.commit()
        event.accepted = true
      }
    }
  }

  Rectangle {
    id: panel

    anchors.centerIn: parent
    visible: window.switcher.shown
    width: list.width + window.listPadding * 2
    height: list.height + window.titleHeight + window.listPadding * 2
    radius: Math.round(20 * Style.fontScale)
    color: Commons.Color.menu.background
    border.width: Style.normalBorderWidth
    border.color: Commons.Color.menu.border

    // Clicks on the panel itself stay here.
    MouseArea { anchors.fill: parent }

    Flow {
      id: list

      x: window.listPadding
      y: window.listPadding
      width: Math.min(
        window.switcher.entries.length * Math.round(window.itemWidth * window.scale),
        Math.floor((window.width * 0.9 - window.listPadding * 2) / Math.round(window.itemWidth * window.scale)) * Math.round(window.itemWidth * window.scale))

      Repeater {
        model: window.switcher.entries

        delegate: Item {
          id: item

          required property var modelData
          required property int index

          readonly property bool selected: index === window.switcher.index
          readonly property var entry: DesktopEntries.heuristicLookup(modelData.appId)
          readonly property string iconName: entry && entry.icon ? entry.icon : Model.iconNameForAppId(modelData.appId)

          width: Math.round(window.itemWidth * window.scale)
          height: Math.round(window.itemHeight * window.scale)

          Rectangle {
            anchors.fill: parent
            radius: Math.round(12 * Style.fontScale * window.scale)
            color: Commons.Color.menu.selectedBackground
            border.width: item.selected ? Style.normalBorderWidth : 0
            border.color: Commons.Color.menu.selectedText
            opacity: item.selected ? 1 : 0
          }

          Item {
            id: previewBox
            anchors.fill: parent
            anchors.margins: Math.round(window.itemPadding * window.scale)

            ScreencopyView {
              id: preview
              anchors.centerIn: parent
              captureSource: item.modelData.toplevel ? item.modelData.toplevel.wayland : null
              live: false
              constraintSize: Qt.size(previewBox.width, previewBox.height)
              width: hasContent ? implicitWidth : 0
              height: hasContent ? implicitHeight : 0
            }

            // No preview yet (or none to be had): the icon, large.
            Image {
              anchors.centerIn: parent
              visible: !preview.hasContent
              width: Math.round(previewBox.height * 0.5)
              height: width
              sourceSize: Qt.size(width, height)
              source: Quickshell.iconPath(item.iconName, true)
              asynchronous: true
            }
          }

          Image {
            visible: preview.hasContent
            anchors.right: previewBox.right
            anchors.bottom: previewBox.bottom
            width: Math.round(40 * Style.fontScale * window.scale)
            height: width
            sourceSize: Qt.size(width, height)
            source: Quickshell.iconPath(item.iconName, true)
            asynchronous: true
          }

          HoverHandler {
            id: hover
          }

          readonly property bool pointed: hover.hovered && window.pointerMoved
          onPointedChanged: if (pointed) window.switcher.select(index)

          TapHandler {
            onTapped: {
              window.switcher.select(item.index)
              window.switcher.commit()
            }
          }
        }
      }
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: window.listPadding
      anchors.rightMargin: window.listPadding
      height: window.titleHeight + window.listPadding
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: window.switcher.selected && window.switcher.selected.toplevel ? String(window.switcher.selected.toplevel.title || "") : ""
      color: Commons.Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
