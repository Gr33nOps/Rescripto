package com.rescripto.rescripto

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's one and only Flutter engine/Activity, and the single place
 * every external entry point (ACTION_PROCESS_TEXT, ACTION_SEND, the Quick
 * Settings tile) hands text into the running app — deliberately not three
 * separate activities. Nothing about "process this selected text" or
 * "share this text in" needs a second Flutter engine or a duplicated
 * provider tree; it only needs this activity to notice a new intent and
 * tell Dart about it. See [RescriptoTileService] for the third caller.
 *
 * [CHANNEL] carries two things, kept deliberately small:
 *   - native -> Dart: "incomingText" (pushed on [onNewIntent], where the
 *     Dart side is already running and its handler is already registered)
 *     and "getInitialIntent" (Dart calls this once at startup to pull
 *     whatever launched a cold start — a push at that point would race
 *     Dart's handler registration, since the engine is still being stood
 *     up when [configureFlutterEngine] runs).
 *   - Dart -> native: "finishProcessText", the one native action a
 *     PROCESS_TEXT round-trip needs — returning EXTRA_PROCESS_TEXT and
 *     finishing the activity. Declining is not a separate message: if the
 *     activity finishes without ever calling setResult(), Android's own
 *     default delivers RESULT_CANCELED to the caller, which is already
 *     the correct behaviour.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialIntent" -> result.success(extractIncomingText(intent)?.toMap())
                "finishProcessText" -> {
                    val text = call.argument<String>("text")
                    setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, text))
                    finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val incoming = extractIncomingText(intent) ?: return
        channel?.invokeMethod("incomingText", incoming.toMap())
    }

    private data class IncomingText(val text: String, val source: String, val readOnly: Boolean) {
        fun toMap(): Map<String, Any> = mapOf("text" to text, "source" to source, "readOnly" to readOnly)
    }

    private fun extractIncomingText(intent: Intent?): IncomingText? {
        intent ?: return null
        return when {
            intent.action == Intent.ACTION_PROCESS_TEXT && intent.type == "text/plain" -> {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString() ?: return null
                val readOnly = intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, false)
                IncomingText(text, "process_text", readOnly)
            }
            intent.action == Intent.ACTION_SEND && intent.type == "text/plain" -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
                IncomingText(text, "share", false)
            }
            intent.action == ACTION_TILE_REWRITE -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
                IncomingText(text, "tile", false)
            }
            else -> null
        }
    }

    companion object {
        const val CHANNEL = "com.rescripto.rescripto/system"

        /** Fired by [RescriptoTileService] with the current clipboard text. */
        const val ACTION_TILE_REWRITE = "com.rescripto.rescripto.ACTION_TILE_REWRITE"
    }
}
