/*
 * Flutter Llama - JNI Bridge for Android
 * 
 * This file provides JNI bindings between Kotlin and llama.cpp
 * Updated for latest llama.cpp API
 */

#include <jni.h>
#include <string>
#include <vector>
#include <mutex>
#include <atomic>
#include <chrono>
#include <android/log.h>
#include <dlfcn.h>

#define LOG_TAG "FlutterLlamaBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Include llama.cpp headers
#include "llama.h"

// Forwards llama.cpp's own diagnostics into logcat. Without this, a failed
// model load surfaces to Dart as a bare "false" with no reason attached.
static void llama_log_to_android(ggml_log_level level, const char * text, void * /*user_data*/) {
    if (!text) return;
    const int priority = level == GGML_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR
                       : level == GGML_LOG_LEVEL_WARN  ? ANDROID_LOG_WARN
                       : ANDROID_LOG_INFO;
    __android_log_print(priority, "llama.cpp", "%s", text);
}

// Global state
static llama_model* g_model = nullptr;
static llama_context* g_context = nullptr;
static const llama_vocab* g_vocab = nullptr;
static llama_sampler* g_sampler = nullptr;
static std::mutex g_mutex;
static std::atomic<bool> g_should_stop{false};
static int g_stream_remaining = 0;
static bool g_stream_finished = true;
static std::string g_last_error;

static std::string jstring_to_utf8(JNIEnv* env, jstring input) {
    if (!input) return {};
    const jchar* chars = env->GetStringChars(input, nullptr);
    const jsize length = env->GetStringLength(input);
    std::string output;
    output.reserve(length * 3);
    for (jsize i = 0; i < length; ++i) {
        uint32_t codepoint = chars[i];
        if (codepoint >= 0xD800 && codepoint <= 0xDBFF && i + 1 < length) {
            const uint32_t low = chars[i + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00);
                ++i;
            }
        }
        if (codepoint <= 0x7F) {
            output.push_back(static_cast<char>(codepoint));
        } else if (codepoint <= 0x7FF) {
            output.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else if (codepoint <= 0xFFFF) {
            output.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else {
            output.push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        }
    }
    env->ReleaseStringChars(input, chars);
    return output;
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

static void reset_sampler(float temperature, float top_p, int top_k, float repeat_penalty) {
    if (g_sampler) llama_sampler_free(g_sampler);
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_penalties(-1, repeat_penalty, 0.0f, 0.0f));
    const auto seed = static_cast<uint32_t>(
        std::chrono::high_resolution_clock::now().time_since_epoch().count());
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(seed));
}

static std::string token_to_utf8(llama_token token) {
    std::vector<char> buffer(256);
    int length = llama_token_to_piece(
        g_vocab, token, buffer.data(), static_cast<int32_t>(buffer.size()), 0, true);
    if (length < 0) {
        buffer.resize(static_cast<size_t>(-length));
        length = llama_token_to_piece(
            g_vocab, token, buffer.data(), static_cast<int32_t>(buffer.size()), 0, true);
    }
    return length > 0 ? std::string(buffer.data(), static_cast<size_t>(length)) : std::string();
}

// llama.cpp treats n_batch as a hard maximum, not a hint. Sending the whole
// rewrite prompt at once used to trip its GGML_ASSERT when our instructions
// exceeded 512 tokens, killing the Android process before Flutter could see an
// error. Automatic positions make sequential one-sequence batches safe.
static bool decode_prompt_in_batches(const std::vector<llama_token>& tokens) {
    const int batch_limit = static_cast<int>(llama_n_batch(g_context));
    if (batch_limit <= 0) {
        g_last_error = "The model has no usable prompt batch size.";
        LOGE("%s", g_last_error.c_str());
        return false;
    }

    for (size_t offset = 0; offset < tokens.size();) {
        const int remaining = static_cast<int>(tokens.size() - offset);
        const int count = remaining < batch_limit ? remaining : batch_limit;
        const llama_batch batch = llama_batch_get_one(
            const_cast<llama_token*>(tokens.data() + offset), count);
        const int status = llama_decode(g_context, batch);
        if (status != 0) {
            g_last_error = "The model could not read the prompt (decode error " +
                           std::to_string(status) + ").";
            LOGE("%s", g_last_error.c_str());
            return false;
        }
        offset += static_cast<size_t>(count);
    }
    return true;
}

// Dynamic CPU variants must be loaded from the app's native-library directory,
// not from Android's APK path. dladdr gives us this bridge's loaded .so path.
static void load_dynamic_backends() {
    Dl_info info{};
    if (dladdr(reinterpret_cast<void*>(&llama_log_to_android), &info) != 0 &&
        info.dli_fname != nullptr) {
        const std::string bridge_path(info.dli_fname);
        const size_t slash = bridge_path.find_last_of('/');
        if (slash != std::string::npos) {
            ggml_backend_load_all_from_path(bridge_path.substr(0, slash).c_str());
            return;
        }
    }
    LOGE("Could not determine native library directory; using ggml default search paths");
    ggml_backend_load_all();
}

extern "C" {

// Initialize and load model
JNIEXPORT jboolean JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeInitModel(
    JNIEnv* env,
    jobject thiz,
    jstring model_path,
    jint n_threads,
    jint n_gpu_layers,
    jint context_size,
    jint batch_size,
    jboolean use_gpu,
    jboolean verbose
) {
    std::lock_guard<std::mutex> lock(g_mutex);

    g_last_error.clear();

    static std::once_flag log_once;
    std::call_once(log_once, [] { llama_log_set(llama_log_to_android, nullptr); });

    const std::string path = jstring_to_utf8(env, model_path);

    LOGI("Initializing model: %s", path.c_str());
    LOGI("Threads: %d, GPU layers: %d, Context: %d, GPU: %d",
         n_threads, n_gpu_layers, context_size, use_gpu ? 1 : 0);

    // Free existing model if any
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }

    // Load the safest compatible CPU backend for this device.
    load_dynamic_backends();

    // Set up model parameters
    llama_model_params model_params = llama_model_default_params();

    // A null `devices` list makes llama.cpp enumerate every registered backend
    // and build a buffer-type list for each one. On Android that touches the
    // Vulkan device even when nothing will be offloaded, and bringing up a
    // Vulkan device makes ggml compile several hundred compute pipelines —
    // minutes of a pegged GPU with no visible progress before generation can
    // even start. Handing llama.cpp an empty device list keeps the load path
    // strictly CPU and never initializes Vulkan at all.
    static ggml_backend_dev_t no_devices[] = { nullptr };
    if (use_gpu) {
        // -1 is not "all layers" to llama.cpp: i_gpu_start becomes n_layer + 1
        // and every layer stays on the CPU, which is why the GPU switch used to
        // make no difference. 999 is llama.cpp's own "offload everything".
        model_params.n_gpu_layers = n_gpu_layers < 0 ? 999 : n_gpu_layers;
    } else {
        model_params.n_gpu_layers = 0;
        model_params.devices = no_devices;
    }

    // Load model
    g_model = llama_model_load_from_file(path.c_str(), model_params);
    if (!g_model) {
        g_last_error = "llama.cpp could not load this model file. It may be "
                       "incomplete or in an unsupported GGUF format.";
        LOGE("Failed to load model from: %s", path.c_str());
        return JNI_FALSE;
    }

    // Get vocab
    g_vocab = llama_model_get_vocab(g_model);

    // Never build a context larger than the model was trained for — the extra
    // KV cache is wasted RAM on a phone and can push the process into an OOM
    // kill on the mid-range devices this app targets.
    const int trained_ctx = static_cast<int>(llama_model_n_ctx_train(g_model));
    int effective_ctx = context_size;
    if (trained_ctx > 0 && effective_ctx > trained_ctx) {
        LOGI("Clamping context %d -> %d (model training context)", effective_ctx, trained_ctx);
        effective_ctx = trained_ctx;
    }

    // Create context
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = effective_ctx;
    ctx_params.n_batch = batch_size;
    ctx_params.n_ubatch = batch_size < 512 ? batch_size : 512;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;

    g_context = llama_init_from_model(g_model, ctx_params);
    if (!g_context) {
        g_last_error = "Not enough memory to open this model at the selected "
                       "context size. Try a smaller model or a smaller context.";
        LOGE("Failed to create context");
        llama_model_free(g_model);
        g_model = nullptr;
        return JNI_FALSE;
    }

    reset_sampler(0.8f, 0.95f, 40, 1.1f);

    LOGI("Model loaded successfully");
    LOGI("Context size: %d", llama_n_ctx(g_context));

    return JNI_TRUE;
}

// Returns the reason the last init/generate call failed, or an empty string.
JNIEXPORT jstring JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGetLastError(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return utf8_to_jstring(env, g_last_error);
}

// Generate text
JNIEXPORT jobject JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerate(
    JNIEnv* env,
    jobject thiz,
    jstring prompt,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jint max_tokens,
    jfloat repeat_penalty
) {
    std::lock_guard<std::mutex> lock(g_mutex);

    g_last_error.clear();
    if (!g_model || !g_context || !g_vocab) {
        g_last_error = "The model is not loaded.";
        LOGE("Model not loaded");
        return nullptr;
    }
    
    const std::string prompt_text = jstring_to_utf8(env, prompt);
    LOGI("Generating with prompt: %.50s...", prompt_text.c_str());
    
    // Tokenize prompt
    const int n_ctx = static_cast<int>(llama_n_ctx(g_context));
    const int n_prompt = -llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), NULL, 0, true, true);
    if (n_prompt <= 0 || n_ctx - n_prompt - 4 < 16) {
        g_last_error = "This text is too long for the selected context size.";
        LOGE("Prompt/output exceeds context: prompt=%d output=%d context=%d",
             n_prompt, max_tokens, n_ctx);
        return nullptr;
    }
    // Clamp to the room actually left in the context instead of refusing.
    const int room = n_ctx - n_prompt - 4;
    if (max_tokens > room) max_tokens = room;
    std::vector<llama_token> prompt_tokens(n_prompt);
    
    if (llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        g_last_error = "The prompt could not be tokenized.";
        LOGE("Failed to tokenize prompt");
        return nullptr;
    }
    
    llama_memory_clear(llama_get_memory(g_context), true);

    if (!decode_prompt_in_batches(prompt_tokens)) {
        return nullptr;
    }
    
    reset_sampler(temperature, top_p, top_k, repeat_penalty);
    
    // Generate tokens
    std::string result;
    int n_generated = 0;
    
    g_should_stop = false;
    
    for (int i = 0; i < max_tokens; i++) {
        if (g_should_stop.load()) {
            LOGI("Generation stopped by user");
            break;
        }
        
        // Sample next token
        llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);
        llama_sampler_accept(g_sampler, new_token);
        
        // Check for EOS
        if (llama_vocab_is_eog(g_vocab, new_token)) {
            LOGI("EOS token reached");
            break;
        }
        
        // Convert token to text
        result.append(token_to_utf8(new_token));
        
        // Prepare for next iteration
        const llama_batch batch = llama_batch_get_one(&new_token, 1);
        
        if (llama_decode(g_context, batch) != 0) {
            g_last_error = "The model could not generate the next token.";
            LOGE("%s", g_last_error.c_str());
            return nullptr;
        }
        
        n_generated++;
    }
    
    LOGI("Generated %d tokens", n_generated);
    
    // Create GenerationResult object
    jclass result_class = env->FindClass("net/nativemind/flutter_llama/FlutterLlamaPlugin$GenerationResult");
    if (!result_class) {
        LOGE("Failed to find GenerationResult class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(result_class, "<init>", "(Ljava/lang/String;I)V");
    if (!constructor) {
        LOGE("Failed to find GenerationResult constructor");
        return nullptr;
    }
    
    jstring j_result = utf8_to_jstring(env, result);
    jobject generation_result = env->NewObject(result_class, constructor, j_result, n_generated);
    
    return generation_result;
}

// Initialize streaming generation
JNIEXPORT jboolean JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamInit(
    JNIEnv* env,
    jobject thiz,
    jstring prompt,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jint max_tokens,
    jfloat repeat_penalty
) {
    std::lock_guard<std::mutex> lock(g_mutex);

    LOGI("Initializing stream generation");

    g_last_error.clear();

    if (!g_model || !g_context || !g_vocab) {
        g_last_error = "The model is not loaded.";
        LOGE("Model not loaded");
        return JNI_FALSE;
    }

    g_should_stop = false;
    g_stream_finished = true;

    const std::string prompt_text = jstring_to_utf8(env, prompt);

    // Tokenize prompt
    const int n_ctx = static_cast<int>(llama_n_ctx(g_context));
    const int n_prompt = -llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), NULL, 0, true, true);
    if (n_prompt <= 0) {
        g_last_error = "The prompt could not be tokenized.";
        LOGE("Tokenization produced no tokens");
        return JNI_FALSE;
    }
    // Reserve a few tokens of headroom so decoding the last sampled token
    // cannot run off the end of the KV cache.
    const int room = n_ctx - n_prompt - 4;
    if (room < 16) {
        g_last_error = "This text is too long for the selected context size.";
        LOGE("Prompt of %d tokens leaves no room in a %d-token context", n_prompt, n_ctx);
        return JNI_FALSE;
    }
    // Clamp rather than refuse: the Dart side can only estimate token counts
    // from byte length, so an honest overshoot used to fail the whole rewrite.
    g_stream_remaining = max_tokens < room ? max_tokens : room;

    std::vector<llama_token> prompt_tokens(n_prompt);

    if (llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        g_last_error = "The prompt could not be tokenized.";
        LOGE("Failed to tokenize prompt");
        return JNI_FALSE;
    }

    llama_memory_clear(llama_get_memory(g_context), true);

    if (!decode_prompt_in_batches(prompt_tokens)) {
        return JNI_FALSE;
    }

    reset_sampler(temperature, top_p, top_k, repeat_penalty);
    g_stream_finished = false;
    return JNI_TRUE;
}

// Get next token in stream
JNIEXPORT jstring JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamNext(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (g_should_stop.load() || g_stream_finished || g_stream_remaining <= 0) {
        g_stream_finished = true;
        return nullptr;
    }

    llama_token token = llama_sampler_sample(g_sampler, g_context, -1);
    llama_sampler_accept(g_sampler, token);
    if (llama_vocab_is_eog(g_vocab, token)) {
        g_stream_finished = true;
        return nullptr;
    }

    const std::string piece = token_to_utf8(token);
    llama_batch batch = llama_batch_get_one(&token, 1);
    if (llama_decode(g_context, batch) != 0) {
        g_last_error = "The model could not generate the next token.";
        LOGE("%s", g_last_error.c_str());
        g_stream_finished = true;
        return nullptr;
    }
    --g_stream_remaining;
    return utf8_to_jstring(env, piece);
}

// End streaming generation
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamEnd(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Ending stream generation");
    g_stream_remaining = 0;
    g_stream_finished = true;
}

// Get model information
JNIEXPORT jobject JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGetModelInfo(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_model || !g_context) {
        return nullptr;
    }
    
    jlong n_params = llama_model_n_params(g_model);
    jint n_layers = llama_model_n_layer(g_model);
    jint context_size = llama_n_ctx(g_context);
    
    LOGI("Model info: params=%lld, layers=%d, context=%d", 
         (long long)n_params, n_layers, context_size);
    
    // Create ModelInfo object
    jclass info_class = env->FindClass("net/nativemind/flutter_llama/FlutterLlamaPlugin$ModelInfo");
    if (!info_class) {
        LOGE("Failed to find ModelInfo class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(info_class, "<init>", "(JII)V");
    if (!constructor) {
        LOGE("Failed to find ModelInfo constructor");
        return nullptr;
    }
    
    jobject model_info = env->NewObject(info_class, constructor, n_params, n_layers, context_size);
    return model_info;
}

// Free model
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeFreeModel(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Freeing model");
    
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    
    g_vocab = nullptr;
    g_stream_remaining = 0;
    g_stream_finished = true;
    
    LOGI("Model freed successfully");
}

// Stop generation
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeStopGeneration(
    JNIEnv* env,
    jobject thiz
) {
    LOGI("Stopping generation");
    g_should_stop.store(true);
}

} // extern "C"
