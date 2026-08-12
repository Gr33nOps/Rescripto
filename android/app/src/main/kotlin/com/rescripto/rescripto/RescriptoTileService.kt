package com.rescripto.rescripto

import android.app.PendingIntent
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast

/**
 * Quick Settings tile: tap reads the clipboard and opens the app with that
 * text pre-loaded into the rewrite screen — the same [MainActivity.ACTION_TILE_REWRITE]
 * path a share does, just triggered from the clipboard instead of an
 * incoming SEND intent.
 *
 * Deliberately does not rewrite in the tile's own process. The tile host
 * process is not where an on-device model should ever load; handing off to
 * the already-running (or freshly launched) app and letting the user
 * review the result before copying it back is also the same
 * confirm-before-anything-happens pattern already used everywhere else in
 * this app — a fully silent clipboard-in, clipboard-out tile would be the
 * one place that pattern broke.
 */
class RescriptoTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            label = getString(R.string.tile_label)
            state = Tile.STATE_ACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()

        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip
        val text = if (clip != null && clip.itemCount > 0) {
            clip.getItemAt(0).coerceToText(this)?.toString()?.trim()
        } else {
            null
        }

        if (text.isNullOrEmpty()) {
            Toast.makeText(this, "Copy some text first", Toast.LENGTH_SHORT).show()
            return
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_TILE_REWRITE
            putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            // The PendingIntent overload doesn't exist before API 34, so this
            // branch is unreachable on any device where the deprecation
            // enforcement (targetSdk >= 34 AND device OS >= 34) actually
            // throws — lint's StartActivityAndCollapseDeprecated check has no
            // way to see that from the call site alone.
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }
}
