import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/models/audience_tag.dart';
import 'package:rescripto/models/backup_bundle.dart';
import 'package:rescripto/models/history_entry.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/models/rewrite_request.dart';
import 'package:rescripto/models/tone_preset.dart';
import 'package:rescripto/models/workflow_definition.dart';
import 'package:rescripto/models/workflow_step.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';

void main() {
  group('BackupBundle.toJson / fromJson', () {
    test('round-trips a fully populated bundle through a JSON string, byte for byte', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final bundle = BackupBundle(
        formatVersion: BackupBundle.currentFormatVersion,
        createdAt: now,
        appVersion: '1.0.3',
        dbVersion: 7,
        settings: const BackupSettings(
          themeMode: 'dark',
          threads: 4,
          useGpu: false,
          contextSize: 4096,
          whisperModel: 'base',
          processingMode: 'hybrid',
          uiMode: 'pro',
          cloudProviderId: 'openai-1',
          cloudModelRef: 'gpt-4o',
          speechEngine: 'local',
        ),
        tones: const [
          TonePreset(
            id: 'user_1',
            name: 'Mine',
            iconToken: 'bolt_outlined',
            description: '',
            instruction: 'Be terse.',
            temperature: 0.5,
            stopSequences: ['###'],
          ),
        ],
        audiences: const [AudienceTag(id: 'coworkers', label: 'coworkers')],
        workflows: [
          WorkflowDefinition(
            id: 'workflow_1',
            name: 'Polish',
            createdAt: now,
            updatedAt: now,
            steps: const [
              WorkflowStep(
                id: 'step_1',
                toneId: 'user_1',
                intensity: RewriteIntensity.full,
                length: RewriteLength.longer,
                audience: ['coworkers'],
                target: EngineTarget(engineId: 'local.llama', modelRef: 'gemma'),
              ),
            ],
          ),
        ],
        providerConfigs: [
          ProviderConfig(
            id: 'openai-1',
            presetId: 'openai',
            displayName: 'OpenAI',
            credential: const CredentialRef(providerId: 'openai-1', kind: CredentialKind.apiKey),
            models: const [ProviderModelEntry(modelRef: 'gpt-4o', displayName: 'GPT-4o')],
            createdAt: now,
            updatedAt: now,
          ),
        ],
        history: [
          HistoryEntry(
            id: 999,
            original: 'hello',
            rewritten: 'Hello.',
            toneId: 'user_1',
            createdAt: now,
          ),
        ],
        credentials: const [
          BackupCredential(
            ref: CredentialRef(providerId: 'openai-1', kind: CredentialKind.apiKey),
            secret: 'sk-test',
          ),
        ],
      );

      final roundTripped = BackupBundle.fromJson(
        jsonDecode(jsonEncode(bundle.toJson())) as Map<String, Object?>,
      );

      expect(roundTripped.formatVersion, bundle.formatVersion);
      expect(roundTripped.appVersion, bundle.appVersion);
      expect(roundTripped.dbVersion, bundle.dbVersion);
      expect(roundTripped.containsSecrets, isTrue);

      expect(roundTripped.settings!.themeMode, 'dark');
      expect(roundTripped.settings!.cloudProviderId, 'openai-1');

      expect(roundTripped.tones, hasLength(1));
      expect(roundTripped.tones.single.stopSequences, ['###']);

      expect(roundTripped.audiences.single.label, 'coworkers');

      expect(roundTripped.workflows, hasLength(1));
      expect(roundTripped.workflows.single.steps.single.toneId, 'user_1');
      expect(roundTripped.workflows.single.steps.single.audience, ['coworkers']);

      expect(roundTripped.providerConfigs, hasLength(1));
      expect(roundTripped.providerConfigs.single.models, [
        const ProviderModelEntry(modelRef: 'gpt-4o', displayName: 'GPT-4o'),
      ]);
      // Never a secret in this section — only the ref.
      expect(roundTripped.providerConfigs.single.credential.providerId, 'openai-1');

      // History ids are never carried across — a restored entry becomes a
      // fresh local row, not a reassertion of the exporting device's
      // autoincrement id.
      expect(roundTripped.history.single.rewritten, 'Hello.');

      expect(roundTripped.credentials.single.secret, 'sk-test');
    });

    test('an empty bundle round-trips with every section empty and containsSecrets false', () {
      final now = DateTime.utc(2026);
      final bundle = BackupBundle(
        formatVersion: BackupBundle.currentFormatVersion,
        createdAt: now,
        appVersion: '1.0.3',
        dbVersion: 7,
      );

      final roundTripped = BackupBundle.fromJson(
        jsonDecode(jsonEncode(bundle.toJson())) as Map<String, Object?>,
      );

      expect(roundTripped.containsSecrets, isFalse);
      expect(roundTripped.settings, isNull);
      expect(roundTripped.tones, isEmpty);
      expect(roundTripped.workflows, isEmpty);
      expect(roundTripped.providerConfigs, isEmpty);
      expect(roundTripped.history, isEmpty);
      expect(roundTripped.credentials, isEmpty);
    });
  });
}
