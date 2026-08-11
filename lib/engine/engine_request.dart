import 'generation_options.dart';
import 'prompt_spec.dart';

/// Everything a prepared [RewriteEngine] needs to generate one result.
class EngineRequest {
  const EngineRequest({required this.prompt, required this.options});

  final PromptSpec prompt;
  final GenerationOptions options;
}
