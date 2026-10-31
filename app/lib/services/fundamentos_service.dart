import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/fundamentos.dart';

/// Lê os indicadores que o robô do GitHub calcula toda semana a partir
/// dos balanços da CVM. Baixa o arquivo uma vez e guarda por uma hora.
class FundamentosService {
  FundamentosService({http.Client? client}) : _client = client ?? http.Client();

  static const _validade = Duration(hours: 1);

  final http.Client _client;
  Map<String, Fundamentos>? _porTicker;
  DateTime? _quando;
  Future<Map<String, Fundamentos>>? _carregando;

  /// null quando o ativo não tem balanço na CVM (FIIs, ETFs, BDRs) ou o
  /// arquivo não pôde ser baixado: a tela mostra só a cotação.
  Future<Fundamentos?> de(String ticker) async {
    try {
      return (await _todos())[ticker.toUpperCase()];
    } catch (_) {
      return null;
    }
  }

  /// Todas as ações com balanço na CVM: alimenta a busca por nome.
  Future<Map<String, Fundamentos>> todos() async {
    try {
      return await _todos();
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, Fundamentos>> _todos() {
    final emCache = _porTicker;
    if (emCache != null &&
        _quando != null &&
        DateTime.now().difference(_quando!) < _validade) {
      return Future.value(emCache);
    }
    // Várias telas pedem ao mesmo tempo: um download só.
    return _carregando ??= _baixar().whenComplete(() => _carregando = null);
  }

  Future<Map<String, Fundamentos>> _baixar() async {
    if (fundamentosUrl.isEmpty) return const {};
    final r = await _client
        .get(Uri.parse(fundamentosUrl))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final acoes = j is Map ? j['acoes'] : null;
    final mapa = <String, Fundamentos>{
      if (acoes is Map)
        for (final e in acoes.entries)
          if (e.value is Map)
            '${e.key}': Fundamentos.fromJson(Map<String, dynamic>.from(e.value as Map)),
    };
    _porTicker = mapa;
    _quando = DateTime.now();
    return mapa;
  }
}
