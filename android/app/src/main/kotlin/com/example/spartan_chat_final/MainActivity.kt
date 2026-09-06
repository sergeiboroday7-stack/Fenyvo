package com.example.spartan_chat_final

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.view.WindowManager
import com.hiennv.flutter_callkit_incoming.getDataActiveCalls
import com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver

class MainActivity: FlutterActivity() {
    private var alert: IncomingCallAlertController? = null
    private var alertChannel: MethodChannel? = null
    private var callWindowChannel: MethodChannel? = null
    private var visibleCallId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        callWindowChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "spartan_chat/call_window").also { channel ->
            channel.setMethodCallHandler { call, result ->
                val id = call.argument<String>("callId")
                if (id.isNullOrBlank() || id.length > 100) {
                    result.error("INVALID_CALL", "Call ID required", null)
                } else if (call.method == "accept") {
                    val pending = getDataActiveCalls(this).firstOrNull { it.id == id }
                    if (pending != null && !pending.isAccepted) {
                        sendBroadcast(CallkitIncomingBroadcastReceiver.getIntentAccept(this, pending.toBundle()))
                    }
                    result.success(null)
                } else if (call.method == "show" || call.method == "hide") {
                    val show = call.method == "show"
                    if (show || visibleCallId == id) {
                        visibleCallId = if (show) id else null
                        if (Build.VERSION.SDK_INT >= 27) {
                            setShowWhenLocked(show)
                            setTurnScreenOn(show)
                        } else {
                            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            if (show) window.addFlags(flags) else window.clearFlags(flags)
                        }
                    }
                    result.success(null)
                } else result.notImplemented()
            }
        }
        alert = IncomingCallAlertController(this)
        alertChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "spartan_chat/incoming_call_alert").also { channel ->
            channel.setMethodCallHandler { call, result ->
                val id = call.argument<String>("callId")
                if (id.isNullOrBlank() || id.length > 100) {
                    result.error("INVALID_CALL", "A valid call ID is required", null)
                } else {
                    when (call.method) {
                        "start" -> { alert?.start(id); result.success(null) }
                        "stop" -> { alert?.stop(id); result.success(null) }
                        else -> result.notImplemented()
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        callWindowChannel?.setMethodCallHandler(null)
        callWindowChannel = null
        alertChannel?.setMethodCallHandler(null)
        alertChannel = null
        alert?.stop()
        alert = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        alert?.stop()
        super.onDestroy()
    }
}
