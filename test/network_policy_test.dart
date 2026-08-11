import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/network/network_feature.dart';
import 'package:rescripto/services/network/network_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<NetworkPolicy> freshPolicy() async {
  SharedPreferences.setMockInitialValues({});
  final policy = NetworkPolicy();
  await policy.init();
  return policy;
}

void main() {
  group('NetworkPolicy defaults', () {
    test('model and voice-model downloads are allowed out of the box', () async {
      final policy = await freshPolicy();
      expect(policy.isAllowed(NetworkFeature.modelDownload), isTrue);
      expect(policy.isAllowed(NetworkFeature.voiceModelDownload), isTrue);
    });

    test('features with no existing behavior default to denied', () async {
      final policy = await freshPolicy();
      expect(policy.isAllowed(NetworkFeature.cloudRewrite), isFalse);
      expect(policy.isAllowed(NetworkFeature.cloudSpeech), isFalse);
      expect(policy.isAllowed(NetworkFeature.sync), isFalse);
      expect(policy.isAllowed(NetworkFeature.updateCheck), isFalse);
    });

    test('the kill switch is off by default', () async {
      final policy = await freshPolicy();
      expect(policy.killSwitch, isFalse);
    });
  });

  group('NetworkPolicy.setFeatureEnabled', () {
    test('overrides the default for just that feature', () async {
      final policy = await freshPolicy();
      await policy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);

      expect(policy.isAllowed(NetworkFeature.cloudRewrite), isTrue);
      expect(policy.isAllowed(NetworkFeature.cloudSpeech), isFalse);
      expect(policy.isAllowed(NetworkFeature.modelDownload), isTrue);
    });

    test('can turn off a feature that defaults on', () async {
      final policy = await freshPolicy();
      await policy.setFeatureEnabled(NetworkFeature.modelDownload, false);
      expect(policy.isAllowed(NetworkFeature.modelDownload), isFalse);
    });
  });

  group('NetworkPolicy.setKillSwitch', () {
    test('blocks every feature regardless of its own setting', () async {
      final policy = await freshPolicy();
      await policy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      await policy.setKillSwitch(true);

      expect(policy.isAllowed(NetworkFeature.modelDownload), isFalse);
      expect(policy.isAllowed(NetworkFeature.voiceModelDownload), isFalse);
      expect(policy.isAllowed(NetworkFeature.cloudRewrite), isFalse);
    });

    test('turning it back off restores each feature\'s own setting', () async {
      final policy = await freshPolicy();
      await policy.setKillSwitch(true);
      await policy.setKillSwitch(false);

      expect(policy.isAllowed(NetworkFeature.modelDownload), isTrue);
      expect(policy.isAllowed(NetworkFeature.cloudRewrite), isFalse);
    });
  });

  test('reading before init throws rather than silently allowing everything', () {
    final policy = NetworkPolicy();
    expect(
      () => policy.isAllowed(NetworkFeature.modelDownload),
      throwsStateError,
    );
  });
}
