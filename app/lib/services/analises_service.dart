import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/analise.dart';

/// Lê as leituras do Gemini que o robô grava toda semana para as ações do
/// ranking. Baixa o arquivo uma vez e guarda por uma hora.
class AnalisesService {
  AnalisesService({http.Client? client}) : _client = client ?? http.Client();

  /// Instância usada pelas telas.
  static final padrao = AnalisesService();

  static const _validade = Duration(hours: 1);

  final http.Client _client;
  Map<String, Analise>? _porTicker;
  DateTime? _quando;
  Future<Map<String, Analise>>? _carregando;

  /// null quando a ação não está no ranking, a IA não está ligada no robô
  /// ou o arquivo não pôde ser baixado.
  Future<Analise?> de(String ticker) async {
    try {
      return (await _todas())[ticker.toUpperCase()];
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Analise>> _todas() {
    final emCache = _porTicker;
    if (emCache != null &&
        _quando != null &&
        DateTime.now().difference(_quando!) < _validade) {
      return Future.value(emCache);
    }
    return _carregando ??= _baixar().whenComplete(() => _carregando = null);
  }

  Future<Map<String, Analise>> _baixar() async {
    if (analisesUrl.isEmpty) return const {};
    final r = await _client
        .get(Uri.parse(analisesUrl))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 404) return const {}; // IA ainda não ligada no robô
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final mapa = analisesDeJson(jsonDecode(utf8.decode(r.bodyBytes)));
    _porTicker = mapa;
    _quando = DateTime.now();
    return mapa;
  }
}

Map<String, Analise> analisesDeJson(Object? j) {
  if (j is! Map) return const {};
  final modelo = j['modelo'] as String?;
  final geradoEm = DateTime.tryParse(j['gerado_em'] as String? ?? '');
  final acoes = j['acoes'];
  return {
    if (acoes is Map)
      for (final e in acoes.entries)
        if (e.value is Map)
          '${e.key}': Analise.fromJson(Map<String, dynamic>.from(e.value as Map),
              modelo: modelo, geradoEm: geradoEm),
  };
}
