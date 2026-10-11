import QtQuick

// idx1 is the "leading" indicator position, idx2 is the "following" one
// The former animates faster than the latter, see the NumberAnimations below
QtObject {
    id: root
    required property int index

    property real idx1: index
    property real idx2: index
    property int idx1Duration: 100
    property int idx2Duration: 300
    // Optional bezier curves; OutSine when empty
    property list<real> idx1Curve: []
    property list<real> idx2Curve: []

    Behavior on idx1 {
        NumberAnimation {
            duration: root.idx1Duration
            easing.type: root.idx1Curve.length > 0 ? Easing.BezierSpline : Easing.OutSine
            easing.bezierCurve: root.idx1Curve
        }
    }
    Behavior on idx2 {
        NumberAnimation {
            duration: root.idx2Duration
            easing.type: root.idx2Curve.length > 0 ? Easing.BezierSpline : Easing.OutSine
            easing.bezierCurve: root.idx2Curve
        }
    }
}
