#ifndef FLUTTER_LLAMA_CPP_BRIDGE_H
#define FLUTTER_LLAMA_CPP_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool rescripto_llama_init_model(
    const char * model_path,
    int32_t n_threads,
    int32_t n_gpu_layers,
    int32_t context_size,
    int32_t batch_size,
    bool use_gpu,
    bool verbose);

bool rescripto_llama_generate(
    const char * prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    int32_t max_tokens,
    float repeat_penalty,
    char * output,
    int32_t output_size,
    int32_t * tokens_generated);

bool rescripto_llama_generate_stream_init(
    const char * prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    int32_t max_tokens,
    float repeat_penalty);

bool rescripto_llama_generate_stream_next(char * output, int32_t output_size);
void rescripto_llama_generate_stream_end(void);
void rescripto_llama_get_model_info(
    int64_t * n_params,
    int32_t * n_layers,
    int32_t * context_size);
void rescripto_llama_free_model(void);
void rescripto_llama_stop_generation(void);

#ifdef __cplusplus
}
#endif

#endif
