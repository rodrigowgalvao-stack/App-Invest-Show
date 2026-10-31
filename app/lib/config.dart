/// Valores passados na compilação, para não ficarem gravados no código:
///   flutter run --dart-define=BRAPI_TOKEN=seu_token \
///     --dart-define=OPORTUNIDADES_URL=https://raw.githubusercontent.com/USUARIO/REPO/main/dados/oportunidades.json
const String brapiToken = String.fromEnvironment('BRAPI_TOKEN');
const String oportunidadesUrl = String.fromEnvironment('OPORTUNIDADES_URL');

/// O robô grava fundamentos.json na mesma pasta do ranking.
String get fundamentosUrl {
  const definido = String.fromEnvironment('FUNDAMENTOS_URL');
  if (definido.isNotEmpty) return definido;
  if (oportunidadesUrl.isEmpty) return '';
  final i = oportunidadesUrl.lastIndexOf('/');
  return '${oportunidadesUrl.substring(0, i + 1)}fundamentos.json';
}
