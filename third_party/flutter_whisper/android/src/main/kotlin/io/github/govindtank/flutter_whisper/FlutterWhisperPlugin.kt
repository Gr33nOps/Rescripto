package io.github.govindtank.flutter_whisper

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AudioEffect
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.coroutines.cancellation.CancellationException
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

class FlutterWhisperPlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var whisperContext: WhisperContext? = null

    // Transcribe runs on a worker thread so the UI never freezes.
    private val transcribeExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Recording state (AudioRecord → 16 kHz mono PCM16 WAV).
    private val recordExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var recording = false
    private var recordFile: File? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "flutter_whisper")
        channel?.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        stopRecordingInternal()
        whisperContext?.close()
        whisperContext = null
        transcribeExecutor.shutdownNow()
        recordExecutor.shutdownNow()
        context = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "checkSupport" -> checkSupport(result)
            "initialize" -> initialize(call, result)
            "transcribeFile" -> transcribeFile(call, result)
            "transcribePcm" -> transcribePcm(call, result)
            "startRecording" -> startRecording(result)
            "stopRecording" -> stopRecording(result)
            "cancel" -> cancel(result)
            "dispose" -> dispose(result)
            else -> result.notImplemented()
        }
    }

    /** Checks native loading before a caller downloads a large model file. */
    private fun checkSupport(result: Result) {
        val abis = Build.SUPPORTED_ABIS.toList()
        val apiLevel = Build.VERSION.SDK_INT
        val libraryDir = context?.applicationInfo?.nativeLibraryDir.orEmpty()
        if (!abis.contains("arm64-v8a")) {
            result.success(
                supportResult(
                    supported = false,
                    code = "ABI_UNSUPPORTED",
                    message = "On-device voice requires a 64-bit ARM Android system.",
                    stage = "abi",
                    abis = abis,
                    apiLevel = apiLevel,
                    libraryDir = libraryDir,
                ),
            )
            return
        }

        var stage = "c++_shared"
        try {
            System.loadLibrary("c++_shared")
            stage = "whisper"
            System.loadLibrary("whisper")
            stage = "jni_smoke_test"
            if (!nativeSmokeTest()) {
                result.success(
                    supportResult(
                        supported = false,
                        code = "JNI_SMOKE_TEST_FAILED",
                        message = "The voice engine loaded but failed its native self-check.",
                        stage = stage,
                        abis = abis,
                        apiLevel = apiLevel,
                        libraryDir = libraryDir,
                    ),
                )
                return
            }
            result.success(
                supportResult(
                    supported = true,
                    stage = "ready",
                    abis = abis,
                    apiLevel = apiLevel,
                    libraryDir = libraryDir,
                ),
            )
        } catch (e: UnsatisfiedLinkError) {
            Log.e("FlutterWhisper", "Native whisper library could not load", e)
            result.success(
                supportResult(
                    supported = false,
                    code = "NATIVE_LOAD_FAILED",
                    message = "The on-device voice library could not load at $stage.",
                    stage = stage,
                    detail = sanitizeLinkerDetail(e.message),
                    abis = abis,
                    apiLevel = apiLevel,
                    libraryDir = libraryDir,
                ),
            )
        } catch (e: Throwable) {
            Log.e("FlutterWhisper", "Native whisper self-check failed", e)
            result.success(
                supportResult(
                    supported = false,
                    code = "NATIVE_CHECK_FAILED",
                    message = "The on-device voice self-check failed at $stage.",
                    stage = stage,
                    detail = e.message.orEmpty().take(300),
                    abis = abis,
                    apiLevel = apiLevel,
                    libraryDir = libraryDir,
                ),
            )
        }
    }

    private fun supportResult(
        supported: Boolean,
        stage: String,
        abis: List<String>,
        apiLevel: Int,
        libraryDir: String,
        code: String? = null,
        message: String? = null,
        detail: String? = null,
    ): Map<String, Any?> = mapOf(
        "supported" to supported,
        "code" to code,
        "message" to message,
        "stage" to stage,
        "abis" to abis,
        "apiLevel" to apiLevel,
        "libraryPath" to libraryDir,
        "detail" to detail,
    )

    private fun sanitizeLinkerDetail(detail: String?): String {
        if (detail.isNullOrBlank()) return "Android did not provide linker details."
        return detail.replace(Regex("/data/[^ ]+"), "<app-native-path>").take(300)
    }

    private fun initialize(call: MethodCall, result: Result) {
        val modelPath = call.argument<String>("modelPath") ?: return result.error("INVALID_ARGS", "modelPath required", null)

        transcribeExecutor.execute {
            try {
                val modelFile = File(modelPath)
                if (!modelFile.exists() && copyModelFromAssets(modelPath) == null) {
                    mainHandler.post {
                        result.error("MODEL_NOT_FOUND", "Model file not found", null)
                    }
                    return@execute
                }

                whisperContext?.close()
                whisperContext = null
                val newContext = WhisperContext(modelFile.absolutePath) { percent ->
                    mainHandler.post { channel?.invokeMethod("transcribeProgress", percent) }
                }
                whisperContext = newContext
                mainHandler.post { result.success(true) }
            } catch (e: UnsatisfiedLinkError) {
                Log.e("FlutterWhisper", "Native whisper library missing", e)
                mainHandler.post {
                    result.error("NATIVE_LOAD_FAILED", "whisper.cpp native library could not load", null)
                }
            } catch (e: Exception) {
                Log.e("FlutterWhisper", "Initialize failed", e)
                mainHandler.post {
                    result.error("INITIALIZATION_FAILED", e.message, null)
                }
            }
        }
    }

    private fun transcribeFile(call: MethodCall, result: Result) {
        val audioPath = call.argument<String>("audioPath") ?: return result.error("INVALID_ARGS", "audioPath required", null)
        val options = call.argument<Map<String, Any>>("options") ?: mutableMapOf()
        val language = options["language"] as? String ?: ""
        val threads = (options["threads"] as? Number)?.toInt() ?: 0
        val translate = options["translate"] as? Boolean ?: false
        val temperature = (options["temperature"] as? Number)?.toFloat() ?: 0.0f
        val suppressBlank = options["suppressBlank"] as? Boolean ?: true
        val wordTimestamps = options["wordTimestamps"] as? Boolean ?: false

        val ctx = whisperContext ?: return result.error("NOT_INITIALIZED", "Call initialize first", null)

        transcribeExecutor.execute {
            try {
                val transcriptionResult = ctx.transcribe(
                    audioPath,
                    language,
                    threads,
                    translate,
                    temperature,
                    suppressBlank,
                    wordTimestamps
                )

                val segmentsList = mutableListOf<Map<String, Any>>()
                for (segment in transcriptionResult.segments) {
                    segmentsList.add(
                        mapOf(
                            "text" to segment.text,
                            "start" to segment.start,
                            "end" to segment.end
                        )
                    )
                }

                val resultMap = mutableMapOf<String, Any>()
                resultMap["text"] = transcriptionResult.fullText
                resultMap["segments"] = segmentsList
                resultMap["language"] = transcriptionResult.language
                resultMap["duration"] = transcriptionResult.duration

                mainHandler.post { result.success(resultMap) }
            } catch (e: CancellationException) {
                mainHandler.post { result.error("TRANSCRIPTION_CANCELLED", "cancelled", null) }
            } catch (e: Exception) {
                Log.e("FlutterWhisper", "Transcription failed", e)
                mainHandler.post { result.error("TRANSCRIPTION_FAILED", e.message, null) }
            }
        }
    }

    private fun transcribePcm(call: MethodCall, result: Result) {
        result.error("NOT_IMPLEMENTED", "PCM transcription not yet implemented — use startRecording/stopRecording", null)
    }

    private fun startRecording(result: Result) {
        if (recording) return result.error("ALREADY_RECORDING", "Already recording", null)
        val ctx = context ?: return result.error("NO_CONTEXT", "Plugin detached", null)

        val sampleRate = 16000
        val bufSize = AudioRecord.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        if (bufSize <= 0) return result.error("MIC_UNAVAILABLE", "No usable audio buffer", null)

        // VOICE_RECOGNITION asks the platform for an unprocessed, AGC-friendly
        // capture path tuned for speech. Plain MIC goes through the camcorder/
        // call tuning on many devices, which is what makes dictation come back
        // muffled or clipped. Fall back to MIC where it isn't offered.
        val record = openRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, sampleRate, bufSize)
            ?: openRecord(MediaRecorder.AudioSource.MIC, sampleRate, bufSize)
            ?: return result.error("MIC_UNAVAILABLE", "Microphone not available", null)

        val effects = attachVoiceProcessing(record.audioSessionId)

        val dir = File(ctx.filesDir, "recordings").apply { mkdirs() }
        val file = File(dir, "rec_${System.currentTimeMillis()}.wav")
        val fos = try {
            FileOutputStream(file).also { writeWavHeader(it, 0) }
        } catch (e: IOException) {
            releaseEffects(effects)
            record.release()
            return result.error("WRITE_FAILED", e.message, null)
        }

        recording = true
        recordFile = file
        record.startRecording()

        recordExecutor.execute {
            // Without an audio-priority thread the read loop loses buffers under
            // load, and the dropouts land in the WAV as clicks and swallowed
            // syllables that whisper then transcribes as garbage.
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            try {
                val buf = ByteArray(bufSize)
                while (recording) {
                    val n = record.read(buf, 0, buf.size)
                    if (n > 0) {
                        fos.write(buf, 0, n)
                    } else if (n < 0) {
                        Log.e("FlutterWhisper", "AudioRecord.read error $n")
                        break
                    }
                }
            } catch (e: Exception) {
                Log.e("FlutterWhisper", "Recording loop failed", e)
            } finally {
                try { record.stop() } catch (_: Exception) {}
                releaseEffects(effects)
                record.release()
                try {
                    fos.flush()
                    fos.close()
                    patchWavHeader(file)
                } catch (e: IOException) {
                    Log.e("FlutterWhisper", "Finalize wav failed", e)
                }
            }
        }
        result.success(true)
    }

    /** Opens an [AudioRecord] on [source], or null if the device refuses it. */
    private fun openRecord(source: Int, sampleRate: Int, bufSize: Int): AudioRecord? {
        val record = try {
            // Four times the minimum keeps a comfortable margin so a scheduling
            // hiccup does not overwrite unread audio.
            AudioRecord(
                source, sampleRate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize * 4
            )
        } catch (e: Exception) {
            Log.w("FlutterWhisper", "AudioRecord source $source unavailable", e)
            return null
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            return null
        }
        return record
    }

    /**
     * Enables the platform's noise suppressor and automatic gain control on the
     * capture session where the hardware offers them. Both measurably improve
     * whisper's accuracy on phone-quality dictation.
     */
    private fun attachVoiceProcessing(sessionId: Int): List<AudioEffect> {
        val effects = mutableListOf<AudioEffect>()
        try {
            if (NoiseSuppressor.isAvailable()) {
                NoiseSuppressor.create(sessionId)?.also {
                    it.enabled = true
                    effects.add(it)
                }
            }
            if (AutomaticGainControl.isAvailable()) {
                AutomaticGainControl.create(sessionId)?.also {
                    it.enabled = true
                    effects.add(it)
                }
            }
        } catch (e: Exception) {
            Log.w("FlutterWhisper", "Voice processing unavailable", e)
        }
        return effects
    }

    private fun releaseEffects(effects: List<AudioEffect>) {
        for (effect in effects) {
            try { effect.release() } catch (_: Exception) {}
        }
    }

    private fun stopRecording(result: Result) {
        if (!recording) return result.error("NOT_RECORDING", "Not recording", null)
        recording = false
        // Ordered after the recording loop on the same executor: the loop has
        // flushed + patched the header by the time we resolve with the path.
        recordExecutor.execute {
            mainHandler.post { result.success(recordFile?.absolutePath) }
        }
    }

    private fun stopRecordingInternal() {
        if (recording) {
            recording = false
        }
    }

    private fun cancel(result: Result) {
        whisperContext?.cancel()
        result.success(true)
    }

    private fun dispose(result: Result) {
        stopRecordingInternal()
        transcribeExecutor.execute {
            whisperContext?.close()
            whisperContext = null
            mainHandler.post { result.success(true) }
        }
    }

    private fun copyModelFromAssets(modelPath: String): String? {
        val context = context ?: return null
        val file = File(modelPath)
        file.parentFile?.mkdirs()

        try {
            val fileName = file.name
            val inputStream = context.assets.open("models/$fileName")
            val outputStream = FileOutputStream(file)
            inputStream.copyTo(outputStream)
            inputStream.close()
            outputStream.close()
            return file.absolutePath
        } catch (e: IOException) {
            Log.e("FlutterWhisper", "Failed to copy model from assets", e)
            return null
        }
    }

    private external fun nativeSmokeTest(): Boolean

    companion object {
        /** Writes a 44-byte PCM WAV header (16 kHz mono 16-bit). */
        fun writeWavHeader(fos: FileOutputStream, dataSize: Int) {
            val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            h.put("RIFF".toByteArray()); h.putInt(36 + dataSize)
            h.put("WAVE".toByteArray())
            h.put("fmt ".toByteArray()); h.putInt(16)
            h.putShort(1); h.putShort(1)
            h.putInt(16000); h.putInt(32000)
            h.putShort(2); h.putShort(16)
            h.put("data".toByteArray()); h.putInt(dataSize)
            fos.write(h.array())
        }

        /** Rewrites RIFF/data sizes now that PCM is known. */
        fun patchWavHeader(file: File) {
            val dataSize = (file.length() - 44).toInt().coerceAtLeast(0)
            RandomAccessFile(file, "rw").use { raf ->
                raf.seek(4); writeLittleEndianInt(raf, 36 + dataSize)
                raf.seek(40); writeLittleEndianInt(raf, dataSize)
            }
        }

        private fun writeLittleEndianInt(raf: RandomAccessFile, value: Int) {
            raf.write(value and 0xff)
            raf.write((value ushr 8) and 0xff)
            raf.write((value ushr 16) and 0xff)
            raf.write((value ushr 24) and 0xff)
        }
    }
}
