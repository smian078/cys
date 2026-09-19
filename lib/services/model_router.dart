import '../core/constants/model_constants.dart';

class ModelRoute {
  const ModelRoute({
    required this.model,
    required this.useWeb,
    required this.useImages,
  });
  final String model;
  final bool useWeb;
  final bool useImages;
}

class ModelRouter {
  ModelRoute route({
    required String prompt,
    required bool forceWeb,
    required bool forceImage,
    required String selectedModel,
  }) {
    if (forceImage || _isImageIntent(prompt))
      return const ModelRoute(
        model: ModelIds.geminiImage,
        useWeb: false,
        useImages: true,
      );
    if (forceWeb || _isWebIntent(prompt))
      return ModelRoute(
        model: ModelIds.geminiResearch,
        useWeb: true,
        useImages: false,
      );
    return ModelRoute(model: selectedModel, useWeb: false, useImages: false);
  }

  bool _isWebIntent(String prompt) {
    final q = prompt.toLowerCase();
    const words = [
      'latest',
      'today',
      'right now',
      'current',
      'recent',
      'news',
      'price',
      'weather',
      'score',
      'schedule',
      'who is the current',
    ];
    return words.any(q.contains);
  }

  bool _isImageIntent(String prompt) {
    final q = prompt.toLowerCase();
    const words = [
      'image search',
      'find images',
      'show me pictures',
      'photos of',
      'pictures of',
      'find photos',
    ];
    return words.any(q.contains);
  }
}
