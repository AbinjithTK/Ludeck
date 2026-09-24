package com.ludeck.android.ui.shelf

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.IntOffset
import com.ludeck.android.ui.theme.LudeckSpring
import com.ludeck.android.ui.theme.Tokens
import com.ludeck.android.ui.theme.projectMomentum
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sign
import kotlinx.coroutines.launch

/** What the app suggests playing, and why it picked it. */
data class Suggestion(
    val igdbId: Long,
    val title: String,
    val reason: String,
    val detail: String,
)

/**
 * The Tonight card. Swipe it aside to ask for a different suggestion.
 *
 * This is the only interaction in the app that needs real physics, and it gets
 * the full treatment: the card tracks the finger 1:1, the release velocity is
 * projected forward to decide whether the gesture committed, and that same
 * velocity is handed to the spring so there is no seam between dragging and
 * animating. Deciding on the PROJECTION rather than on where the finger stopped
 * is what makes a quick flick work without dragging the card the whole way.
 *
 * Under reduced motion the card does not travel; the dismissal is immediate and
 * the caller cross-fades the next suggestion instead.
 */
@Composable
fun TonightCard(
    suggestion: Suggestion,
    reduceMotion: Boolean,
    onStart: () -> Unit,
    onNotTonight: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val offsetX = remember(suggestion.igdbId) { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var widthPx by remember { mutableIntStateOf(1) }

    // Fades as it leaves, so a large surface in motion is never fully opaque.
    val travel = if (widthPx > 0) abs(offsetX.value) / widthPx else 0f
    val fade = (1f - travel * 0.9f).coerceIn(0f, 1f)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .onSizeChanged { widthPx = it.width }
            .offset { IntOffset(offsetX.value.roundToInt(), 0) }
            .alpha(fade)
            .clip(RoundedCornerShape(Tokens.Radius.card))
            .background(Tokens.Palette.surface)
            .then(
                if (reduceMotion) {
                    Modifier
                } else {
                    Modifier.draggable(
                        orientation = Orientation.Horizontal,
                        state = rememberDraggableState { delta ->
                            scope.launch { offsetX.snapTo(offsetX.value + delta) }
                        },
                        onDragStopped = { velocity ->
                            val projected = offsetX.value + projectMomentum(velocity)
                            val committed =
                                abs(projected) > widthPx * Tokens.Motion.DISMISS_FRACTION

                            if (committed) {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                // Leaves along the path the finger was taking.
                                offsetX.animateTo(
                                    targetValue = sign(projected) * widthPx * 1.1f,
                                    animationSpec = LudeckSpring.momentum(),
                                    initialVelocity = velocity,
                                )
                                onNotTonight()
                            } else {
                                // Did not commit, so it returns without overshoot.
                                offsetX.animateTo(
                                    targetValue = 0f,
                                    animationSpec = LudeckSpring.standard(),
                                    initialVelocity = velocity,
                                )
                            }
                        },
                    )
                },
            )
            .padding(Tokens.Space.md),
        verticalArrangement = Arrangement.spacedBy(Tokens.Space.xxs),
    ) {
        Text(
            text = suggestion.reason,
            style = MaterialTheme.typography.labelSmall,
            color = Tokens.Palette.textDim,
        )
        Text(
            text = suggestion.title,
            style = MaterialTheme.typography.titleMedium,
            color = Tokens.Palette.text,
        )
        Text(
            text = suggestion.detail,
            style = MaterialTheme.typography.labelSmall,
            color = Tokens.Palette.textDim,
        )

        Row(
            horizontalArrangement = Arrangement.spacedBy(Tokens.Space.xs),
            modifier = Modifier.padding(top = Tokens.Space.sm),
        ) {
            Pill(text = "Start it", primary = true, onClick = onStart)
            Pill(text = "Not tonight", primary = false, onClick = onNotTonight)
        }
    }
}
