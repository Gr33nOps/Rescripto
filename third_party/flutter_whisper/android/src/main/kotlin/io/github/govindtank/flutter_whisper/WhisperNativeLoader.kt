package io.github.govindtank.flutter_whisper

import android.content.Context
import java.io.File

/**
 * Loads the voice JNI library from Android's extracted native-library
 * directory.  Using explicit paths avoids relying on APK zip lookup and makes
 * the same load path serve both the preflight and model initialization.
 */
internal object WhisperNativeLoader {
    data class LoadResult(
        val loaded: Boolean,
        val stage: String,
        val detail: String? = null,
    )

    @Volatile
    private var isLoaded = false

    @Synchronized
    fun ensureLoaded(context: Context): LoadResult {
        if (isLoaded) return LoadResult(loaded = true, stage = "ready")

        val libraryDir = context.applicationInfo.nativeLibraryDir.orEmpty()
        if (libraryDir.isBlank()) {
            return LoadResult(false, "native_library_dir", "Android did not provide a native library directory.")
        }

        val cxxLibrary = File(libraryDir, "libc++_shared.so")
        val whisperLibrary = File(libraryDir, "libwhisper.so")
        if (!cxxLibrary.isFile) {
            return LoadResult(false, "c++_shared", "The packaged libc++_shared.so file is missing.")
        }
        if (!whisperLibrary.isFile) {
            return LoadResult(false, "whisper", "The packaged libwhisper.so file is missing.")
        }

        load(cxxLibrary, "c++_shared")?.let { return it }
        load(whisperLibrary, "whisper")?.let { return it }

        isLoaded = true
        return LoadResult(loaded = true, stage = "ready")
    }

    private fun load(library: File, stage: String): LoadResult? = try {
        System.load(library.absolutePath)
        null
    } catch (error: UnsatisfiedLinkError) {
        // Android can report this when the same app class loader has already
        // loaded this exact file. That state is safe and needs no second load.
        if (error.message.orEmpty().contains("already loaded")) {
            null
        } else {
            LoadResult(false, stage, sanitize(error.message))
        }
    }

    private fun sanitize(detail: String?): String {
        if (detail.isNullOrBlank()) return "Android did not provide linker details."
        return detail.replace(Regex("/data/[^ ]+"), "<app-native-path>").take(300)
    }
}
