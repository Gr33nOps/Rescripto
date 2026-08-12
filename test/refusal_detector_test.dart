import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/refusal_detector.dart';

void main() {
  group('RefusalDetector.isRefusal — real observed refusals', () {
    // Every string in this group was produced by an on-device model asked to
    // rewrite an entirely ordinary message.
    test('refuses over a plain dollar amount', () {
      expect(
        RefusalDetector.isRefusal(
          'I cannot rewrite a text that includes payment information. Is '
          'there anything else I can help you with?',
        ),
        isTrue,
      );
    });

    test('refuses as "potentially misleading"', () {
      expect(
        RefusalDetector.isRefusal(
          'I cannot write an email that contains potentially misleading '
          'information. Is there anything else I can help you with?',
        ),
        isTrue,
      );
    });

    test('claims no text was provided', () {
      expect(
        RefusalDetector.isRefusal(
          "I'm happy to help, but I don't see any text provided. Could you "
          'please share the text you\'d like me to rewrite?',
        ),
        isTrue,
      );
    });
  });

  group('RefusalDetector.isRefusal — other refusal shapes', () {
    for (final refusal in const [
      "I'm sorry, but I can't help with that.",
      "Sorry, I am unable to assist with this request.",
      "I'm not able to process this text.",
      'As an AI language model, I must decline.',
      "I can't rewrite this.",
      'Please provide the text you want rewritten.',
    ]) {
      test('detects: "$refusal"', () {
        expect(RefusalDetector.isRefusal(refusal), isTrue);
      });
    }
  });

  group('RefusalDetector.isRefusal — must not fire on real rewrites', () {
    test('a rewrite of a draft that itself says "I cannot make it"', () {
      expect(
        RefusalDetector.isRefusal(
          "I cannot make it to Tuesday's meeting, but I can join on "
          'Wednesday if that works for everyone.',
        ),
        isFalse,
        reason: 'the phrase belongs to the user\'s content, not the model',
      );
    });

    test('a long rewrite mentioning being unable to attend', () {
      final rewrite =
          "Hi team, I'm sorry but I cannot attend the review session this "
          'week. I have a conflicting commitment that I was not able to move. '
          'I have read through the document in full and left my comments '
          'inline, so please go ahead without me. If anything needs a '
          'decision from my side, flag it and I will respond the same day. '
          'Thanks for understanding, and apologies for the short notice on '
          'this one.';
      expect(RefusalDetector.isRefusal(rewrite), isFalse);
    });

    test('an ordinary rewrite', () {
      expect(
        RefusalDetector.isRefusal(
          'Hey, I just wanted to ask if the project can be finished by '
          'August 20, 2026.',
        ),
        isFalse,
      );
    });

    test('empty output is not a refusal — EmptyResponseException covers it', () {
      expect(RefusalDetector.isRefusal(''), isFalse);
      expect(RefusalDetector.isRefusal('   '), isFalse);
    });

    test('a refusal phrase buried late in a short text does not fire', () {
      expect(
        RefusalDetector.isRefusal(
          'The deadline is flexible and the budget is approved, so please '
          'proceed whenever you are ready. I cannot see any blockers.',
        ),
        isFalse,
        reason: 'only the opening of the response is examined',
      );
    });
  });
}
