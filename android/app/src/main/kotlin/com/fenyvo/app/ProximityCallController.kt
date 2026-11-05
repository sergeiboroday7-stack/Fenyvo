package com.fenyvo.app

import android.content.Context
import android.os.PowerManager

class ProximityCallController(context: Context) {
    private val powerManager =
        context.getSystemService(Context.POWER_SERVICE) as PowerManager

    private var wakeLock: PowerManager.WakeLock? = null
    private var currentCallId: String? = null
    private val endedCalls = LinkedHashSet<String>()

    fun endCall(callId: String) {
        endedCalls.add(callId)
        while (endedCalls.size > 64) {
            endedCalls.remove(endedCalls.first())
        }
        if (currentCallId == callId) {
            stop()
        }
    }

    fun setEnabled(callId: String, enabled: Boolean): Boolean {
        if (enabled && endedCalls.contains(callId)) {
            return false
        }
        if (!enabled) {
            if (currentCallId == callId) {
                stop()
            }
            return true
        }

        if (!powerManager.isWakeLockLevelSupported(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK
            )) {
            return false
        }

        if (currentCallId == callId && wakeLock?.isHeld == true) {
            return true
        }

        stop()

        return try {
            val lock = powerManager.newWakeLock(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                "fenyvo:voice-call-proximity"
            )
            wakeLock = lock
            currentCallId = callId
            lock.acquire()
            true
        } catch (error: Exception) {
            stop()
            false
        }
    }

    fun stop() {
        val lock = wakeLock
        wakeLock = null
        currentCallId = null

        if (lock?.isHeld == true) {
            try {
                lock.release()
            } catch (_: Exception) {
                // Never block call cleanup.
            }
        }
    }
}