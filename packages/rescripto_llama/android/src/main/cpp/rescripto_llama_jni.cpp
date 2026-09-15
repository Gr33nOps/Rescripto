// JNI layer between LlamaNative.kt and llama.cpp.
//
// Threading: every entry point except nativeCancelUpTo is called from the
// plugin's single worker thread, so the model and context below need no lock.
// Cancellation is an atomic "cancel every generation id up to N" value that
// the decode loop and llama.cpp's abort callback both poll.

#include <jni.h>

#include <android/log.h>
#include <sys/auxv.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

#include "ggml-backend.h"
#include "llama.h"

#if defined(__aarch64__)
#include <asm/hwcap.h>
#endif

// Older NDK headers lack some of these bits.
#ifndef HWCAP_FPHP
#define HWCAP_FPHP (1 << 9)
#endif
#ifndef HWCAP_ASIMDDP
#define HWCAP_ASIMDDP (1 << 20)
#endif
#ifndef HWCAP2_I8MM
#define HWCAP2_I8MM (1 << 13)
#endif

namespace {

constexpr const char *kTag = "RescriptoLlama";

llama_model *g_model = nullptr;
llama_context *g_ctx = nullptr;

std::atomic<int64_t> g_cancel_up_to{0};
std::atomic<int64_t> g_running_id{0};

bool is_cancelled(int64_t id) { return id <= g_cancel_up_to.load(); }

bool abort_decode(void * /*data*/) { return is_cancelled(g_running_id.load()); }

void log_to_logcat(ggml_log_level level, const char *text, void * /*user_data*/) {
    // Keep logcat quiet in normal use: model loading prints hundreds of info
    // lines per load.
    if (level == GGML_LOG_LEVEL_ERROR) {
        __android_log_print(ANDROID_LOG_ERROR, kTag, "%s", text);
    } else if (level == GGML_LOG_LEVEL_WARN) {
        __android_log_print(ANDROID_LOG_WARN, kTag, "%s", text);
    }
}

jstring to_jstring(JNIEnv *env, const std::string &value) {
    return env->NewStringUTF(value.c_str());
}

std::string from_jstring(JNIEnv *env, jstring value) {
    if (value == nullptr) return {};
    const char *chars = env->GetStringUTFChars(value, nullptr);
    std::string result = chars == nullptr ? "" : chars;
    if (chars != nullptr) env->ReleaseStringUTFChars(value, chars);
    return result;
}

// GetStringUTFChars returns modified UTF-8, which encodes characters outside
// the BMP (most emoji) differently from real UTF-8. Prompts are user text, so
// convert through UTF-16 instead.
std::string utf8_from_jstring(JNIEnv *env, jstring value) {
    if (value == nullptr) return {};
    const jsize length = env->GetStringLength(value);
    const jchar *units = env->GetStringChars(value, nullptr);
    std::string out;
    out.reserve(static_cast<size_t>(length) * 3);
    for (jsize i = 0; i < length; ++i) {
        uint32_t cp = units[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < length) {
            const uint32_t low = units[i + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                ++i;
            }
        }
        if (cp < 0x80) {
            out.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    env->ReleaseStringChars(value, units);
    return out;
}

// Length of the longest prefix of `bytes` that ends on a complete UTF-8
// sequence. A token can end halfway through a multi-byte character; the
// remainder waits for the next token.
size_t complete_utf8_prefix(const std::string &bytes) {
    const size_t end = bytes.size();
    size_t i = end;
    // Walk back over at most three continuation bytes to the lead byte.
    int continuation = 0;
    while (i > 0 && continuation < 4) {
        const unsigned char c = static_cast<unsigned char>(bytes[i - 1]);
        if ((c & 0xC0) != 0x80) break;
        --i;
        ++continuation;
    }
    // No lead byte in reach means the bytes are not valid UTF-8 at all.
    // Passing them through beats holding back output forever.
    if (i == 0 || continuation >= 4) return end;
    const unsigned char lead = static_cast<unsigned char>(bytes[i - 1]);
    int needed = 1;
    if ((lead & 0x80) == 0x00) needed = 1;
    else if ((lead & 0xE0) == 0xC0) needed = 2;
    else if ((lead & 0xF0) == 0xE0) needed = 3;
    else if ((lead & 0xF8) == 0xF0) needed = 4;
    else return end;  // Invalid lead byte; pass it through rather than stall.
    const int have = continuation + 1;
    return have >= needed ? end : i - 1;
}

void free_model() {
    if (g_ctx != nullptr) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model != nullptr) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
}

// ggml builds one CPU backend per Android feature level. Load exactly one,
// chosen from the kernel's feature bits, so a phone never opens a library
// compiled for instructions it lacks. The list is ordered best first and
// always ends with the ARMv8.0 baseline every arm64 phone can run.
//
// Returns library file names. Non-arm64 builds (x86_64 emulator tests) have
// a single generic backend instead.
std::vector<std::string> cpu_backend_candidates() {
    std::vector<std::string> names;
#if defined(__aarch64__)
    const unsigned long hwcap = getauxval(AT_HWCAP);
    const unsigned long hwcap2 = getauxval(AT_HWCAP2);
    const bool dotprod = (hwcap & HWCAP_ASIMDDP) != 0;
    const bool fp16 = (hwcap & HWCAP_FPHP) != 0;
    const bool i8mm = (hwcap2 & HWCAP2_I8MM) != 0;
    if (dotprod && fp16 && i8mm) names.emplace_back("libggml-cpu-android_armv8.6_1.so");
    if (dotprod && fp16) names.emplace_back("libggml-cpu-android_armv8.2_2.so");
    if (dotprod) names.emplace_back("libggml-cpu-android_armv8.2_1.so");
    names.emplace_back("libggml-cpu-android_armv8.0_1.so");
#else
    names.emplace_back("libggml-cpu.so");
#endif
    return names;
}

bool contains_stop_sequence(const std::string &text, const std::vector<std::string> &stops,
                            size_t search_from) {
    for (const auto &stop : stops) {
        if (stop.empty()) continue;
        const size_t from = search_from > stop.size() ? search_from - stop.size() : 0;
        if (text.find(stop, from) != std::string::npos) return true;
    }
    return false;
}

}  // namespace

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_rescripto_llama_LlamaNative_nativeInitBackends(JNIEnv *env, jobject /*thiz*/,
                                                       jstring library_dir) {
    llama_log_set(log_to_logcat, nullptr);
    llama_backend_init();

    if (ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU) != nullptr) return nullptr;

    const std::string dir = from_jstring(env, library_dir);
    std::string tried;
    for (const auto &name : cpu_backend_candidates()) {
        const std::string path = dir + "/" + name;
        if (access(path.c_str(), R_OK) != 0) continue;
        if (!tried.empty()) tried += ", ";
        tried += name;
        if (ggml_backend_load(path.c_str()) != nullptr &&
            ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU) != nullptr) {
            __android_log_print(ANDROID_LOG_INFO, kTag, "Using CPU backend %s", name.c_str());
            return nullptr;
        }
    }
    return to_jstring(env, tried.empty()
                               ? "No CPU backend library was found in the app's native library folder."
                               : "None of the CPU backends could be loaded on this phone (" + tried + ").");
}

JNIEXPORT jstring JNICALL
Java_com_rescripto_llama_LlamaNative_nativeLoadModel(JNIEnv *env, jobject /*thiz*/, jstring path,
                                                    jint threads, jint context_size, jint batch_size) {
    free_model();

    const std::string model_path = from_jstring(env, path);
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;

    g_model = llama_model_load_from_file(model_path.c_str(), model_params);
    if (g_model == nullptr) {
        return to_jstring(env, "The model file could not be read as a GGUF model.");
    }

    const int32_t trained = llama_model_n_ctx_train(g_model);
    uint32_t n_ctx = static_cast<uint32_t>(context_size);
    if (trained > 0 && n_ctx > static_cast<uint32_t>(trained)) n_ctx = static_cast<uint32_t>(trained);

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = n_ctx;
    ctx_params.n_batch = static_cast<uint32_t>(batch_size);
    ctx_params.n_ubatch = static_cast<uint32_t>(batch_size);
    ctx_params.n_seq_max = 1;
    ctx_params.n_threads = threads;
    ctx_params.n_threads_batch = threads;
    ctx_params.no_perf = true;
    ctx_params.abort_callback = abort_decode;
    ctx_params.abort_callback_data = nullptr;

    g_ctx = llama_init_from_model(g_model, ctx_params);
    if (g_ctx == nullptr) {
        free_model();
        return to_jstring(env, "There is not enough memory to set up this model's context. "
                               "Try a smaller context size or a smaller model.");
    }
    return nullptr;
}

JNIEXPORT void JNICALL
Java_com_rescripto_llama_LlamaNative_nativeUnloadModel(JNIEnv * /*env*/, jobject /*thiz*/) {
    free_model();
}

JNIEXPORT void JNICALL
Java_com_rescripto_llama_LlamaNative_nativeCancelUpTo(JNIEnv * /*env*/, jobject /*thiz*/, jlong id) {
    int64_t current = g_cancel_up_to.load();
    while (id > current && !g_cancel_up_to.compare_exchange_weak(current, id)) {
    }
}

JNIEXPORT jstring JNICALL
Java_com_rescripto_llama_LlamaNative_nativeGenerate(JNIEnv *env, jobject /*thiz*/, jlong id,
                                                   jstring prompt, jfloat temperature, jfloat top_p,
                                                   jint top_k, jfloat repeat_penalty, jint max_tokens,
                                                   jobjectArray stop_sequences, jobject sink) {
    if (g_model == nullptr || g_ctx == nullptr) {
        return to_jstring(env, "MODEL_NOT_LOADED|No model is loaded.");
    }
    g_running_id.store(id);
    if (is_cancelled(id)) return nullptr;

    jclass sink_class = env->GetObjectClass(sink);
    jmethodID on_text = env->GetMethodID(sink_class, "onText", "([B)V");
    env->DeleteLocalRef(sink_class);
    if (on_text == nullptr) {
        env->ExceptionClear();
        return to_jstring(env, "GENERATION_FAILED|The text callback is missing.");
    }

    std::vector<std::string> stops;
    const jsize stop_count = stop_sequences == nullptr ? 0 : env->GetArrayLength(stop_sequences);
    for (jsize i = 0; i < stop_count; ++i) {
        auto item = static_cast<jstring>(env->GetObjectArrayElement(stop_sequences, i));
        stops.push_back(utf8_from_jstring(env, item));
        env->DeleteLocalRef(item);
    }

    const llama_vocab *vocab = llama_model_get_vocab(g_model);
    const std::string text = utf8_from_jstring(env, prompt);

    const int32_t needed = -llama_tokenize(vocab, text.c_str(), static_cast<int32_t>(text.size()),
                                           nullptr, 0, true, true);
    if (needed <= 0) {
        return to_jstring(env, "GENERATION_FAILED|The prompt could not be tokenized.");
    }
    std::vector<llama_token> tokens(static_cast<size_t>(needed));
    if (llama_tokenize(vocab, text.c_str(), static_cast<int32_t>(text.size()), tokens.data(),
                       needed, true, true) < 0) {
        return to_jstring(env, "GENERATION_FAILED|The prompt could not be tokenized.");
    }

    const auto n_ctx = static_cast<int32_t>(llama_n_ctx(g_ctx));
    const auto n_prompt = static_cast<int32_t>(tokens.size());
    if (n_prompt + 8 >= n_ctx) {
        return to_jstring(env, "CONTEXT_OVERFLOW|The prompt uses " + std::to_string(n_prompt) +
                                   " of " + std::to_string(n_ctx) + " context tokens.");
    }

    llama_memory_clear(llama_get_memory(g_ctx), true);

    // Feed the prompt in batch-sized pieces. One oversized batch is rejected
    // by llama_decode, and on a phone a long prompt in one piece also holds
    // a large compute buffer for no gain.
    const auto n_batch = static_cast<int32_t>(llama_n_batch(g_ctx));
    for (int32_t start = 0; start < n_prompt; start += n_batch) {
        const int32_t count = std::min(n_batch, n_prompt - start);
        const int32_t rc = llama_decode(g_ctx, llama_batch_get_one(tokens.data() + start, count));
        if (is_cancelled(id)) {
            llama_memory_clear(llama_get_memory(g_ctx), true);
            return nullptr;
        }
        if (rc != 0) {
            llama_memory_clear(llama_get_memory(g_ctx), true);
            return to_jstring(env, "GENERATION_FAILED|The model could not read the prompt (code " +
                                       std::to_string(rc) + ").");
        }
    }

    llama_sampler_chain_params chain_params = llama_sampler_chain_default_params();
    chain_params.no_perf = true;
    llama_sampler *sampler = llama_sampler_chain_init(chain_params);
    if (repeat_penalty > 1.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, repeat_penalty, 0.0f, 0.0f));
    }
    if (temperature <= 0.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
        if (top_k > 0) llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
        if (top_p > 0.0f && top_p < 1.0f) llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
        const auto seed = static_cast<uint32_t>(
            std::chrono::steady_clock::now().time_since_epoch().count());
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
    }

    std::string pending;
    std::string produced;
    std::string failure;
    char piece[256];
    const int32_t budget = std::max(1, std::min<int32_t>(max_tokens, n_ctx - n_prompt - 1));

    auto emit = [&](size_t length) -> bool {
        if (length == 0) return true;
        jbyteArray bytes = env->NewByteArray(static_cast<jsize>(length));
        if (bytes == nullptr) return false;
        env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(length),
                                reinterpret_cast<const jbyte *>(pending.data()));
        env->CallVoidMethod(sink, on_text, bytes);
        env->DeleteLocalRef(bytes);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            return false;
        }
        produced.append(pending, 0, length);
        pending.erase(0, length);
        return true;
    };

    for (int32_t generated = 0; generated < budget; ++generated) {
        if (is_cancelled(id)) break;

        llama_token token = llama_sampler_sample(sampler, g_ctx, -1);
        if (llama_vocab_is_eog(vocab, token)) break;

        int32_t n = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, false);
        if (n < 0) {
            std::string large(static_cast<size_t>(-n), '\0');
            n = llama_token_to_piece(vocab, token, large.data(), -n, 0, false);
            if (n > 0) pending.append(large.data(), static_cast<size_t>(n));
        } else if (n > 0) {
            pending.append(piece, static_cast<size_t>(n));
        }

        const size_t before = produced.size();
        if (!emit(complete_utf8_prefix(pending))) {
            failure = "GENERATION_FAILED|The generated text could not be delivered.";
            break;
        }
        if (contains_stop_sequence(produced, stops, before)) break;

        const int32_t rc = llama_decode(g_ctx, llama_batch_get_one(&token, 1));
        if (is_cancelled(id)) break;
        if (rc != 0) {
            failure = "GENERATION_FAILED|The model stopped unexpectedly (code " + std::to_string(rc) + ").";
            break;
        }
    }

    if (failure.empty() && !pending.empty() && !is_cancelled(id)) {
        emit(pending.size());
    }

    llama_sampler_free(sampler);
    llama_memory_clear(llama_get_memory(g_ctx), true);
    return failure.empty() ? nullptr : to_jstring(env, failure);
}

}  // extern "C"
