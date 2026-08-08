part of 'package:flutter_whisper/flutter_whisper.dart';

/// Whisper model variants with sizes and characteristics.
enum WhisperModel {
  /// 74 MiB, multilingual, fastest, lowest accuracy
  tiny,

  /// 141 MiB, multilingual, better accuracy
  base,

  /// 465 MiB, multilingual, good accuracy
  small,

  /// 1.43 GiB, multilingual, high accuracy
  medium,

  /// 2.88 GiB, multilingual, highest accuracy (large-v3)
  large;

  /// Approximate file size in bytes (actual ggml-*.bin from HF).
  int get fileSizeBytes => switch (this) {
        WhisperModel.tiny => 77691713,
        WhisperModel.base => 147951465,
        WhisperModel.small => 487601967,
        WhisperModel.medium => 1533763059,
        WhisperModel.large => 3095033483,
      };

  /// Human-readable size string.
  String get fileSizeHuman => switch (this) {
        WhisperModel.tiny => '74 MB',
        WhisperModel.base => '141 MB',
        WhisperModel.small => '465 MB',
        WhisperModel.medium => '1.43 GB',
        WhisperModel.large => '2.88 GB',
      };

  String get sha256 => switch (this) {
        WhisperModel.tiny =>
          'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
        WhisperModel.base =>
          '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
        WhisperModel.small =>
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
        WhisperModel.medium =>
          '6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208',
        WhisperModel.large =>
          '64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2',
      };

  /// Whether model supports non-English languages.
  bool get isMultilingual => true;

  /// Download URL for the model.
  String get downloadUrl {
    final remoteName = this == WhisperModel.large ? 'large-v3' : name;
    return 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
        'ggml-$remoteName.bin';
  }
}
