package com.ludeck.android.data.db

import androidx.room.TypeConverter
import com.ludeck.android.data.model.Acquired
import com.ludeck.android.data.model.Form
import com.ludeck.android.data.model.Ownership
import com.ludeck.android.data.model.Progress

/**
 * Stores enums by NAME, not ordinal.
 *
 * Ordinals are a trap: reordering an enum silently rewrites the meaning of
 * every stored row, and an added value in the middle corrupts history with no
 * error. Names cost a few bytes and cannot do that.
 */
class Converters {
    @TypeConverter fun ownershipToString(v: Ownership): String = v.name
    @TypeConverter fun stringToOwnership(v: String): Ownership = Ownership.valueOf(v)

    @TypeConverter fun progressToString(v: Progress): String = v.name
    @TypeConverter fun stringToProgress(v: String): Progress = Progress.valueOf(v)

    @TypeConverter fun formToString(v: Form): String = v.name
    @TypeConverter fun stringToForm(v: String): Form = Form.valueOf(v)

    @TypeConverter fun acquiredToString(v: Acquired): String = v.name
    @TypeConverter fun stringToAcquired(v: String): Acquired = Acquired.valueOf(v)
}
