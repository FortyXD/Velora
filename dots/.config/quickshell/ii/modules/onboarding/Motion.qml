pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell

/**
 * How the setup assistant moves: Material 3 Expressive curves, scaled with the shell's motion speed.
 * With motion turned down (Appearance → Motion, or the accessibility button), things fade instead of
 * travelling.
 */
Singleton {
    id: root

    property bool reduced: Appearance.animationSpeed <= 0
    function ms(duration) {
        return root.reduced ? Math.round(duration * 0.6) : Appearance.scaledDuration(duration);
    }
    // How far things travel: none with reduced motion
    function travel(distance) {
        return root.reduced ? 0 : distance;
    }

    readonly property list<real> emphasized: Appearance.animationCurves.emphasized
    readonly property list<real> decelerate: Appearance.animationCurves.emphasizedDecel
    readonly property list<real> accelerate: Appearance.animationCurves.emphasizedAccel
    readonly property list<real> spatial: Appearance.animationCurves.expressiveDefaultSpatial
    readonly property list<real> effects: Appearance.animationCurves.expressiveEffects

    readonly property int page: 520
    readonly property int stagger: 36
    readonly property int quick: 220
}
