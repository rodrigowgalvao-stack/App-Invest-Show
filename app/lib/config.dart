/// Valores passados na compilação, para não ficarem gravados no código:
///   flutter run --dart-define=BRAPI_TOKEN=seu_token \
///     --dart-define=OPORTUNIDADES_URL=https://raw.githubusercontent.com/USUARIO/REPO/main/dados/oportunidades.json
const String brapiToken = String.fromEnvironment('BRAPI_TOKEN');
const String oportunidadesUrl = String.fromEnvironment('OPORTUNIDADES_URL');
