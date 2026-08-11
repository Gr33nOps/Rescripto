/// A rewrite prompt in provider-neutral shape: instructions plus the text to
/// act on, not yet wrapped in any model's chat markup.
///
/// [system] stays a separate field rather than folded into a message list,
/// because Anthropic's API takes `system` as a top-level parameter rather
/// than a message with a role — un-folding it per provider later would be
/// worse than keeping the split now, when it costs nothing.
class PromptSpec {
  const PromptSpec({required this.system, required this.user});

  final String system;
  final String user;
}
