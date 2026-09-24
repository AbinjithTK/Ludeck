package com.ludeck.android.ui.shelf

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import com.ludeck.android.data.model.Progress
import com.ludeck.android.ui.theme.Tokens
import com.ludeck.android.ui.theme.pressable

/**
 * The status picker, opened by holding a cover.
 *
 * Why a hold and not a menu button: a status change is the single most frequent
 * action in a collection app, and giving it its own screen means four taps to
 * record one fact. Holding the thing you mean is the shortest true path.
 *
 * The sheet is draggable and dismissible by the platform component, which
 * already carries velocity through a drag release, so there is nothing to
 * hand-roll here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatusSheet(
    title: String,
    current: Progress,
    onPick: (Progress) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Tokens.Palette.surface,
        contentColor = Tokens.Palette.text,
    ) {
        Column(
            modifier = Modifier.padding(
                start = Tokens.Space.md,
                end = Tokens.Space.md,
                bottom = Tokens.Space.xl,
            ),
            verticalArrangement = Arrangement.spacedBy(Tokens.Space.xxs),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                color = Tokens.Palette.text,
                modifier = Modifier.padding(bottom = Tokens.Space.xs),
            )

            Progress.entries.forEach { option ->
                StatusRow(
                    option = option,
                    selected = option == current,
                    onClick = { onPick(option) },
                )
            }
        }
    }
}

@Composable
private fun StatusRow(
    option: Progress,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Tokens.Space.sm),
        modifier = Modifier
            .fillMaxWidth()
            .pressable(onClick = onClick)
            .padding(vertical = Tokens.Space.sm),
    ) {
        // The selected state is carried by a filled dot rather than a tick
        // glyph, so it needs no icon dependency and reads at a glance.
        Column(
            modifier = Modifier
                .size(Tokens.Space.sm)
                .clip(CircleShape)
                .background(
                    if (selected) Tokens.Palette.accent else Tokens.Palette.bg,
                ),
        ) {}

        Text(
            text = option.label,
            style = MaterialTheme.typography.bodyMedium,
            color = if (selected) Tokens.Palette.text else Tokens.Palette.textDim,
        )
    }
}
