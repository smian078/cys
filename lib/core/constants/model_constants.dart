class ModelIds {
  static const nemotronSuper = 'nvidia/nemotron-3-super-120b-a12b';
  static const nemotronNanoOmni =
      'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning';
  static const nemotronUltra = 'nvidia/nemotron-3-ultra-550b-a55b';
  static const geminiResearch = 'gemini-3.8-flash';
  static const geminiImage = 'gemini-3.1-flash-image';
}

class ModelDefinition {
  const ModelDefinition({
    required this.id,
    required this.name,
    required this.role,
  });
  final String id;
  final String name;
  final String role;
}

const models = [
  ModelDefinition(
    id: ModelIds.nemotronSuper,
    name: 'Nemotron 3 Super',
    role: 'Main brain',
  ),
  ModelDefinition(
    id: ModelIds.nemotronNanoOmni,
    name: 'Nemotron 3 Nano Omni',
    role: 'Private attachment analyst',
  ),
  ModelDefinition(
    id: ModelIds.nemotronUltra,
    name: 'Nemotron 3 Ultra',
    role: 'High-capability optional brain',
  ),
  ModelDefinition(
    id: ModelIds.geminiResearch,
    name: 'Gemini 3.8 Flash',
    role: 'Live web researcher',
  ),
  ModelDefinition(
    id: ModelIds.geminiImage,
    name: 'Gemini 3.1 Flash Image',
    role: 'Google Image Search / image generation layer',
  ),
];
