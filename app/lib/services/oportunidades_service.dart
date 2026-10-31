import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/oportunidade.dart';
import 'brapi_service.dart' show BrapiException;

/// Lê o ranking que o robô do GitHub publica toda semana.
class OportunidadesService {
  OportunidadesService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<RelatorioOportunidades> carregar() async {
    if (oportunidadesUrl.isEmpty) {
      throw BrapiException(
          'Endereço do ranking não configurado. Passe OPORTUNIDADES_URL na compilação (veja o README).');
    }
    final uri = Uri.parse(oportunidadesUrl);
    http.Response r;
    try {
      r = await _client.get(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw BrapiException('Tempo esgotado. Verifique sua conexão.');
    } catch (_) {
      throw BrapiException('Sem conexão com a internet.');
    }
    if (r.statusCode == 404) {
      throw BrapiException(
          'Ranking ainda não gerado. Rode o workflow “Screener semanal” no GitHub.');
    }
    if (r.statusCode != 200) {
      throw BrapiException('Erro ${r.statusCode} ao baixar o ranking.');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is! Map) throw BrapiException('Arquivo de ranking inválido.');
    return RelatorioOportunidades.fromJson(Map<String, dynamic>.from(j));
  }
}
