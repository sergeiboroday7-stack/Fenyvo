package com.fenyvo.app

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/** Foreground/connected-app alert only; this is not a background call service. */
@Suppress("DEPRECATION")
internal class IncomingCallAlertController(context: Context) {
    private val app = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val audio = app.getSystemService(AudioManager::class.java)
    private val notifications = app.getSystemService(NotificationManager::class.java)
    private val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
        app.getSystemService(VibratorManager::class.java).defaultVibrator
    } else {
        app.getSystemService(Vibrator::class.java)
    }
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()
    private var activeCallId: String? = null
    private var policy: IncomingAlertPolicy? = null
    private var player: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null
    private var legacyFocus = false
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
            stopSound()
        }
    }

    private val policyTick = object : Runnable {
        override fun run() {
            val id = activeCallId ?: return
            refreshPolicy(id)
            if (activeCallId == id) handler.postDelayed(this, 500)
        }
    }

    fun start(callId: String) {
        if (callId == activeCallId) return
        stop()
        activeCallId = callId
        policyTick.run()
        // Native fail-safe also works if Dart is paused or loses its timer.
        handler.postDelayed({ stop(callId) }, 75_000)
    }

    fun stop(expectedCallId: String? = null) {
        if (expectedCallId != null && activeCallId != expectedCallId) return
        activeCallId = null
        policy = null
        handler.removeCallbacksAndMessages(null)
        stopSound()
        stopVibration()
    }

    private fun readPolicy(): IncomingAlertPolicy {
        // Never bypass DND or change the user's ringer mode/volume.
        val dnd = notifications.currentInterruptionFilter !=
            NotificationManager.INTERRUPTION_FILTER_ALL
        return incomingAlertPolicy(audio.ringerMode, dnd, audio.getStreamVolume(AudioManager.STREAM_RING))
    }

    private fun refreshPolicy(id: String) {
        val next = try {
            readPolicy()
        } catch (error: Exception) {
            Log.w("FenyvoCall", "Could not read ringing policy", error)
            IncomingAlertPolicy(false, false)
        }
        val previous = policy
        if (previous == next) return
        policy = next
        if (previous?.sound != next.sound) {
            if (next.sound) startSound(id) else stopSound()
        }
        if (previous?.vibration != next.vibration) {
            if (next.vibration) startVibration() else stopVibration()
        }
    }

    private fun requestFocus(): Boolean {
        val result = if (Build.VERSION.SDK_INT >= 26) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener, handler)
                .build()
            focusRequest = request
            audio.requestAudioFocus(request)
        } else {
            legacyFocus = true
            audio.requestAudioFocus(focusListener, AudioManager.STREAM_RING,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun startSound(id: String) {
        stopSound()
        try {
            if (!requestFocus()) {
                stopSound()
                return
            }
            val candidate = MediaPlayer()
            player = candidate
            candidate.setAudioAttributes(attributes)
            app.resources.openRawResourceFd(R.raw.spartan_phoenix_call).use { descriptor ->
                candidate.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
            }
            candidate.isLooping = true
            candidate.setOnPreparedListener { prepared ->
                if (player === prepared && activeCallId == id) {
                    try {
                        if (readPolicy().sound) prepared.start() else stopSound()
                    } catch (error: Exception) {
                        Log.w("FenyvoCall", "Ringtone playback unavailable", error)
                        stopSound()
                    }
                }
            }
            candidate.setOnErrorListener { failed, _, _ ->
                if (player === failed) stopSound()
                true
            }
            candidate.prepareAsync()
        } catch (error: Exception) {
            Log.w("FenyvoCall", "Ringtone preparation unavailable", error)
            stopSound()
        }
    }

    private fun stopSound() {
        val previous = player
        player = null
        previous?.setOnPreparedListener(null)
        previous?.setOnErrorListener(null)
        previous?.release()
        val request = focusRequest
        focusRequest = null
        if (Build.VERSION.SDK_INT >= 26 && request != null) {
            audio.abandonAudioFocusRequest(request)
        }
        if (legacyFocus) {
            legacyFocus = false
            audio.abandonAudioFocus(focusListener)
        }
    }

    private fun startVibration() {
        if (!vibrator.hasVibrator()) return
        // Three gentle pulses and a pause; same 4.8-second cycle as the melody.
        val timings = longArrayOf(0, 180, 110, 180, 110, 320, 3900)
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                val effect = if (vibrator.hasAmplitudeControl()) {
                    VibrationEffect.createWaveform(timings, intArrayOf(0, 120, 0, 150, 0, 190, 0), 0)
                } else {
                    VibrationEffect.createWaveform(timings, 0)
                }
                if (Build.VERSION.SDK_INT >= 33) {
                    vibrator.vibrate(effect, VibrationAttributes.Builder()
                        .setUsage(VibrationAttributes.USAGE_RINGTONE).build())
                } else {
                    vibrator.vibrate(effect, attributes)
                }
            } else {
                vibrator.vibrate(timings, 0, attributes)
            }
        } catch (error: Exception) {
            Log.w("FenyvoCall", "Call vibration unavailable", error)
        }
    }

    private fun stopVibration() {
        try { vibrator.cancel() } catch (_: Exception) { /* Already stopped. */ }
    }
}
