/// Recognises a model declining to rewrite, so a refusal is never stored and
/// displayed as though it were a successful rewrite.
///
/// Small instruction-tuned models refuse ordinary drafts surprisingly often —
/// an observed `$24.50` in a message was read as payment credentials, and a
/// routine note was refused as "potentially misleading information" because
/// the model treated rewriting as vouching for the content. The prompt now
/// argues against both (see `PromptBuilder`), but a prompt is a request, not
/// a guarantee, so this is the second line of defence.
///
/// Deliberately conservative. A false positive here throws away a real
/// rewrite the user wanted, which is worse than letting an occasional
/// refusal through — so a match requires a refusal phrase near the very
/// start of a *short* response. A long response that merely happens to
/// contain "I cannot" somewhere is a rewrite of a draft that said so.
abstract final class RefusalDetector {
  /// Beyond this many characters a response is treated as real output no
  /// matter what it contains. Genuine refusals from these models are one or
  /// two sentences; a rewrite long enough to exceed this is not a refusal
  /// that happens to be verbose.
  static const int _maxRefusalLength = 300;

  /// Only the opening of the response is examined — a refusal announces
  /// itself immediately, whereas a legitimate rewrite of a draft that says
  /// "I can't make it Tuesday" would trip the same phrases mid-text.
  static const int _prefixWindow = 160;

  /// The verbs a refusal is *about*. Requiring one is what separates a model
  /// declining the task from a rewrite of a draft whose author is declining
  /// something — "I'm sorry but I cannot attend the review" is ordinary
  /// content and must survive, while "I'm sorry but I cannot rewrite this"
  /// is the model talking. Without this the two were indistinguishable, and
  /// a real rewrite would have been thrown away.
  static const String _taskVerbs =
      r'(?:rewrite|rewrit\w+|write|help|assist|complete|process|provide|'
      r'do that|do this|fulfil|fulfill|generate|create|produce|edit|revise)';

  static final List<RegExp> _patterns = [
    // "I cannot/can't/won't rewrite|write|help|assist|do that"
    RegExp(
      r"\bi\s+(?:cannot|can't|can not|won't|will not|am unable to|'m unable to)\s+"
      "$_taskVerbs",
      caseSensitive: false,
    ),
    // "I'm sorry, but I can't help ..." / "Sorry, I am unable to assist ..."
    RegExp(
      r"\b(?:i'?m sorry|i am sorry|sorry)\b[^.!?\n]{0,40}\b"
      r"(?:cannot|can't|can not|unable to|won't|not able to)\s+"
      "$_taskVerbs",
      caseSensitive: false,
    ),
    // "I'm not able to process ..." / "I am not able to help ..."
    RegExp(
      r"\bi\s*(?:'m| am)\s+not able to\s+"
      "$_taskVerbs",
      caseSensitive: false,
    ),
    // "As an AI ... I cannot" and friends.
    RegExp(
      r"\bas an? (?:ai|language model|assistant)\b",
      caseSensitive: false,
    ),
    // "Is there anything else I can help you with?" — the stock closer these
    // models append to a refusal.
    RegExp(
      r"\bis there anything else i can help\b",
      caseSensitive: false,
    ),
    // "I don't see any text" — the model failing to locate the source text
    // rather than objecting to it. Same remedy (retry), different cause.
    RegExp(
      r"\bi\s+(?:don'?t|do not)\s+see\s+(?:any\s+)?(?:text|content|message)\b",
      caseSensitive: false,
    ),
    // "Could you please share/provide the text"
    RegExp(
      r"\b(?:please\s+)?(?:share|provide|paste)\s+the\s+text\b",
      caseSensitive: false,
    ),
  ];

  /// True when [output] looks like a refusal or a "where is the text?" reply
  /// rather than a rewrite.
  static bool isRefusal(String output) {
    final text = output.trim();
    if (text.isEmpty) return false;
    if (text.length > _maxRefusalLength) return false;

    final prefix = text.length <= _prefixWindow
        ? text
        : text.substring(0, _prefixWindow);

    return _patterns.any((pattern) => pattern.hasMatch(prefix));
  }

  /// True when a parsed rewrite response looks like a refusal rather than a
  /// rewrite — [variants] is the caller's already-parsed
  /// `PromptBuilder.parseVariants` output.
  ///
  /// Only ever true for a single-variant response: with more than one
  /// variant parsed the model clearly understood the task, and a multi-part
  /// answer that merely opens with a refusal-shaped clause is far more
  /// likely to be a rewrite of a draft that said so.
  ///
  /// Shared by `RewriteController` and `WorkflowRunner` so a refusal gets
  /// the same one-retry-then-give-up treatment regardless of which one is
  /// driving the engine — `WorkflowRunner` used to have no refusal check at
  /// all, so a step's "I can't assist with that…" flowed into the next step
  /// (or was saved as the workflow's final result) as if it were real text.
  static bool looksLikeRefusal(List<String> variants) =>
      variants.length == 1 && isRefusal(variants.first);
}
