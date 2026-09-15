package com.rescripto.llama

import android.content.Context

/**
 * JNI surface of `librescripto_llama.so`.
 *
 * Everything except [cancelUpTo] and [cancelAll] must be called from the
 * plugin's single worker thread.
 */
internal object LlamaNative {
    data class SetupError(val code: String, val message: String)

    /** Receives generated text as complete UTF-8 sequences. Called from JNI. */
    fun interface TextSink {
        fun onText(bytes: ByteArray)
    }

    @Volatile
    var isReady = false
        private set

    private var setupError: SetupError? = null

    /**
     * Loads the JNI library and registers the best CPU backend for this
     * phone. Runs once; later calls return the first outcome.
     */
    @Synchronized
    fun ensureReady(context: Context): SetupError? {
        if (isReady) return null
        setupError?.let { return it }

        try {
            System.loadLibrary("rescripto_llama")
        } catch (error: UnsatisfiedLinkError) {
            return remember(SetupError("NATIVE_LIBRARY_UNAVAILABLE", sanitize(error.message)))
        }

        val libraryDir = context.applicationInfo.nativeLibraryDir.orEmpty()
        val backendError = nativeInitBackends(libraryDir)
        if (backendError != null) {
            return remember(SetupError("CPU_BACKEND_UNAVAILABLE", backendError))
        }
        isReady = true
        return null
    }

    fun cancelUpTo(id: Long) {
        if (isReady) nativeCancelUpTo(id)
    }

    fun cancelAll() = cancelUpTo(Long.MAX_VALUE)

    private fun remember(error: SetupError): SetupError {
        setupError = error
        return error
    }

    private fun sanitize(detail: String?): String {
        if (detail.isNullOrBlank()) return "Android did not report why the native library failed to load."
        return detail.replace(Regex("/data/[^ ]+"), "<app-native-path>").take(300)
    }

    /** Returns null on success, otherwise a readable reason. */
    private external fun nativeInitBackends(libraryDir: String): String?

    /** Returns null on success, otherwise a readable reason. */
    external fun nativeLoadModel(path: String, threads: Int, contextSize: Int, batchSize: Int): String?

    external fun nativeUnloadModel()

    /**
     * Runs one generation to completion, cancellation, or failure. Returns
     * null unless it failed, in which case the value is `CODE|message`.
     */
    external fun nativeGenerate(
        id: Long,
        prompt: String,
        temperature: Float,
        topP: Float,
        topK: Int,
        repeatPenalty: Float,
        maxTokens: Int,
        stopSequences: Array<String>,
        sink: TextSink,
    ): String?

    private external fun nativeCancelUpTo(id: Long)
}
