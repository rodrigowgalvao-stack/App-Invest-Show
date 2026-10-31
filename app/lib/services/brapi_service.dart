import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/acao.dart';
import 'fundamentos_service.dart';

class BrapiException implements Exception {
  BrapiException(this.mensagem);
  final String mensagem;

  @override
  String toString() => mensagem;
}

/// Resultado de uma consulta que pode ter falhado, para que um ticker
/// com erro não derrube a lista inteira.
class ResultadoCotacao {
  const ResultadoCotacao(this.ticker, {this.acao, this.erro});
  final String ticker;
  final Acao? acao;
  final String? erro;
}

/// Cotação e histórico vêm da brapi (liberados no plano gratuito); os
/// indicadores vêm do arquivo que o robô gera com os balanços da CVM.
class BrapiService {
  BrapiService({http.Client? client, FundamentosService? fundamentos})
      : _client = client ?? http.Client(),
        _fundamentos = fundamentos ?? FundamentosService(client: client);

  static const _base = 'https://brapi.dev/api';
  static const _validadeCache = Duration(minutes: 5);

  final http.Client _client;
  final FundamentosService _fundamentos;
  final Map<String, _ItemCache> _cache = {};

  Map<String, String> get _headers =>
      brapiToken.isEmpty ? const {} : {'Authorization': 'Bearer $brapiToken'};

  /// [completo] = true traz histórico e indicadores fundamentalistas.
  Future<Acao> cotacao(
    String ticker, {
    bool completo = false,
    String range = '3mo',
    bool forcar = false,
  }) async {
    final t = ticker.trim().toUpperCase();
    final chave = completo ? '$t|$range' : t;
    final emCache = _cache[chave];
    if (!forcar &&
        emCache != null &&
        DateTime.now().difference(emCache.quando) < _validadeCache) {
      return emCache.acao;
    }

    final params = <String, String>{
      if (completo) ...{'range': range, 'interval': '1d'},
    };
    final fundamentos = completo ? _fundamentos.de(t) : null;
    final uri = Uri.parse('$_base/quote/$t')
        .replace(queryParameters: params.isEmpty ? null : params);

    http.Response r;
    try {
      r = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw BrapiException('Tempo esgotado. Verifique sua conexão.');
    } catch (_) {
      throw BrapiException('Sem conexão com a internet.');
    }

    if (r.statusCode != 200) throw BrapiException(_mensagemErro(r));

    final body = jsonDecode(utf8.decode(r.bodyBytes));
    final results = body is Map ? body['results'] : null;
    if (results is! List || results.isEmpty) {
      throw BrapiException('$t não encontrado.');
    }
    final acao = Acao.fromJson(Map<String, dynamic>.from(results.first as Map),
        fundamentos: await fundamentos);
    _cache[chave] = _ItemCache(acao, DateTime.now());
    return acao;
  }

  Future<ResultadoCotacao> resultado(
    String ticker, {
    bool completo = false,
    bool forcar = false,
  }) async {
    try {
      final a = await cotacao(ticker, completo: completo, forcar: forcar);
      return ResultadoCotacao(ticker, acao: a);
    } catch (e) {
      return ResultadoCotacao(ticker, erro: e.toString());
    }
  }

  /// Uma requisição por ativo (o plano gratuito limita ativos por chamada).
  Future<List<ResultadoCotacao>> varias(
    List<String> tickers, {
    bool completo = false,
    bool forcar = false,
  }) =>
      Future.wait(tickers
          .map((t) => resultado(t, completo: completo, forcar: forcar)));

  String _mensagemErro(http.Response r) {
    String? msg;
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map && j['message'] is String) msg = j['message'] as String;
    } catch (_) {}
    final base = switch (r.statusCode) {
      401 => 'Token inválido ou ausente.',
      402 || 403 => 'Recurso fora do seu plano da brapi ou ativo não liberado sem token.',
      404 => 'Ativo não encontrado.',
      429 => 'Limite de requisições atingido. Tente mais tarde.',
      _ => 'Erro ${r.statusCode} ao consultar a brapi.',
    };
    return msg == null ? base : '$base\n$msg';
  }
}

class _ItemCache {
  _ItemCache(this.acao, this.quando);
  final Acao acao;
  final DateTime quando;
}
