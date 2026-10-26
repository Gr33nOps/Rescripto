import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/language_fidelity.dart';

void main() {
  test(
    'German translation to English is rejected without rejecting German edits',
    () {
      final profile = LanguageFidelity.inspect(
        'hallo, ich komm morgen nicht ins buero weil mein zug ausfaellt, '
        'bin ab 13 uhr online',
      );
      expect(profile.languages, {'de'});
      expect(profile.promptCues.single, contains('Deutsch'));
      expect(
        profile.rejects(
          'Hallo, I will not be in the office tomorrow because my train '
          'was cancelled. I will be online at 13:00.',
        ),
        isTrue,
      );
      expect(
        profile.rejects(
          'Hallo, ich komme morgen nicht ins Büro, weil mein Zug ausfällt, '
          'und ich bin ab 13 Uhr online.',
        ),
        isFalse,
      );
      expect(
        profile.rejects(
          'Hallo, ich komme morgen nicht ins Büro, but I will be online '
          'at 13 Uhr.',
        ),
        isTrue,
      );
    },
  );

  test('French and Spanish stay in their source languages', () {
    final french = LanguageFidelity.inspect(
      'bonjour, je ne peux pas venir demain parce que mon train est annulé, '
      'je serai en ligne à 13 h',
    );
    expect(french.languages, contains('fr'));
    expect(
      french.rejects(
        'Bonjour, je ne peux pas venir demain parce que mon train est '
        'annulé. Je serai en ligne à 13 h.',
      ),
      isFalse,
    );
    expect(
      french.rejects(
        'Hello, I cannot come tomorrow because my train was cancelled. '
        'I will be online at 13 h.',
      ),
      isTrue,
    );

    final spanish = LanguageFidelity.inspect(
      'hola, no puedo ir a la oficina mañana porque cancelaron mi tren, '
      'estaré en línea desde las 13 h',
    );
    expect(spanish.languages, contains('es'));
    expect(
      spanish.rejects(
        'Hola, no puedo ir a la oficina mañana porque cancelaron mi tren. '
        'Estaré en línea desde las 13 h.',
      ),
      isFalse,
    );
  });

  test('mixed language source requires its substantive German passage', () {
    final profile = LanguageFidelity.inspect(
      'Hi Maria, ich bin ab 13 uhr online. See you tomorrow.',
    );
    expect(profile.languages, contains('de'));
    expect(profile.promptCues.first, contains('Keep the language switches'));
    expect(profile.promptCues.first, contains('copy already-correct passages'));
    expect(profile.promptCues, contains(contains('German passages')));
    expect(
      profile.rejects('Hi Maria, I am online at 13:00. See you tomorrow.'),
      isTrue,
    );
    expect(
      profile.rejects('Hi Maria, ich bin ab 13 Uhr online. See you tomorrow.'),
      isFalse,
    );
  });

  test('a short standalone German passage receives the native cue', () {
    final profile = LanguageFidelity.inspect('ich bin ab 13 uhr online');
    expect(profile.languages, {'de'});
    expect(profile.promptCues.single, contains('Deutsch'));
    expect(profile.rejects('Ich bin ab 13 Uhr online.'), isFalse);
  });

  test('mixed passage plan preserves short greetings and separators', () {
    final passages = LanguageFidelity.mixedPassages(
      'Hi Maria, ich bin ab 13 uhr online. See you tomorrow.',
    );
    expect(passages, isNotNull);
    expect(
      passages!.map((part) => part.original).join(),
      'Hi Maria, ich bin ab 13 uhr online. See you tomorrow.',
    );
    expect(passages.map((part) => part.languageCode).toList(), [
      null,
      'de',
      null,
    ]);
    expect(
      passages[1].withRewrite('Ich bin ab 13 Uhr online.'),
      ' ich bin ab 13 Uhr online.',
    );
  });

  test('non-Latin source cannot silently become Latin-script English', () {
    final profile = LanguageFidelity.inspect('明日は休みです。会議は金曜日です。');
    expect(profile.languages, contains('ja'));
    expect(
      profile.rejects('I am off tomorrow. The meeting is Friday.'),
      isTrue,
    );
    expect(profile.rejects('明日は休みです。会議は金曜日です。'), isFalse);
  });

  test('a non-Latin passage survives an English passage beside it', () {
    final profile = LanguageFidelity.inspect(
      'کل رپورٹ بھیج دوں گا، please check it tomorrow.',
    );
    expect(
      profile.rejects('I will send the report tomorrow, please check it.'),
      isTrue,
    );
    expect(
      profile.rejects('کل رپورٹ بھیج دوں گا، please check it tomorrow.'),
      isFalse,
    );
  });

  test('English draft with numbers is not treated as foreign text', () {
    final profile = LanguageFidelity.inspect(
      'Hey sorry I cannot make the meeting on Tuesday at 3pm, can we '
      'move it to Thursday 10am? I will bring the 12 reports from Maria.',
    );
    expect(profile.languages, isNot(contains('de')));
    expect(
      profile.rejects(
        'Sorry, I cannot make the meeting on Tuesday at 3 pm. Could we '
        'move it to Thursday at 10 am? I will bring the 12 reports from Maria.',
      ),
      isFalse,
    );
  });

  test('ambiguous short text is not assigned a guessed language', () {
    final profile = LanguageFidelity.inspect('Hi Maria');
    expect(profile.languages, isEmpty);
    expect(profile.promptCues, isEmpty);
    expect(profile.rejects('Hi, Maria.'), isFalse);
  });
}
