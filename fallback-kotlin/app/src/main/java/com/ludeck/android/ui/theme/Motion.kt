package com.ludeck.android.ui.theme

import android.provider.Settings
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.scale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext

/**
 * The motion layer. Every animation in the app resolves through here, for the
 * same reason every colour resolves through Tokens: a one-off spring at a call
 * site is how an interface stops feeling like one thing.
 */

/** The strong ease-out. Platform easings are too weak to read as deliberate. */
object LudeckEasing {
    /** Entering, exiting, and press feedback. Never ease-in on UI. */
    val out: Easing = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)

    /** Something already on screen moving to a new place. */
    val inOut: Easing = CubicBezierEasing(0.77f, 0f, 0.175f, 1f)
}

object LudeckSpring {
    /**
     * The default. Critically damped, so it settles without overshooting.
     * Use for anything that appears, moves, or snaps back.
     */
    fun <T> standard(): AnimationSpec<T> = spring(
        dampingRatio = Tokens.Motion.DAMPING_DEFAULT,
        stiffness = Spring.StiffnessMediumLow,
    )

    /**
     * Slight overshoot. Only legitimate when the user's own gesture supplied
     * the momentum: a flick, a throw, a drag release. Overshoot on something
     * that merely faded in is decoration.
     */
    fun <T> momentum(): AnimationSpec<T> = spring(
        dampingRatio = Tokens.Motion.DAMPING_MOMENTUM,
        stiffness = Spring.StiffnessMediumLow,
    )
}

/**
 * Android's equivalent of prefers-reduced-motion. When the user has turned
 * animations off in Developer options or Accessibility, the scale reads 0.
 *
 * Reduced motion means gentler, not none: callers keep opacity and colour
 * changes that aid comprehension and drop movement.
 */
@Composable
fun rememberReducedMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        val scale = Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        )
        scale == 0f
    }
}

/**
 * Apple's momentum projection, from the Designing Fluid Interfaces sample code.
 * Answers "where would this come to rest if released now", so a flick lands
 * where the gesture was going rather than where the finger happened to stop.
 *
 * Note this is the exponential-decay form, NOT the textbook v squared over
 * twice the deceleration. The textbook version is not what feels right.
 */
fun projectMomentum(velocityPxPerSecond: Float): Float {
    val d = Tokens.Motion.DECELERATION
    return (velocityPxPerSecond / 1000f) * d / (1f - d)
}

/**
 * Press feedback plus tap and hold, in one modifier.
 *
 * The important detail is that the scale starts on pointer DOWN, not on
 * release. Waiting for the tap to complete before acknowledging it is the
 * single thing that makes an interface feel dead, and it is invisible in a
 * screenshot.
 *
 * @param onHold when non-null the element is holdable, which is how a status
 *        gets changed without a separate screen.
 */
fun Modifier.pressable(
    onClick: () -> Unit,
    onHold: (() -> Unit)? = null,
): Modifier = composed {
    var pressed by remember { mutableStateOf(false) }
    val reduce = rememberReducedMotion()

    val scale by animateFloatAsState(
        targetValue = if (pressed && !reduce) Tokens.Motion.PRESS_SCALE else 1f,
        animationSpec = tween(
            durationMillis = Tokens.Motion.PRESS_MS,
            easing = LudeckEasing.out,
        ),
        label = "pressScale",
    )

    this
        .scale(scale)
        .pointerInput(onHold == null) {
            detectTapGestures(
                onPress = {
                    pressed = true
                    // Releasing OR cancelling both clear the press. Dragging a
                    // finger off a control must undo the highlight, not leave
                    // it stuck on.
                    tryAwaitRelease()
                    pressed = false
                },
                onTap = { onClick() },
                onLongPress = if (onHold != null) {
                    { onHold() }
                } else {
                    null
                },
            )
        }
}
