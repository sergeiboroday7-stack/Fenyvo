package com.fenyvo.app

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.sqrt

/**
 * Reads amplitude envelopes from already-local, decrypted video files.
 *
 * No microphone access, network requests, stored PCM, or message transport.
 * Work is performed off the main/UI thread.
 */
internal object HexVideoAudioLevels {
    private const val CHANNEL = "fenyvo/hex_video_audio"
    private const val WINDOW_US = 100_000L
    private const val MAX_WINDOWS = 600
    private const val MAX_BYTES = 200L * 1024L * 1024L
    private const val TIME_LIMIT_NS = 30_000_000_000L

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "analyze") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("INVALID_PATH", "Local video path required", null)
                return@setMethodCallHandler
            }

            executor.execute {
                try {
                    val file = checkedLocalFile(appContext, path)
                    val levels = analyze(file)
                    main.post { result.success(levels) }
                } catch (error: Exception) {
                    main.post {
                        result.error(
                            "AUDIO_ANALYSIS_FAILED",
                            "Local audio analysis unavailable",
                            null
                        )
                    }
                }
            }
        }
    }

    private fun checkedLocalFile(context: Context, input: String): File {
        val file = File(input).canonicalFile
        val allowed = listOfNotNull(
            context.filesDir,
            context.cacheDir,
            context.externalCacheDir,
            context.getExternalFilesDir(null)
        )

        if (!allowed.any { dir ->
                file.path.startsWith(dir.canonicalPath + File.separator)
            }) {
            throw SecurityException("File is outside app storage")
        }

        if (!file.isFile || file.length() <= 0 || file.length() > MAX_BYTES) {
            throw IllegalArgumentException("Invalid local media size")
        }
        return file
    }

    private fun analyze(file: File): List<Double> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var started = false

        try {
            extractor.setDataSource(file.absolutePath)

            var audioTrack = -1
            var format: MediaFormat? = null

            for (index in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(index)
                val mime = candidate.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrack = index
                    format = candidate
                    break
                }
            }

            if (audioTrack < 0 || format == null) return emptyList()

            val mime = format.getString(MediaFormat.KEY_MIME)
                ?: return emptyList()

            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION)
            } else {
                60_000_000L
            }

            val windows = ((durationUs.coerceAtLeast(1L) + WINDOW_US - 1L) /
                WINDOW_US).toInt().coerceIn(1, MAX_WINDOWS)

            val sums = DoubleArray(windows)
            val counts = LongArray(windows)

            extractor.selectTrack(audioTrack)
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()
            started = true

            val info = MediaCodec.BufferInfo()
            val startTime = System.nanoTime()
            var inputDone = false
            var outputDone = false
            var outputEncoding = AudioFormat.ENCODING_PCM_16BIT
            var iterations = 0

            while (!outputDone &&
                iterations++ < 200000 &&
                System.nanoTime() - startTime < TIME_LIMIT_NS) {

                if (!inputDone) {
                    val index = codec.dequeueInputBuffer(10_000)
                    if (index >= 0) {
                        val input = codec.getInputBuffer(index)
                            ?: throw IllegalStateException("Input unavailable")
                        input.clear()
                        val size = extractor.readSampleData(input, 0)

                        if (size < 0 ||
                            extractor.sampleTime >= 60_000_000L) {
                            codec.queueInputBuffer(
                                index, 0, 0, 0L,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(
                                index, 0, size,
                                extractor.sampleTime.coerceAtLeast(0L), 0
                            )
                            extractor.advance()
                        }
                    }
                }

                when (val index = codec.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val output = codec.outputFormat
                        outputEncoding =
                            if (output.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                                output.getInteger(MediaFormat.KEY_PCM_ENCODING)
                            } else {
                                AudioFormat.ENCODING_PCM_16BIT
                            }
                    }
                    else -> {
                        if (index >= 0) {
                            if (info.size > 0) {
                                val target = (
                                    info.presentationTimeUs / WINDOW_US
                                ).toInt()

                                if (target in 0 until windows) {
                                    val buffer = codec.getOutputBuffer(index)
                                    if (buffer != null) {
                                        buffer.order(ByteOrder.nativeOrder())
                                        buffer.position(info.offset)
                                        buffer.limit(info.offset + info.size)

                                        if (outputEncoding ==
                                            AudioFormat.ENCODING_PCM_FLOAT) {
                                            while (buffer.remaining() >= 4) {
                                                val sample = buffer.getFloat()
                                                if (sample.isFinite()) {
                                                    val value = sample.toDouble()
                                                    sums[target] += value * value
                                                    counts[target]++
                                                }
                                            }
                                        } else if (outputEncoding ==
                                            AudioFormat.ENCODING_PCM_16BIT) {
                                            while (buffer.remaining() >= 2) {
                                                val value =
                                                    buffer.getShort() / 32768.0
                                                sums[target] += value * value
                                                counts[target]++
                                            }
                                        }
                                    }
                                }
                            }

                            outputDone =
                                info.flags and
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            codec.releaseOutputBuffer(index, false)
                        }
                    }
                }
            }

            if (!outputDone) {
                throw IllegalStateException("Audio decoder timed out")
            }

            return List(windows) { index ->
                if (counts[index] <= 0L) {
                    0.0
                } else {
                    sqrt(sums[index] / counts[index])
                        .coerceIn(0.0, 1.0)
                }
            }
        } finally {
            if (codec != null) {
                if (started) {
                    try { codec.stop() } catch (_: Exception) {}
                }
                try { codec.release() } catch (_: Exception) {}
            }
            try { extractor.release() } catch (_: Exception) {}
        }
    }
}