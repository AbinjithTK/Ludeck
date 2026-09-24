package com.ludeck.android.data.db

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.ludeck.android.data.model.Copy
import com.ludeck.android.data.model.Entry
import com.ludeck.android.data.model.Game
import kotlinx.coroutines.flow.Flow

/** A shelf row: the catalogue record plus the user's relationship to it. */
data class ShelfRow(
    @Embedded(prefix = "g_") val game: Game,
    @Embedded(prefix = "e_") val entry: Entry,
)

@Dao
interface LudeckDao {

    /**
     * The shelf. Shelved rows are excluded here rather than deleted, so nothing
     * is ever lost. Ordering is by title for now; the sort is a product
     * decision that belongs in the ViewModel, not baked into SQL.
     */
    @Query(
        """
        SELECT
            g.igdbId AS g_igdbId, g.title AS g_title, g.coverUrl AS g_coverUrl,
            g.releaseYear AS g_releaseYear, g.timeToBeatSeconds AS g_timeToBeatSeconds,
            e.igdbId AS e_igdbId, e.ownership AS e_ownership, e.progress AS e_progress,
            e.rating AS e_rating, e.note AS e_note, e.lastPlayedAt AS e_lastPlayedAt,
            e.shelved AS e_shelved
        FROM entries e
        JOIN games g ON g.igdbId = e.igdbId
        WHERE e.shelved = 0
        ORDER BY g.title COLLATE NOCASE ASC
        """
    )
    fun observeShelf(): Flow<List<ShelfRow>>

    @Query("SELECT COUNT(*) FROM entries WHERE shelved = 0")
    fun observeCount(): Flow<Int>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertGames(games: List<Game>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertEntries(entries: List<Entry>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCopies(copies: List<Copy>)

    @Query("SELECT * FROM copies WHERE igdbId = :igdbId")
    fun observeCopies(igdbId: Long): Flow<List<Copy>>
}

@Database(
    entities = [Game::class, Entry::class, Copy::class],
    version = 1,
    // Off until the Room Gradle plugin is added with a schemaLocation. Schema
    // export is worth turning on before the FIRST migration, because it is what
    // makes a migration test able to prove no user row is dropped.
    exportSchema = false,
)
@TypeConverters(Converters::class)
abstract class LudeckDatabase : RoomDatabase() {
    abstract fun dao(): LudeckDao
}
