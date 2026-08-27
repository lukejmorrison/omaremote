import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool crossed: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Screen {
    x: 0
    y: 0
    w: root.width * 0.68
    h: root.height * 0.58
    opacity: 0.45
  }
  Screen {
    x: root.width * 0.28
    y: root.height * 0.32
    w: root.width * 0.68
    h: root.height * 0.58
    opacity: 1.0
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.18
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  component Screen: Rectangle {
    property real w: 0
    property real h: 0
    width: w
    height: h
    radius: Math.max(1.5, root.iconSize * 0.08)
    color: "transparent"
    border.width: Math.max(1.2, root.iconSize * 0.08)
    border.color: root.color
  }
}
