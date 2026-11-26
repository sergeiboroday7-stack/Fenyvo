package com.fenyvo.app

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID

/** Accepts only explicit text and a bounded set of image streams from Android Sharesheet. */
internal class IncomingShareBridge(
    private val activity: FlutterActivity,
    engine: FlutterEngine
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "fenyvo/incoming_share")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var loading = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingShare" -> getPendingShare(result)
                else -> result.notImplemented()
            }
        }
    }

    fun notifyNewIntent(intent: Intent) {
        if (isShare(intent)) channel.invokeMethod("shareAvailable", null)
    }

    fun close() {
        channel.setMethodCallHandler(null)
    }

    private fun isShare(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE

    private fun getPendingShare(result: MethodChannel.Result) {
        val incoming = activity.intent
        if (!isShare(incoming) || loading) {
            result.success(null)
            return
        }
        loading = true
        Thread({
            val response: Map<String, Any?> = try {
                importShare(incoming)
            } catch (_: Exception) {
                mapOf("error" to "Не удалось безопасно прочитать вложение")
            }
            mainHandler.post {
                // Do not discard a newer share which may have arrived during import.
                if (activity.intent === incoming) {
                    activity.intent = Intent(Intent.ACTION_MAIN)
                }
                loading = false
                result.success(response)
            }
        }, "fenyvo-incoming-share").start()
    }

    @Suppress("DEPRECATION")
    private fun importShare(incoming: Intent): Map<String, Any?> {
        val text = incoming.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()?.take(8192).orEmpty()
        val sourceType = incoming.type?.lowercase().orEmpty()
        val images = mutableListOf<Map<String, String>>()

        if (sourceType.startsWith("image/")) {
            val uris = mutableListOf<Uri>()
            if (incoming.action == Intent.ACTION_SEND) {
                incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
            } else if (incoming.action == Intent.ACTION_SEND_MULTIPLE) {
                incoming.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::addAll)
            }
            incoming.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) {
                    clip.getItemAt(i).uri?.let(uris::add)
                }
            }
            val unique = uris.distinctBy(Uri::toString)
            if (unique.size > 5) throw IOException("Too many shared images")
            for (uri in unique) images.add(copyPrivateImage(uri, sourceType))
        } else if (incoming.action != Intent.ACTION_SEND || sourceType != "text/plain") {
            throw IOException("Unsupported MIME type")
        }
        if (images.isEmpty() && text.isBlank()) throw IOException("Empty share")
        return mapOf("text" to text, "images" to images)
    }

    private fun copyPrivateImage(uri: Uri, sourceType: String): Map<String, String> {
        // Never trust file:// paths or filenames from third-party apps.
        if (uri.scheme != "content") throw IOException("Unsupported URI")
        val contentType = activity.contentResolver.getType(uri)?.lowercase() ?: sourceType
        val extension = when (contentType) {
            "image/jpeg", "image/jpg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/heic" -> "heic"
            "image/heif" -> "heif"
            "image/gif" -> "gif"
            else -> throw IOException("Unsupported image MIME")
        }
        val directory = File(activity.cacheDir, "incoming_share")
        if (!directory.exists() && !directory.mkdirs()) throw IOException("Cannot create share cache")
        val target = File(directory, "shared_${UUID.randomUUID()}.$extension")
        try {
            val stream = activity.contentResolver.openInputStream(uri)
                ?: throw IOException("Cannot open share")
            stream.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var copied = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        copied += count
                        if (copied > 20L * 1024 * 1024) throw IOException("Image too large")
                        output.write(buffer, 0, count)
                    }
                    if (copied == 0L) throw IOException("Empty image")
                }
            }
            return mapOf(
                "path" to target.absolutePath,
                "fileName" to target.name,
                "mimeType" to contentType
            )
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }
}
