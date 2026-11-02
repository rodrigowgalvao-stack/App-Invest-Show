import 'fundamentos.dart';

enum Formato { multiplo, percentual, moeda, moedaCompacta }

/// Usado no comparador para destacar o melhor valor.
enum Melhor { maior, menor }

enum Comparacao {
  menor('<'),
  menorIgual('≤'),
  maior('>'),
  maiorIgual('≥');

  const Comparacao(this.simbolo);
  final String simbolo;
}

/// Valor de referência da literatura (Graham, Bazin, Buffett...) ou da
/// prática de mercado. É régua, não regra: setores diferentes têm faixas
/// diferentes.
class Referencia {
  const Referencia(this.comparacao, this.limite, this.fonte,
      {this.rotuloLimite});

  final Comparacao comparacao;
  final double limite;

  /// Quem propôs, ex.: "Graham".
  final String fonte;

  /// Substitui o número formatado, ex.: "preço atual".
  final String? rotuloLimite;

  /// null quando não há valor para comparar.
  bool? atende(double? v) {
    if (v == null || !v.isFinite) return null;
    return switch (comparacao) {
      Comparacao.menor => v < limite,
      Comparacao.menorIgual => v <= limite,
      Comparacao.maior => v > limite,
      Comparacao.maiorIgual => v >= limite,
    };
  }
}

class Indicador {
  const Indicador(
    this.nome,
    this.valor,
    this.formato,
    this.ajuda, {
    this.melhor,
    this.soPositivos = false,
    this.referencia,
  });

  final Referencia? referencia;

  /// Prejuízo deixa P/L negativo, "abaixo de 15", mas não é bom sinal.
  bool? get atendeReferencia {
    final r = referencia?.atende(valor);
    if (r == true && soPositivos && valor! <= 0) return false;
    return r;
  }

  final String nome;
  final double? valor;
  final Formato formato;
  final String ajuda;
  final Melhor? melhor;

  /// Para múltiplos como P/L: valor negativo (prejuízo) não conta como "melhor".
  final bool soPositivos;
}

class GrupoIndicadores {
  const GrupoIndicadores(this.titulo, this.itens);
  final String titulo;
  final List<Indicador> itens;
}

class PontoHistorico {
  const PontoHistorico(
    this.data,
    this.fechamento, {
    double? abertura,
    double? maxima,
    double? minima,
    this.volume,
  })  : abertura = abertura ?? fechamento,
        maxima = maxima ?? fechamento,
        minima = minima ?? fechamento;

  final DateTime data;
  final double fechamento;

  /// Sem o dado, ficam iguais ao fechamento (candle vira um traço).
  final double abertura;
  final double maxima;
  final double minima;
  final double? volume;
}

class Acao {
  const Acao({
    required this.ticker,
    required this.nome,
    this.setor,
    this.preco,
    this.variacaoPct,
    this.minimo52,
    this.maximo52,
    this.historico = const [],
    this.fundamentos,
  });

  final String ticker;
  final String nome;
  final String? setor;
  final double? preco;
  final double? variacaoPct;
  final double? minimo52;
  final double? maximo52;
  final List<PontoHistorico> historico;

  /// Vem do robô (balanços da CVM), não da brapi.
  final Fundamentos? fundamentos;

  bool get temFundamentos => fundamentos != null;
  List<GrupoIndicadores> get grupos => gruposIndicadores(fundamentos, preco);

  /// Cotação e histórico da brapi; os indicadores entram à parte.
  factory Acao.fromJson(Map<String, dynamic> j, {Fundamentos? fundamentos}) {
    final historico = <PontoHistorico>[];
    for (final p in (j['historicalDataPrice'] as List? ?? const [])) {
      if (p is! Map) continue;
      final d = numero(p['date']);
      final c = numero(p['close']) ?? numero(p['adjustedClose']);
      if (d == null || c == null) continue;
      historico.add(PontoHistorico(
        DateTime.fromMillisecondsSinceEpoch(d.toInt() * 1000),
        c,
        abertura: _positivo(p['open']),
        maxima: _positivo(p['high']),
        minima: _positivo(p['low']),
        volume: numero(p['volume']),
      ));
    }
    historico.sort((a, b) => a.data.compareTo(b.data));

    final ticker = '${j['symbol'] ?? ''}'.toUpperCase();
    return Acao(
      ticker: ticker,
      nome: '${j['longName'] ?? j['shortName'] ?? ticker}',
      setor: fundamentos?.setor,
      preco: numero(j['regularMarketPrice']),
      variacaoPct: numero(j['regularMarketChangePercent']),
      minimo52: numero(j['fiftyTwoWeekLow']),
      maximo52: numero(j['fiftyTwoWeekHigh']),
      historico: historico,
      fundamentos: fundamentos,
    );
  }
}

/// A brapi às vezes manda 0 em abertura/máxima/mínima quando não tem o dado.
double? _positivo(dynamic v) {
  final x = numero(v);
  return (x == null || x <= 0) ? null : x;
}

/// Aceita número, texto ou o formato {raw: x, fmt: "..."}.
double? numero(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is Map && v['raw'] is num) return (v['raw'] as num).toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

double? dividir(double? a, double? b) =>
    (a == null || b == null || b == 0) ? null : a / b;
