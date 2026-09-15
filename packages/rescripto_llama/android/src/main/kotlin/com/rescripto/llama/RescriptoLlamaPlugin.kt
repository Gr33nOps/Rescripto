package com.rescripto.llama

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Method-channel host for [LlamaNative].
 *
 * Every native call except cancellation runs on one worker thread, in the
 * order Dart made the calls. That single thread is the only locking the
 * native side relies on. Cancellation skips the queue on purpose: it only
 * flips an atomic value that the running generation polls.
 */
class RescriptoLlamaPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var worker: ExecutorService? = null
    private val mainThread = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "rescripto-llama").apply { isDaemon = true }
        }
        channel = MethodChannel(binding.binaryMessenger, "rescripto_llama").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        LlamaNative.cancelAll()
        worker?.let { executor ->
            executor.execute {
                if (LlamaNative.isReady) LlamaNative.nativeUnloadModel()
            }
            executor.shutdown()
        }
        worker = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> loadModel(call, result)
            "unloadModel" -> runOnWorker(result) {
                if (LlamaNative.isReady) LlamaNative.nativeUnloadModel()
                reply(result, null)
            }
            "generate" -> generate(call, result)
            "cancel" -> {
                val upToId = call.argument<Number>("upToId")?.toLong() ?: Long.MAX_VALUE
                LlamaNative.cancelUpTo(upToId)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun loadModel(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("BAD_ARGUMENTS", "A model path is required.", null)
            return
        }
        val threads = call.argument<Number>("threads")?.toInt() ?: 4
        val contextSize = call.argument<Number>("contextSize")?.toInt() ?: 2048
        val batchSize = call.argument<Number>("batchSize")?.toInt() ?: 512
        val context = appContext

        runOnWorker(result) {
            val setupError = if (context == null) {
                LlamaNative.SetupError("NATIVE_LIBRARY_UNAVAILABLE", "The plugin is not attached.")
            } else {
                LlamaNative.ensureReady(context)
            }
            if (setupError != null) {
                reply(result, failure(setupError.code, setupError.message))
                return@runOnWorker
            }
            val loadError = LlamaNative.nativeLoadModel(
                path,
                threads.coerceIn(1, 16),
                contextSize.coerceAtLeast(256),
                batchSize.coerceIn(32, 4096),
            )
            reply(
                result,
                if (loadError == null) mapOf("ok" to true) else failure("MODEL_LOAD_FAILED", loadError),
            )
        }
    }

    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")?.toLong()
        val prompt = call.argument<String>("prompt")
        if (id == null || prompt == null) {
            result.error("BAD_ARGUMENTS", "Generation needs an id and a prompt.", null)
            return
        }
        val temperature = call.argument<Number>("temperature")?.toFloat() ?: 0.7f
        val topP = call.argument<Number>("topP")?.toFloat() ?: 0.95f
        val topK = call.argument<Number>("topK")?.toInt() ?: 40
        val repeatPenalty = call.argument<Number>("repeatPenalty")?.toFloat() ?: 1.1f
        val maxTokens = call.argument<Number>("maxTokens")?.toInt() ?: 512
        val stops = call.argument<List<String>>("stopSequences")?.toTypedArray() ?: emptyArray()

        val executor = worker
        if (executor == null) {
            result.error("NATIVE_LIBRARY_UNAVAILABLE", "The plugin is not attached.", null)
            return
        }
        // Acknowledge straight away; text, completion and errors all arrive
        // as separate calls tagged with this id.
        result.success(null)
        executor.execute {
            if (!LlamaNative.isReady) {
                send("onError", mapOf("id" to id, "code" to "MODEL_NOT_LOADED", "message" to "No model is loaded."))
                return@execute
            }
            val sink = LlamaNative.TextSink { bytes ->
                send("onText", mapOf("id" to id, "text" to String(bytes, Charsets.UTF_8)))
            }
            val error = try {
                LlamaNative.nativeGenerate(
                    id, prompt, temperature, topP, topK, repeatPenalty, maxTokens, stops, sink,
                )
            } catch (t: Throwable) {
                "GENERATION_FAILED|${t.message ?: t.javaClass.simpleName}"
            }
            if (error == null) {
                send("onDone", mapOf("id" to id))
            } else {
                val code = error.substringBefore('|', "GENERATION_FAILED")
                val message = error.substringAfter('|', error)
                send("onError", mapOf("id" to id, "code" to code, "message" to message))
            }
        }
    }

    private fun runOnWorker(result: MethodChannel.Result, body: () -> Unit) {
        val executor = worker
        if (executor == null) {
            result.error("NATIVE_LIBRARY_UNAVAILABLE", "The plugin is not attached.", null)
            return
        }
        executor.execute {
            try {
                body()
            } catch (t: Throwable) {
                mainThread.post {
                    result.error("NATIVE_FAILURE", t.message ?: t.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun reply(result: MethodChannel.Result, value: Any?) {
        mainThread.post { result.success(value) }
    }

    private fun send(method: String, arguments: Map<String, Any?>) {
        mainThread.post { channel?.invokeMethod(method, arguments) }
    }

    private fun failure(code: String, message: String) =
        mapOf("ok" to false, "code" to code, "message" to message)
}
