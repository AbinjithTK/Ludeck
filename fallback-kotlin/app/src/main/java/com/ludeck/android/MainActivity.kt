package com.ludeck.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.room.Room
import com.ludeck.android.data.db.LudeckDatabase
import com.ludeck.android.data.db.ShelfRow
import com.ludeck.android.data.model.Progress
import com.ludeck.android.ui.shelf.ShelfScreen
import com.ludeck.android.ui.shelf.ShelfState
import com.ludeck.android.ui.shelf.Suggestion
import com.ludeck.android.ui.theme.LudeckTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** Seconds to hours. The ONE place this division happens. */
private const val SECONDS_PER_HOUR = 3600

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Built here for the first build. This moves behind dependency injection
        // once there is a second consumer; doing it now would be ceremony.
        val db = Room.databaseBuilder(
            applicationContext,
            LudeckDatabase::class.java,
            "ludeck.db",
        ).build()

        setContent {
            LudeckTheme {
                val scope = rememberCoroutineScope()

                val rows by remember { db.dao().observeShelf() }
                    .collectAsState(initial = emptyList())

                val state by remember { db.dao().observeShelf() }
                    .map { list ->
                        if (list.isEmpty()) ShelfState.Empty else ShelfState.Content(list)
                    }
                    .collectAsState(initial = ShelfState.Loading)

                // How many suggestions the user has waved away this session.
                // Skipping walks down the candidate list rather than reshuffling,
                // so the same card never comes straight back.
                var skipped by remember { mutableIntStateOf(0) }

                ShelfScreen(
                    state = state,
                    suggestion = pickSuggestion(rows, skipped),
                    onImportSteam = {
                        // Wired in task 117. Deliberately inert rather than fake:
                        // a button that pretends to work is worse than one that waits.
                    },
                    onSetProgress = { igdbId, progress ->
                        val row = rows.firstOrNull { it.game.igdbId == igdbId }
                        if (row != null) {
                            scope.launch(Dispatchers.IO) {
                                db.dao().upsertEntries(
                                    listOf(row.entry.copy(progress = progress)),
                                )
                            }
                        }
                    },
                    onStartSuggestion = {
                        val pick = pickSuggestion(rows, skipped)
                        val row = rows.firstOrNull { it.game.igdbId == pick?.igdbId }
                        if (row != null) {
                            scope.launch(Dispatchers.IO) {
                                db.dao().upsertEntries(
                                    listOf(row.entry.copy(progress = Progress.PLAYING)),
                                )
                            }
                        }
                    },
                    onSkipSuggestion = { skipped += 1 },
                )
            }
        }
    }
}

/**
 * What to play tonight.
 *
 * The rule is deliberately legible rather than clever: among the games you own
 * and have never started, offer the shortest one with a known length. A player
 * staring at two hundred games does not need a better ranking model, they need
 * one name and a reason they can accept or reject in a second.
 *
 * Games with no known length are excluded rather than guessed at, because the
 * reason line is the whole value and "unknown hours" is not a reason.
 */
private fun pickSuggestion(rows: List<ShelfRow>, skipped: Int): Suggestion? {
    val candidates = rows
        .filter { it.entry.progress == Progress.UNTOUCHED }
        .filter { (it.game.timeToBeatSeconds ?: 0) > 0 }
        .sortedBy { it.game.timeToBeatSeconds }

    if (candidates.isEmpty()) return null

    val row = candidates[skipped % candidates.size]
    val hours = (row.game.timeToBeatSeconds ?: 0) / SECONDS_PER_HOUR

    val year = row.game.releaseYear
    val detail = buildString {
        append("$hours hours")
        if (year != null) append(" · released $year")
        append(" · never opened")
    }

    return Suggestion(
        igdbId = row.game.igdbId,
        title = row.game.title,
        reason = if (hours <= 15) {
            "Short enough to finish this week"
        } else {
            "The shortest thing you have not started"
        },
        detail = detail,
    )
}
