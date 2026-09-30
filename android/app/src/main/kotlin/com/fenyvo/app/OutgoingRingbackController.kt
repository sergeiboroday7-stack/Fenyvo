package com.fenyvo.app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlin.math.PI
import kotlin.math.sin

/** Caller-side call-progress tones routed through Android communication audio. */
internal class OutgoingRingbackController {
    private enum class Kind { RINGBACK, BUSY, ENDED }

    private val handler = Handler(Looper.getMainLooper())
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()
    private var activeCallId: String? = null
    private var activeKind: Kind? = null
    private var track: AudioTrack? = null

    fun start(callId: String) {
        if (activeCallId == callId && activeKind == Kind.RINGBACK) return
        play(callId, Kind.RINGBACK, ringbackSamples(), loop = true)
    }

    fun busy(callId: String) {
        play(callId, Kind.BUSY, busySamples(), loop = false)
    }

    fun ended(callId: String) {
        play(callId, Kind.ENDED, endedSamples(), loop = false)
    }

    /** Cleanup must not cut off a busy/end confirmation that has just started. */
    fun stopRingback(expectedCallId: String? = null) {
        if (activeKind != Kind.RINGBACK) return
        stop(expectedCallId)
    }

    fun stop(expectedCallId: String? = null) {
        if (expectedCallId != null && activeCallId != expectedCallId) return
        activeCallId = null
        activeKind = null
        handler.removeCallbacksAndMessages(null)
        val previous = track
        track = null
        try {
            previous?.pause()
            previous?.flush()
            previous?.release()
        } catch (_: Exception) {
            // The native track may already be released by Android.
        }
    }

    private fun play(
        callId: String,
        kind: Kind,
        samples: ShortArray,
        loop: Boolean,
    ) {
        stop()
        activeCallId = callId
        activeKind = kind
        try {
            val candidate = AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(samples.size * 2)
                .build()
            track = candidate
            val written = candidate.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING)
            if (written != samples.size) throw IllegalStateException("Incomplete call tone")
            candidate.setVolume(0.38f)
            if (loop) candidate.setLoopPoints(0, samples.size, -1)
            candidate.play()
            val durationMs = if (loop) 75_000L else samples.size * 1000L / SAMPLE_RATE + 120L
            handler.postDelayed({
                if (activeCallId == callId && activeKind == kind) stop(callId)
            }, durationMs)
        } catch (error: Exception) {
            Log.w("FenyvoCall", "Call progress tone unavailable", error)
            stop(callId)
        }
    }

    private fun ringbackSamples(): ShortArray {
        val result = ShortArray(SAMPLE_RATE * 4)
        addTone(result, 0, 260, 440.0, 554.37)
        addTone(result, 360, 280, 554.37, 659.25)
        return result
    }

    private fun busySamples(): ShortArray {
        val result = ShortArray((SAMPLE_RATE * 1.45).toInt())
        for (start in intArrayOf(0, 420, 840)) {
            addTone(result, start, 230, 480.0, 620.0)
        }
        return result
    }

    private fun endedSamples(): ShortArray {
        val result = ShortArray((SAMPLE_RATE * 0.7).toInt())
        addTone(result, 0, 120, 698.46)
        addTone(result, 145, 170, 523.25)
        addTone(result, 340, 260, 349.23)
        return result
    }

    private fun addTone(
        target: ShortArray,
        startMs: Int,
        durationMs: Int,
        vararg frequencies: Double,
    ) {
        val start = startMs * SAMPLE_RATE / 1000
        val length = durationMs * SAMPLE_RATE / 1000
        val fade = (SAMPLE_RATE * 0.018).toInt().coerceAtLeast(1)
        for (offset in 0 until length) {
            val index = start + offset
            if (index !in target.indices) break
            val envelope = minOf(
                1.0,
                offset.toDouble() / fade,
                (length - offset).toDouble() / fade,
            )
            var wave = 0.0
            for (frequency in frequencies) {
                wave += sin(2.0 * PI * frequency * offset / SAMPLE_RATE)
            }
            wave /= frequencies.size.coerceAtLeast(1)
            target[index] = (wave * envelope * Short.MAX_VALUE * 0.62).toInt().toShort()
        }
    }

    private companion object {
        const val SAMPLE_RATE = 16_000
    }
}
