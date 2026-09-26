package com.fenyvo.app

import android.app.Application
import android.os.Bundle
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** Decline must reach the caller even if no Flutter UI engine is running. */
class SpartanApplication : Application(), CallkitEventCallback {
    private val network = Executors.newSingleThreadExecutor()
    override fun onCreate() {
        super.onCreate()
        FlutterCallkitIncomingPlugin.registerEventCallback(this)
    }
    @Suppress("DEPRECATION")
    override fun onCallEvent(event: CallkitEventCallback.CallEvent, callData: Bundle) {
        if (event != CallkitEventCallback.CallEvent.DECLINE) return
        val extra = callData.getSerializable("EXTRA_CALLKIT_EXTRA") as? Map<*, *> ?: return
        val endpoint = extra["endpoint"]?.toString() ?: return
        val token = extra["callToken"]?.toString() ?: return
        val expires = extra["expiresAt"]?.toString()?.toLongOrNull() ?: return
        if (expires < System.currentTimeMillis() || !token.matches(Regex("[0-9a-f]{64}"))) return
        network.execute {
            var connection: HttpURLConnection? = null
            try {
                val url = URL(endpoint)
                if (url.protocol !in listOf("http", "https") || !url.path.startsWith("/calls/")) return@execute
                connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 4000
                    readTimeout = 4000
                    instanceFollowRedirects = false
                    setRequestProperty("Authorization", "Bearer $token")
                    setFixedLengthStreamingMode(0)
                    doOutput = true
                }
                connection.outputStream.close()
                connection.responseCode
            } catch (_: Exception) {
                // The server's short ringing deadline remains the fallback.
            } finally { connection?.disconnect() }
        }
    }
}
