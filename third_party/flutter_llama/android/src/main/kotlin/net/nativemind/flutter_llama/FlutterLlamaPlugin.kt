package net.nativemind.flutter_llama

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * FlutterLlamaPlugin - плагин для работы с llama.cpp моделями на Android
 * 
 * Поддерживает:
 * - Загрузку GGUF моделей
 * - GPU ускорение через Vulkan/OpenCL
 * - Потоковую и обычную генерацию
 */
class FlutterLlamaPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val TAG = "FlutterLlama"
        private const val CHANNEL_NAME = "flutter_llama"
        private const val EVENT_CHANNEL_NAME = "flutter_llama/stream"

        private val NATIVE_LIBRARIES_LOADED: Boolean = try {
                // Load llama.cpp libraries in correct order
                System.loadLibrary("c++_shared")
                System.loadLibrary("ggml")
                System.loadLibrary("ggml-base")
                System.loadLibrary("llama")
                System.loadLibrary("flutter_llama_bridge")
                Log.d(TAG, "Native libraries loaded successfully")
                true
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load native libraries: ${e.message}")
                false
        }
    }

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    
    private var modelLoaded = false
    private var modelPath: String? = null
    private var nativeLibraryDir: String = ""
    @Volatile private var shouldStop = false

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        nativeLibraryDir = flutterPluginBinding.applicationContext.applicationInfo.nativeLibraryDir
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)
        
        Log.d(TAG, "Plugin attached to engine")
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "loadModel" -> loadModel(call, result)
            "generate" -> generate(call, result)
            "generateStream" -> generateStream(call, result)
            "unloadModel" -> unloadModel(result)
            "getModelInfo" -> getModelInfo(result)
            "stopGeneration" -> stopGeneration(result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        shouldStop = true
        if (NATIVE_LIBRARIES_LOADED) nativeStopGeneration()
        executor.execute {
            if (modelLoaded && NATIVE_LIBRARIES_LOADED) nativeFreeModel()
            modelLoaded = false
            modelPath = null
        }
        executor.shutdown()
    }

    // MARK: - EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        shouldStop = true
        if (NATIVE_LIBRARIES_LOADED) nativeStopGeneration()
    }

    // MARK: - Load Model

    private fun loadModel(call: MethodCall, result: Result) {
        if (!NATIVE_LIBRARIES_LOADED) {
            result.error("NATIVE_UNAVAILABLE", "llama native libraries are unavailable on this device ABI", null)
            return
        }
        executor.execute {
            try {
                val modelPath = call.argument<String>("modelPath")
                if (modelPath == null) {
                    mainHandler.post {
                        result.error("INVALID_ARGS", "Missing modelPath", null)
                    }
                    return@execute
                }

                val nThreads = call.argument<Int>("nThreads") ?: 4
                val nGpuLayers = call.argument<Int>("nGpuLayers") ?: 0
                val contextSize = call.argument<Int>("contextSize") ?: 2048
                val batchSize = call.argument<Int>("batchSize") ?: 512
                val useGpu = call.argument<Boolean>("useGpu") ?: true
                val verbose = call.argument<Boolean>("verbose") ?: false

                // Check if model file exists
                val file = File(modelPath)
                if (!file.exists()) {
                    mainHandler.post {
                        result.error("MODEL_NOT_FOUND", "Model file not found: $modelPath", null)
                    }
                    return@execute
                }

                this.modelPath = modelPath

                // Initialize model through JNI
                val success = nativeInitModel(
                    modelPath,
                    nativeLibraryDir,
                    nThreads,
                    nGpuLayers,
                    contextSize,
                    batchSize,
                    useGpu,
                    verbose
                )

                modelLoaded = success

                val reason = if (success) "" else nativeGetLastError()
                val errorCode = if (success) "" else nativeGetLastErrorCode()

                mainHandler.post {
                    if (success) {
                        Log.d(TAG, "Model loaded: $modelPath")
                        Log.d(TAG, "GPU layers: $nGpuLayers, threads: $nThreads, context: $contextSize")
                        result.success(true)
                    } else {
                        result.error(
                            errorCode.ifBlank { "INIT_FAILED" },
                            reason.ifBlank { "Failed to initialize model" },
                            null,
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error loading model", e)
                mainHandler.post {
                    result.error("EXCEPTION", "Error loading model: ${e.message}", null)
                }
            }
        }
    }

    // MARK: - Generate (blocking)

    private fun generate(call: MethodCall, result: Result) {
        if (!modelLoaded) {
            result.error("MODEL_NOT_LOADED", "Model not loaded", null)
            return
        }

        executor.execute {
            try {
                val prompt = call.argument<String>("prompt")
                if (prompt == null) {
                    mainHandler.post {
                        result.error("INVALID_ARGS", "Missing prompt", null)
                    }
                    return@execute
                }

                val temperature = call.argument<Double>("temperature")?.toFloat() ?: 0.8f
                val topP = call.argument<Double>("topP")?.toFloat() ?: 0.95f
                val topK = call.argument<Int>("topK") ?: 40
                val maxTokens = call.argument<Int>("maxTokens") ?: 512
                val repeatPenalty = call.argument<Double>("repeatPenalty")?.toFloat() ?: 1.1f
                val stopSequences = call.argument<List<String>>("stopSequences") ?: emptyList()

                shouldStop = false
                val startTime = System.currentTimeMillis()

                // Generate through JNI
                val generationResult = nativeGenerate(
                    prompt,
                    temperature,
                    topP,
                    topK,
                    maxTokens,
                    repeatPenalty
                )

                val generationTime = System.currentTimeMillis() - startTime

                mainHandler.post {
                    if (generationResult != null) {
                        val responseText = trimAtStop(generationResult.text, stopSequences)
                        val response = hashMapOf(
                            "text" to responseText,
                            "tokensGenerated" to generationResult.tokensGenerated,
                            "generationTimeMs" to generationTime
                        )
                        Log.d(TAG, "Generated: ${generationResult.tokensGenerated} tokens in ${generationTime}ms")
                        result.success(response)
                    } else {
                        result.error(
                            "GENERATION_FAILED",
                            nativeGetLastError().ifBlank { "Failed to generate response" },
                            null,
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error generating", e)
                mainHandler.post {
                    result.error("EXCEPTION", "Error generating: ${e.message}", null)
                }
            }
        }
    }

    // MARK: - Generate Stream

    private fun generateStream(call: MethodCall, result: Result) {
        if (!modelLoaded) {
            result.error("MODEL_NOT_LOADED", "Model not loaded", null)
            return
        }

        val sink = eventSink
        if (sink == null) {
            result.error("NO_EVENT_SINK", "Event channel not initialized", null)
            return
        }

        executor.execute {
            try {
                val prompt = call.argument<String>("prompt")
                if (prompt == null) {
                    mainHandler.post {
                        result.error("INVALID_ARGS", "Missing prompt", null)
                    }
                    return@execute
                }

                val temperature = call.argument<Double>("temperature")?.toFloat() ?: 0.8f
                val topP = call.argument<Double>("topP")?.toFloat() ?: 0.95f
                val topK = call.argument<Int>("topK") ?: 40
                val maxTokens = call.argument<Int>("maxTokens") ?: 512
                val repeatPenalty = call.argument<Double>("repeatPenalty")?.toFloat() ?: 1.1f
                val stopSequences = call.argument<List<String>>("stopSequences") ?: emptyList()

                shouldStop = false

                // Initialize streaming generation
                val initialized = nativeGenerateStreamInit(
                    prompt, temperature, topP, topK, maxTokens, repeatPenalty
                )
                if (!initialized) {
                    val reason = nativeGetLastError().ifBlank {
                        "Stream initialization failed"
                    }
                    mainHandler.post {
                        sink.error("GENERATION_FAILED", reason, null)
                        result.error("GENERATION_FAILED", reason, null)
                    }
                    return@execute
                }

                // Stream tokens one by one
                val pending = StringBuilder()
                val tailLength = (stopSequences.maxOfOrNull { it.length } ?: 0).coerceAtLeast(1) - 1
                var stoppedAtSequence = false
                while (!shouldStop) {
                    val token = nativeGenerateStreamNext()
                    if (token != null) {
                        pending.append(token)
                        val stopIndex = firstStopIndex(pending, stopSequences)
                        if (stopIndex >= 0) {
                            val safe = pending.substring(0, stopIndex)
                            if (safe.isNotEmpty()) mainHandler.post { sink.success(safe) }
                            stoppedAtSequence = true
                            nativeStopGeneration()
                            break
                        }
                        val safeLength = pending.length - tailLength
                        if (safeLength > 0) {
                            val safe = pending.substring(0, safeLength)
                            pending.delete(0, safeLength)
                            mainHandler.post { sink.success(safe) }
                        }
                    } else {
                        break
                    }
                }
                if (!stoppedAtSequence && pending.isNotEmpty()) {
                    val safe = pending.toString()
                    mainHandler.post { sink.success(safe) }
                }

                val generationError = nativeGetLastError()
                nativeGenerateStreamEnd()

                mainHandler.post {
                    if (generationError.isNotBlank() && !shouldStop && !stoppedAtSequence) {
                        sink.error("GENERATION_FAILED", generationError, null)
                        result.error("GENERATION_FAILED", generationError, null)
                    } else {
                        sink.endOfStream()
                        result.success(null)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error in streaming generation", e)
                mainHandler.post {
                    sink.error("EXCEPTION", "Error in streaming: ${e.message}", null)
                    result.error("EXCEPTION", "Error in streaming: ${e.message}", null)
                }
            }
        }
    }

    // MARK: - Unload Model

    private fun unloadModel(result: Result) {
        shouldStop = true
        if (NATIVE_LIBRARIES_LOADED) nativeStopGeneration()
        executor.execute {
            if (modelLoaded && NATIVE_LIBRARIES_LOADED) nativeFreeModel()
            modelLoaded = false
            modelPath = null
            Log.d(TAG, "Model unloaded")
            mainHandler.post { result.success(null) }
        }
    }

    // MARK: - Get Model Info

    private fun getModelInfo(result: Result) {
        if (!modelLoaded || modelPath == null) {
            result.success(null)
            return
        }

        try {
            val info = nativeGetModelInfo()
            if (info != null) {
                val infoMap = hashMapOf(
                    "modelPath" to modelPath!!,
                    "nParams" to info.nParams,
                    "nLayers" to info.nLayers,
                    "contextSize" to info.contextSize
                )
                result.success(infoMap)
            } else {
                result.success(null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting model info", e)
            result.success(null)
        }
    }

    // MARK: - Stop Generation

    private fun stopGeneration(result: Result) {
        shouldStop = true
        if (NATIVE_LIBRARIES_LOADED) nativeStopGeneration()
        result.success(null)
    }

    private fun trimAtStop(text: String, stopSequences: List<String>): String {
        val index = firstStopIndex(StringBuilder(text), stopSequences)
        return if (index >= 0) text.substring(0, index) else text
    }

    private fun firstStopIndex(text: CharSequence, stopSequences: List<String>): Int {
        var first = -1
        for (sequence in stopSequences) {
            if (sequence.isEmpty()) continue
            val index = text.indexOf(sequence)
            if (index >= 0 && (first < 0 || index < first)) first = index
        }
        return first
    }

    // MARK: - Native Methods (JNI)

    private external fun nativeInitModel(
        modelPath: String,
        nativeLibraryDir: String,
        nThreads: Int,
        nGpuLayers: Int,
        contextSize: Int,
        batchSize: Int,
        useGpu: Boolean,
        verbose: Boolean
    ): Boolean

    private external fun nativeGenerate(
        prompt: String,
        temperature: Float,
        topP: Float,
        topK: Int,
        maxTokens: Int,
        repeatPenalty: Float
    ): GenerationResult?

    private external fun nativeGenerateStreamInit(
        prompt: String,
        temperature: Float,
        topP: Float,
        topK: Int,
        maxTokens: Int,
        repeatPenalty: Float
    ): Boolean

    private external fun nativeGenerateStreamNext(): String?

    private external fun nativeGenerateStreamEnd()

    private external fun nativeGetModelInfo(): ModelInfo?

    /** Reason the last native init/generate failed, or "" if there was none. */
    private external fun nativeGetLastError(): String

    /** Stable platform-channel code for the last native failure. */
    private external fun nativeGetLastErrorCode(): String

    private external fun nativeFreeModel()

    private external fun nativeStopGeneration()

    // Data classes for JNI results
    data class GenerationResult(
        val text: String,
        val tokensGenerated: Int
    )

    data class ModelInfo(
        val nParams: Long,
        val nLayers: Int,
        val contextSize: Int
    )
}
