package com.ludeck.android.ui.shelf

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.ludeck.android.ui.theme.LudeckEasing
import com.ludeck.android.ui.theme.Tokens
import com.ludeck.android.ui.theme.pressable

/**
 * The only button shape in the app.
 *
 * It is a plain Text on a shaped background rather than a Material Button
 * because Material's button carries its own ripple, elevation and padding
 * scale, and three competing opinions about a corner radius is how a design
 * system dies.
 */
@Composable
fun Pill(
    text: String,
    primary: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = if (primary) Tokens.Palette.bg else Tokens.Palette.textDim,
        modifier = modifier
            .clip(RoundedCornerShape(Tokens.Radius.pill))
            .background(if (primary) Tokens.Palette.accent else Tokens.Palette.bg)
            .then(
                if (primary) {
                    Modifier
                } else {
                    Modifier.border(
                        width = 1.dp,
                        color = Tokens.Palette.surface,
                        shape = RoundedCornerShape(Tokens.Radius.pill),
                    )
                },
            )
            .pressable(onClick = onClick)
            .padding(horizontal = Tokens.Space.md, vertical = Tokens.Space.xs),
    )
}

/**
 * A filter chip. Selection is a colour change only: it is touched many times a
 * day, so it sits in the near-imperceptible tier and gets no movement at all.
 */
@Composable
fun FilterChip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val background by animateColorAsState(
        targetValue = if (selected) Tokens.Palette.accent else Tokens.Palette.surface,
        animationSpec = tween(Tokens.Motion.TAB_MS, easing = LudeckEasing.out),
        label = "chipBackground",
    )
    val foreground by animateColorAsState(
        targetValue = if (selected) Tokens.Palette.bg else Tokens.Palette.textDim,
        animationSpec = tween(Tokens.Motion.TAB_MS, easing = LudeckEasing.out),
        label = "chipForeground",
    )

    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = foreground,
        modifier = Modifier
            .clip(RoundedCornerShape(Tokens.Radius.pill))
            .background(background)
            .pressable(onClick = onClick)
            .padding(horizontal = Tokens.Space.sm, vertical = Tokens.Space.xxs),
    )
}
