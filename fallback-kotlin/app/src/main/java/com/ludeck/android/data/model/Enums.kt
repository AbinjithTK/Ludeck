package com.ludeck.android.data.model

/**
 * The ONLY status vocabulary in this app. Copied verbatim from BUILD.md
 * section 4. scripts\check.ps1 fails the build if `want_to_play`, `wantToPlay`,
 * `backlog`, `completed`, `beaten`, `dropped` or `on_hold` appear anywhere.
 *
 * Two orthogonal axes, not one chain. A single chain cannot express "I finished
 * it and then sold it", which is a normal collector state, and it forces a sale
 * to destroy the completion record.
 */

/** Do I have it? */
enum class Ownership(val label: String) {
    /** Seen and saved, not owned. This is the state the judged tie-break criterion is about. */
    SPOTTED("Spotted"),
    OWNED("Owned"),

    /** Sold, traded, refunded, or lapsed out of a subscription. */
    RELEASED("Let go"),
}

/**
 * How far did I get?
 *
 * The labels are what a person reads, and they are deliberately not verdicts.
 * "Set aside" is the same data as a harsher word would carry and costs the user
 * nothing to look at, which matters in an app whose whole subject is a pile of
 * things you have not played.
 */
enum class Progress(val label: String) {
    UNTOUCHED("Not started"),
    INSTALLED("Installed"),
    PLAYING("Playing"),
    FINISHED("Finished"),

    /** Not the same event as finishing. This is where the interesting data lives. */
    ABANDONED("Set aside"),
}

/** Digital or a physical object on a shelf. Physical is what makes RELEASED honest. */
enum class Form(val label: String) {
    DIGITAL("Digital"),
    PHYSICAL("Physical"),
}

/** How the copy was acquired. Subscription matters: it can lapse and remove access. */
enum class Acquired(val label: String) {
    BOUGHT("Bought"),
    SUBSCRIPTION("Subscription"),
    GIFT("Gift"),
    BUNDLE("Bundle"),
    FREE("Free"),
}
