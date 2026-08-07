import 'rewrite_output.dart';
import 'rewrite_request.dart';

/// Result of a full rewrite pass (primary output + alternatives).
class RewriteResult {
  const RewriteResult({
    required this.outputs,
    required this.request,
    this.createdAt,
  });

  final List<RewriteOutput> outputs;
  final RewriteRequest request;
  final DateTime? createdAt;

  RewriteOutput get primary =>
      outputs.isNotEmpty ? outputs.first : const RewriteOutput(text: '');

  factory RewriteResult.empty(RewriteRequest request) {
    return RewriteResult(outputs: const [], request: request);
  }
}
