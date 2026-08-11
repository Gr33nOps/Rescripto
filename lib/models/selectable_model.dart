import 'ai_model.dart';
import 'provider_config.dart';

/// A model as offered to the user at the picker boundary — local or cloud.
///
/// Deliberately not a unification of [AiModel] and a cloud model type.
/// [AiModel] describes a file to download and verify (`fileName`, `sha256`,
/// `sizeBytes`, `quant`); none of that exists for a cloud model, and forcing
/// them into one type produces something where half the fields are
/// meaningless for either case. This is presentation-only, built fresh at
/// the picker rather than persisted, so it can freely combine two otherwise
/// unrelated sources.
sealed class SelectableModel {
  const SelectableModel();

  String get label;
}

/// An on-device GGUF model from [ModelCatalog].
final class LocalSelectableModel extends SelectableModel {
  const LocalSelectableModel(this.model);

  final AiModel model;

  @override
  String get label => model.displayName;
}

/// A model offered by a configured cloud provider.
final class CloudSelectableModel extends SelectableModel {
  const CloudSelectableModel({required this.provider, required this.model});

  final ProviderConfig provider;
  final ProviderModelEntry model;

  @override
  String get label => '${model.displayName} · ${provider.displayName}';
}
