// JNI bridge: whisper.cpp → Kotlin (io.github.govindtank.flutter_whisper.WhisperContext)
//
// Protocol:
//   nativeInit       → jlong handle (0 on failure)
//   nativeTranscribe → JSON string:
//       {"text":"...","language":"en","duration":3.2,
//        "segments":[{"text":"...","start":0.0,"end":1.5}]}
//       or {"error":"..."} (including "cancelled")
//   nativeCancel     → sets abort flag; in-flight whisper_full stops at next
//                      segment boundary (abort callback)
//   nativeFree       → releases context + JNI global refs
//
// Progress: whisper_full_progress_callback fires Kotlin
// WhisperContext.onNativeProgress(int percent) on the calling thread.
#include <jni.h>
#include <android/log.h>
#include <atomic>
#include <exception>
#include <new>
#include <string>
#include <vector>
#include <sstream>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iterator>
#include <thread>

#include "whisper.h"

#define MA_NO_DEVICE_IO
#define MA_NO_THREADING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#define WHISPER_JNI_TAG "RescriptoWhisper"

// ---- JNI callback registry (single active context — see ponytail) ----
static JavaVM* g_vm = nullptr;
static jobject g_target = nullptr;        // global ref to WhisperContext
static jmethodID g_onProgress = nullptr;  // (I)V
static std::atomic<bool> g_abort{false};

extern "C" JNIEXPORT jboolean JNICALL
Java_io_github_govindtank_flutter_1whisper_FlutterWhisperPlugin_nativeSmokeTest(
    JNIEnv*, jobject) {
    const char* version = whisper_version();
    return (version != nullptr && version[0] != '\0') ? JNI_TRUE : JNI_FALSE;
}

static jstring utf8_to_jstring(JNIEnv* env, const std::string& input) {
    std::vector<jchar> output;
    output.reserve(input.size());
    for (size_t i = 0; i < input.size();) {
        const uint8_t first = static_cast<uint8_t>(input[i]);
        uint32_t codepoint = 0xFFFD;
        size_t count = 1;
        if (first < 0x80) {
            codepoint = first;
        } else if ((first & 0xE0) == 0xC0 && i + 1 < input.size()) {
            codepoint = ((first & 0x1F) << 6) |
                        (static_cast<uint8_t>(input[i + 1]) & 0x3F);
            count = 2;
        } else if ((first & 0xF0) == 0xE0 && i + 2 < input.size()) {
            codepoint = ((first & 0x0F) << 12) |
                        ((static_cast<uint8_t>(input[i + 1]) & 0x3F) << 6) |
                        (static_cast<uint8_t>(input[i + 2]) & 0x3F);
            count = 3;
        } else if ((first & 0xF8) == 0xF0 && i + 3 < input.size()) {
            codepoint = ((first & 0x07) << 18) |
                        ((static_cast<uint8_t>(input[i + 1]) & 0x3F) << 12) |
                        ((static_cast<uint8_t>(input[i + 2]) & 0x3F) << 6) |
                        (static_cast<uint8_t>(input[i + 3]) & 0x3F);
            count = 4;
        }
        i += count;
        if (codepoint <= 0xFFFF) {
            output.push_back(static_cast<jchar>(codepoint));
        } else {
            codepoint -= 0x10000;
            output.push_back(static_cast<jchar>(0xD800 + (codepoint >> 10)));
            output.push_back(static_cast<jchar>(0xDC00 + (codepoint & 0x3FF)));
        }
    }
    return env->NewString(output.data(), static_cast<jsize>(output.size()));
}

bool abort_cb(void* /*user_data*/) { return g_abort.load(); }

void progress_cb(whisper_context* /*ctx*/, whisper_state* /*state*/, int progress, void* /*user_data*/) {
    if (progress < 0 || progress > 100) return;
    JNIEnv* env = nullptr;
    if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        // Callback runs on the thread that called whisper_full (an executor
        // thread we attach here).
        g_vm->AttachCurrentThread(&env, nullptr);
    }
    if (env && g_target && g_onProgress) {
        env->CallVoidMethod(g_target, g_onProgress, static_cast<jint>(progress));
    }
}

// AudioRecord always writes a 16 kHz mono PCM16 WAV. Decode that small,
// well-defined format ourselves before falling back to miniaudio. Some Android
// devices expose a valid recording that miniaudio's stdio decoder cannot open,
// even though the same file decodes normally elsewhere.
static uint16_t read_le16(const unsigned char* p) {
    return static_cast<uint16_t>(p[0]) |
           (static_cast<uint16_t>(p[1]) << 8);
}

static uint32_t read_le32(const unsigned char* p) {
    return static_cast<uint32_t>(p[0]) |
           (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) |
           (static_cast<uint32_t>(p[3]) << 24);
}

static bool load_pcm16_wav_16k_mono(const std::string& path, std::vector<float>& out) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) return false;

    std::vector<unsigned char> bytes(
        (std::istreambuf_iterator<char>(stream)),
        std::istreambuf_iterator<char>());
    if (bytes.size() < 44 || std::memcmp(bytes.data(), "RIFF", 4) != 0 ||
        std::memcmp(bytes.data() + 8, "WAVE", 4) != 0) {
        return false;
    }

    uint16_t audio_format = 0;
    uint16_t channels = 0;
    uint16_t bits_per_sample = 0;
    uint32_t sample_rate = 0;
    const unsigned char* pcm = nullptr;
    size_t pcm_size = 0;

    size_t offset = 12;
    while (offset + 8 <= bytes.size()) {
        const unsigned char* chunk = bytes.data() + offset;
        const uint32_t chunk_size = read_le32(chunk + 4);
        const size_t data_offset = offset + 8;
        if (data_offset > bytes.size() || chunk_size > bytes.size() - data_offset) {
            return false;
        }
        if (std::memcmp(chunk, "fmt ", 4) == 0 && chunk_size >= 16) {
            audio_format = read_le16(bytes.data() + data_offset);
            channels = read_le16(bytes.data() + data_offset + 2);
            sample_rate = read_le32(bytes.data() + data_offset + 4);
            bits_per_sample = read_le16(bytes.data() + data_offset + 14);
        } else if (std::memcmp(chunk, "data", 4) == 0) {
            pcm = bytes.data() + data_offset;
            pcm_size = chunk_size;
        }
        offset = data_offset + chunk_size + (chunk_size & 1U);
    }

    if (audio_format != 1 || channels != 1 || sample_rate != 16000 ||
        bits_per_sample != 16 || pcm == nullptr || pcm_size < 2) {
        return false;
    }

    const size_t sample_count = pcm_size / 2;
    out.resize(sample_count);
    for (size_t i = 0; i < sample_count; ++i) {
        const int16_t sample = static_cast<int16_t>(read_le16(pcm + i * 2));
        out[i] = static_cast<float>(sample) / 32768.0f;
    }
    return true;
}

// ---- audio decode: any format → 16 kHz mono f32 (miniaudio resamples) ----
static bool load_audio_16k(const std::string& path, std::vector<float>& out) {
    if (load_pcm16_wav_16k_mono(path, out)) return true;

    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 1, 16000);
    ma_decoder decoder;
    if (ma_decoder_init_file(path.c_str(), &cfg, &decoder) != MA_SUCCESS) return false;
    std::vector<float> pcm;
    float buf[4096];
    for (;;) {
        ma_uint64 framesRead = 0;
        const ma_uint64 n = ma_decoder_read_pcm_frames(&decoder, buf, 4096, &framesRead);
        if (n == 0) break;
        pcm.insert(pcm.end(), buf, buf + framesRead);
    }
    ma_decoder_uninit(&decoder);
    out.swap(pcm);
    return !out.empty();
}

// ---- JSON helpers ----
static std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:   out += c;      break;
        }
    }
    return out;
}

static std::string transcribe_json(
    whisper_context* ctx,
    const std::string& path,
    const std::string& language,
    int threads,
    bool translate,
    float temperature,
    bool suppress_blank,
    bool word_timestamps) {
    std::vector<float> pcm;
    if (!load_audio_16k(path, pcm)) {
        return "{\"error\":\"cannot decode audio (wav/mp3/flac/ogg supported)\"}";
    }

    // whisper works on 30 s windows and behaves badly on clips shorter than its
    // 1 s minimum — it either returns nothing or invents a phrase. Pad short
    // dictation with silence rather than failing on a legitimate quick word.
    const size_t min_samples = WHISPER_SAMPLE_RATE;
    if (pcm.size() < min_samples) {
        pcm.resize(min_samples, 0.0f);
    }

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_realtime = false;
    params.print_progress = false;
    params.print_special = false;
    params.print_timestamps = false;
    if (threads > 0) {
        params.n_threads = threads;
    } else {
        const unsigned int cores = std::thread::hardware_concurrency();
        params.n_threads = cores == 0 ? 4 : static_cast<int>(cores > 4 ? 4 : cores);
    }
    params.single_segment = false;
    params.translate = translate;
    params.temperature = temperature;
    params.suppress_blank = suppress_blank;
    params.token_timestamps = word_timestamps;
    // Each call transcribes one independent recording, so carrying decoder
    // state across windows only gives whisper a chance to loop on a phrase it
    // already emitted — the classic repeated-sentence output.
    params.no_context = true;
    params.progress_callback = progress_cb;
    params.abort_callback = abort_cb;
    if (language.empty()) {
        params.language = nullptr;  // auto-detect
    } else {
        params.language = language.c_str();  // lives for duration of whisper_full
    }

    g_abort = false;
    if (whisper_full(ctx, params, pcm.data(), static_cast<int>(pcm.size())) != 0) {
        return "{\"error\":\"whisper_full failed\"}";
    }
    if (g_abort.load()) {
        return "{\"error\":\"cancelled\"}";
    }

    const int n = whisper_full_n_segments(ctx);
    std::string full;
    std::stringstream segs;
    segs << "[";
    double dur = 0.0;
    for (int i = 0; i < n; ++i) {
        const char* text = whisper_full_get_segment_text(ctx, i);
        if (!text) continue;
        const double t0 = whisper_full_get_segment_t0(ctx, i) / 100.0;
        const double t1 = whisper_full_get_segment_t1(ctx, i) / 100.0;
        if (i > 0) segs << ",";
        segs << "{\"text\":\"" << json_escape(text)
             << "\",\"start\":" << t0
             << ",\"end\":" << t1 << "}";
        full += text;
        dur = t1;
    }
    segs << "]";

    std::stringstream out;
    out << "{\"text\":\"" << json_escape(full)
        << "\",\"language\":\"" << whisper_lang_str(whisper_full_lang_id(ctx))
        << "\",\"duration\":" << dur
        << ",\"segments\":" << segs.str() << "}";
    return out.str();
}

// ---- JNI exports ----
extern "C" JNIEXPORT jlong JNICALL
Java_io_github_govindtank_flutter_1whisper_WhisperContext_nativeInit(
    JNIEnv* env, jobject thiz, jstring jmodel) {
    const char* cpath = env->GetStringUTFChars(jmodel, nullptr);
    std::string model(cpath);
    env->ReleaseStringUTFChars(jmodel, cpath);

    env->GetJavaVM(&g_vm);
    jclass cls = env->GetObjectClass(thiz);
    g_onProgress = env->GetMethodID(cls, "onNativeProgress", "(I)V");
    if (g_onProgress == nullptr || env->ExceptionCheck()) {
        env->ExceptionClear();
        g_onProgress = nullptr;
        return 0;
    }
    if (g_target) env->DeleteGlobalRef(g_target);
    g_target = env->NewGlobalRef(thiz);
    if (g_target == nullptr) {
        g_onProgress = nullptr;
        return 0;
    }

    struct whisper_context_params cparams = whisper_context_default_params();
    // This Android plugin is deliberately built with the CPU backend only.
    // whisper.cpp defaults both of these to true, which needlessly probes a
    // GPU path and selects the flash-attention graph even though no GPU
    // backend is packaged. Keep initialization on the guaranteed ARMv8-A
    // CPU path used by the build.
    cparams.use_gpu = false;
    cparams.flash_attn = false;
    whisper_context* ctx = nullptr;
    __android_log_print(
        ANDROID_LOG_INFO,
        WHISPER_JNI_TAG,
        "Starting CPU-only Whisper context initialization");
    try {
        ctx = whisper_init_from_file_with_params(model.c_str(), cparams);
    } catch (const std::bad_alloc&) {
        __android_log_print(
            ANDROID_LOG_ERROR,
            WHISPER_JNI_TAG,
            "Whisper context initialization ran out of memory");
    } catch (const std::exception& error) {
        __android_log_print(
            ANDROID_LOG_ERROR,
            WHISPER_JNI_TAG,
            "Whisper context initialization failed: %s",
            error.what());
    } catch (...) {
        __android_log_print(
            ANDROID_LOG_ERROR,
            WHISPER_JNI_TAG,
            "Whisper context initialization failed with an unknown native exception");
    }
    if (ctx == nullptr) {
        env->DeleteGlobalRef(g_target);
        g_target = nullptr;
        g_onProgress = nullptr;
    } else {
        __android_log_print(
            ANDROID_LOG_INFO,
            WHISPER_JNI_TAG,
            "Whisper context initialization completed");
    }
    return reinterpret_cast<jlong>(ctx);
}

extern "C" JNIEXPORT jstring JNICALL
Java_io_github_govindtank_flutter_1whisper_WhisperContext_nativeTranscribe(
    JNIEnv* env,
    jobject /*thiz*/,
    jlong handle,
    jstring jpath,
    jstring jlang,
    jint threads,
    jboolean translate,
    jfloat temperature,
    jboolean suppress_blank,
    jboolean word_timestamps) {
    whisper_context* ctx = reinterpret_cast<whisper_context*>(handle);
    if (!ctx) return env->NewStringUTF("{\"error\":\"whisper not initialized\"}");

    const char* cpath = env->GetStringUTFChars(jpath, nullptr);
    std::string path(cpath);
    env->ReleaseStringUTFChars(jpath, cpath);

    std::string language;
    if (jlang && env->GetStringUTFLength(jlang) > 0) {
        const char* clang = env->GetStringUTFChars(jlang, nullptr);
        language = clang;
        env->ReleaseStringUTFChars(jlang, clang);
    }

    std::string result = transcribe_json(
        ctx,
        path,
        language,
        threads,
        translate == JNI_TRUE,
        temperature,
        suppress_blank == JNI_TRUE,
        word_timestamps == JNI_TRUE);
    return utf8_to_jstring(env, result);
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_govindtank_flutter_1whisper_WhisperContext_nativeCancel(
    JNIEnv* /*env*/, jobject /*thiz*/, jlong /*handle*/) {
    g_abort = true;
}

extern "C" JNIEXPORT void JNICALL
Java_io_github_govindtank_flutter_1whisper_WhisperContext_nativeFree(
    JNIEnv* env, jobject /*thiz*/, jlong handle) {
    whisper_context* ctx = reinterpret_cast<whisper_context*>(handle);
    if (ctx) whisper_free(ctx);
    g_abort = false;
    if (g_target) {
        env->DeleteGlobalRef(g_target);
        g_target = nullptr;
    }
    g_onProgress = nullptr;
}
