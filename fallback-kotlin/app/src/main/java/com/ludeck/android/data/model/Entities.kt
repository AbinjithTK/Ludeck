package com.ludeck.android.data.model

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Catalogue data. One row per IGDB id, never duplicated.
 *
 * igdbId is THE identity. Never match a game on its title: IGDB search returns
 * DLC and remasters above base games, and titles get edited.
 */
@Entity(tableName = "games")
data class Game(
    @PrimaryKey val igdbId: Long,
    val title: String,
    val coverUrl: String?,
    val releaseYear: Int?,

    /**
     * SECONDS, exactly as IGDB returns them. Converted to hours in exactly one
     * place, the mapper. check.ps1 fails on a division by anything but 3600.
     */
    val timeToBeatSeconds: Int?,
)

/**
 * One owned copy. A SET of these, not a field on the game, because people own
 * the same game on more than one platform and a sale should remove one copy
 * without erasing the other.
 */
@Entity(
    tableName = "copies",
    indices = [Index("igdbId")],
)
data class Copy(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val igdbId: Long,

    /** Free text from a fixed list: Steam, PS5, Switch, iOS, Android, ... */
    val platform: String,
    val form: Form,
    val acquired: Acquired,
    val pricePaidMinor: Int?,
)

/** The user's relationship to a game. One row per game. */
@Entity(tableName = "entries")
data class Entry(
    @PrimaryKey val igdbId: Long,
    val ownership: Ownership,
    val progress: Progress,
    val rating: Int?,
    val note: String?,

    /** From Steam's rtime_last_played when available. Drives ABANDONED without asking. */
    val lastPlayedAt: Long?,

    /** Replaces delete. Deleting a collection row is not a feature. */
    val shelved: Boolean = false,
)

/** A game plus the user's relationship to it, for list rendering. */
data class ShelfItem(
    val game: Game,
    val entry: Entry,
)
