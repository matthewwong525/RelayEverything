package com.matthewwong525.relay_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// The share card: Relay Everything in Android's share list. It runs Dart's shareMain (lib/share/share_main.dart) in a
// see-through window over the app the person shares from, and Save closes it, back to that app.
class ShareActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName() = "shareMain"

    override fun getDartEntrypointLibraryUri() = "package:relay_app/share/share_main.dart"

    override fun getBackgroundMode() = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "relay/share").setMethodCallHandler { call, result ->
            if (call.method != "items") return@setMethodCallHandler result.notImplemented()
            val shared = intent
            // Copying a big file takes a while, so it runs off the main thread; the answer goes back on it.
            Thread {
                val items = try {
                    items(shared)
                } catch (error: Exception) {
                    mapOf("files" to emptyList<Any>())
                }
                Handler(Looper.getMainLooper()).post { result.success(items) }
            }.start()
        }
    }

    // The read grant for each content:// item ends with this window, so each file is copied into the app's cache now.
    // A file over 25 MB is not copied: the card names it as too big.
    private fun items(shared: Intent): Map<String, Any?> {
        val uris = when (shared.action) {
            Intent.ACTION_SEND -> listOfNotNull(stream(shared))
            Intent.ACTION_SEND_MULTIPLE -> streams(shared)
            else -> emptyList()
        }
        val folder = File(cacheDir, "shared")
        folder.deleteRecursively()
        folder.mkdirs()
        val files = uris.mapIndexedNotNull { index, uri -> copy(uri, folder, index) }
        return mapOf(
            "text" to shared.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
            "subject" to shared.getStringExtra(Intent.EXTRA_SUBJECT),
            "files" to files,
        )
    }

    @Suppress("DEPRECATION")
    private fun stream(shared: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) shared.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else shared.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streams(shared: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) shared.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else shared.getParcelableArrayListExtra(Intent.EXTRA_STREAM)) ?: emptyList()

    private fun copy(uri: Uri, folder: File, index: Int): Map<String, Any?>? {
        var name = "file-${index + 1}"
        var size = -1L
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameAt = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeAt = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameAt >= 0 && !cursor.isNull(nameAt)) name = cursor.getString(nameAt)
                    if (sizeAt >= 0 && !cursor.isNull(sizeAt)) size = cursor.getLong(sizeAt)
                }
            }
        } catch (error: Exception) {
            // A provider with no columns: the name stays plain, and the copy gives the size.
        }
        val type = contentResolver.getType(uri)
        if (size > MAX_FILE_BYTES) return mapOf("path" to null, "name" to name, "type" to type, "size" to size)
        val target = File(folder, "${index + 1}-${name.replace('/', '-')}")
        val copied = try {
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
        } catch (error: Exception) {
            target.delete()
            return null
        }
        return mapOf("path" to target.absolutePath, "name" to name, "type" to type, "size" to copied)
    }

    companion object {
        // The same limit as the app's: 25 MB a file.
        const val MAX_FILE_BYTES = 25L * 1024 * 1024
    }
}
