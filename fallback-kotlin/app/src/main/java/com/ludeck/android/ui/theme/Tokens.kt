package com.ludeck.android.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * NO NEW VALUES.
 *
 * If you need a value that is not here, change THIS FILE and say why in the
 * commit. Do not add a one-off colour, size or duration at a call site.
 *
 * This is the only file in the app permitted to contain a colour literal.
 * scripts\check.ps1 fails the build on a Color(0x...) or a #hex anywhere else.
 *
 * The reason for the cap: the generated look comes from ADDING decoration to
 * solve a problem. A capped palette leaves nowhere to add it.
 */
object Tokens {

    /** Six colours. Not seven. */
    object Palette {
        val bg = Color(0xFF0E0F11)
        val surface = Color(0xFF181A1D)
        val text = Color(0xFFF2F3F5)
        val textDim = Color(0xFF8B9099)
        val accent = Color(0xFFE8B84B)
        val danger = Color(0xFFD4553F)
    }

    /** Four type sizes. A fifth means the hierarchy is unclear, not that a size is missing. */
    object Type {
        val display = 28.sp
        val title = 20.sp
        val body = 15.sp
        val caption = 13.sp
    }

    /** One spacing scale. Never a bare dp at a call site. */
    object Space {
        val xxs = 4.dp
        val xs = 8.dp
        val sm = 12.dp
        val md = 16.dp
        val lg = 24.dp
        val xl = 32.dp
    }

    /** Two radii. */
    object Radius {
        val card = 10.dp
        val pill = 999.dp
    }

    /** Fixed sizes. Only add one when a layout genuinely cannot derive it. */
    object Size {
        /** Minimum cover width in the shelf grid; the column count follows from it. */
        val coverMin = 120.dp
    }

    /** One elevation rule: surfaces lift, nothing else does. */
    object Elevation {
        val surface = 2.dp
    }

    /**
     * Motion. Values are taken from Apple's Designing Fluid Interfaces, not
     * invented: response is how fast a spring reaches its target, damping is
     * how much it overshoots. 1.0 damping never overshoots and is the default,
     * because overshoot on something that merely appeared feels wrong. Bounce
     * is reserved for motion the user's own gesture put momentum into.
     *
     * Durations are for the few things that are NOT gesture-driven. Anything a
     * finger touches uses a spring, because a spring can be interrupted and a
     * duration cannot.
     */
    object Motion {
        /** Press feedback. Fires on pointer-down, so it must be near-invisible. */
        const val PRESS_MS = 100

        /** Tab change. Seen many times a day, so it stays under perception. */
        const val TAB_MS = 200

        /** Sheets. The one place a longer duration is earned. */
        const val SHEET_MS = 300

        /** Per-item delay when a list first appears. Eight items maximum. */
        const val STAGGER_MS = 30

        /** Critically damped. No overshoot. The default for everything. */
        const val DAMPING_DEFAULT = 1.0f

        /** Slight overshoot, only after a flick or a drag release. */
        const val DAMPING_MOMENTUM = 0.8f

        /** Apple's scroll deceleration constant, used to project where a flick lands. */
        const val DECELERATION = 0.998f

        /** Fraction of a card's width a swipe must project past to commit. */
        const val DISMISS_FRACTION = 0.4f

        /** How far a press scales down. Deliberately barely visible. */
        const val PRESS_SCALE = 0.97f
    }
}
