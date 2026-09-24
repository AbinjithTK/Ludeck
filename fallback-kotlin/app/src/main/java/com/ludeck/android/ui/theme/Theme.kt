package com.ludeck.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight

private val LudeckColors = darkColorScheme(
    background = Tokens.Palette.bg,
    surface = Tokens.Palette.surface,
    onBackground = Tokens.Palette.text,
    onSurface = Tokens.Palette.text,
    primary = Tokens.Palette.accent,
    onPrimary = Tokens.Palette.bg,
    error = Tokens.Palette.danger,
    onSurfaceVariant = Tokens.Palette.textDim,
)

private val LudeckType = Typography(
    displaySmall = TextStyle(fontSize = Tokens.Type.display, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = Tokens.Type.title, fontWeight = FontWeight.Medium),
    bodyMedium = TextStyle(fontSize = Tokens.Type.body),
    labelSmall = TextStyle(fontSize = Tokens.Type.caption),
)

/**
 * One theme, dark only for now. A light theme is a decision, not an omission:
 * a collection of cover art reads better on a dark surface, and shipping one
 * well-tuned theme beats shipping two half-tuned ones.
 */
@Composable
fun LudeckTheme(
    @Suppress("UNUSED_PARAMETER") darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = LudeckColors,
        typography = LudeckType,
        content = content,
    )
}
