package com.ludeck.android

import android.content.ClipData
import android.content.Intent
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives text shared to Ludeck from any other app.
 *
 * Deliberately PULL based rather than push. Dart asks for the pending share on
 * startup and again whenever the app resumes; this class only stores it. The
 * alternative, invoking a Dart method the moment an intent arrives, has to
 * reason about whether the Flutter engine is attached yet, and on a cold share
 * it is not. One mechanism that cannot race is worth more than two that can.
 *
 * Both entry points are covered:
 *  - cold start: the activity is created WITH the share intent, read in onCreate
 *  - warm start: the activity is already running, so singleTop routes the intent
 *    to onNewIntent
 */
class MainActivity : FlutterActivity() {

    /** Set by an incoming intent, cleared when Dart takes it. */
    private var pendingShare: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingShare = extractSharedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Keep getIntent() honest for anything that reads it later.
        setIntent(intent)
        extractSharedText(intent)?.let { pendingShare = it }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Returns the pending share and clears it, so one share is
                    // acted on exactly once however many times Dart asks.
                    "takePendingShare" -> {
                        val share = pendingShare
                        pendingShare = null
                        result.success(share)
                    }
                    // Share OUT: the system chooser with the link text and,
                    // when given, the orchard card image (served from the
                    // cache dir through the FileProvider in the manifest).
                    "shareOut" -> {
                        val text = call.argument<String>("text") ?: ""
                        val image = call.argument<String>("image")
                        val send = Intent(Intent.ACTION_SEND)
                        if (image != null) {
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.share", File(image))
                            send.type = "image/png"
                            send.putExtra(Intent.EXTRA_STREAM, uri)
                            send.clipData = ClipData.newRawUri("", uri)
                            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        } else {
                            send.type = "text/plain"
                        }
                        send.putExtra(Intent.EXTRA_TEXT, text)
                        startActivity(Intent.createChooser(send, null))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * The shared text, or null when this intent is not a text share.
     *
     * EXTRA_TEXT is documented as a CharSequence. Most apps put a String there,
     * but not all, so the CharSequence path is a real fallback rather than
     * defensive noise.
     */
    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null

        val raw = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: return null

        val trimmed = raw.trim()
        return if (trimmed.isEmpty()) null else trimmed
    }

    private companion object {
        const val CHANNEL = "com.ludeck.android/share"
    }
}
