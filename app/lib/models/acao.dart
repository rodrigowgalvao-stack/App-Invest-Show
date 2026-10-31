enum Formato { multiplo, percentual, moeda, moedaCompacta }

/// Usado no comparador para destacar o melhor valor.
enum Melhor { maior, menor }

class Indicador {
  const Indicador(
    this.nome,
    this.valor,
    this.formato,
    this.ajuda, {
    this.melhor,
    this.soPositivos = false,
  });

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
  const PontoHistorico(this.data, this.fechamento);
  final DateTime data;
  final double fechamento;
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
    this.grupos = const [],
    this.temFundamentos = false,
  });

  final String ticker;
  final String nome;
  final String? setor;
  final double? preco;
  final double? variacaoPct;
  final double? minimo52;
  final double? maximo52;
  final List<PontoHistorico> historico;
  final List<GrupoIndicadores> grupos;
  final bool temFundamentos;

  factory Acao.fromJson(Map<String, dynamic> j) {
    final dks = _mapa(j['defaultKeyStatistics']);
    final fd = _mapa(j['financialData']);
    final sp = _mapa(j['summaryProfile']);

    final preco = numero(j['regularMarketPrice']) ?? numero(fd['currentPrice']);
    final lpa = numero(j['earningsPerShare']) ?? numero(dks['trailingEps']);
    final vpa = numero(dks['bookValue']);
    final divida = numero(fd['totalDebt']);
    final caixa = numero(fd['totalCash']);
    final ebitda = numero(fd['ebitda']);
    final dividaLiquida =
        (divida != null && caixa != null) ? divida - caixa : null;

    final grupos = <GrupoIndicadores>[
      GrupoIndicadores('Valuation', [
        Indicador('P/L', numero(j['priceEarnings']) ?? _div(preco, lpa),
            Formato.multiplo,
            'Preço ÷ lucro por ação. Quantos anos de lucro atual “pagam” a ação.',
            melhor: Melhor.menor, soPositivos: true),
        Indicador('P/VP', numero(dks['priceToBook']) ?? _div(preco, vpa),
            Formato.multiplo,
            'Preço ÷ valor patrimonial por ação. Abaixo de 1, a ação vale menos que o patrimônio.',
            melhor: Melhor.menor, soPositivos: true),
        Indicador('EV/EBITDA', numero(dks['enterpriseToEbitda']),
            Formato.multiplo,
            'Valor da firma (valor de mercado + dívida líquida) ÷ EBITDA.',
            melhor: Melhor.menor, soPositivos: true),
        Indicador('Dividend yield (12m)',
            _dy12m(j, preco) ?? _pctTalvez(numero(dks['dividendYield'])),
            Formato.percentual,
            'Proventos por ação com data-com nos últimos 12 meses ÷ preço atual.',
            melhor: Melhor.maior),
        Indicador('LPA', lpa, Formato.moeda,
            'Lucro líquido por ação nos últimos 12 meses.',
            melhor: Melhor.maior),
        Indicador('VPA', vpa, Formato.moeda,
            'Patrimônio líquido ÷ número de ações.'),
      ]),
      GrupoIndicadores('Rentabilidade', [
        Indicador('ROE', _pct(numero(fd['returnOnEquity'])), Formato.percentual,
            'Lucro líquido ÷ patrimônio líquido. Quanto a empresa rende sobre o capital dos acionistas.',
            melhor: Melhor.maior),
        Indicador('ROA', _pct(numero(fd['returnOnAssets'])), Formato.percentual,
            'Lucro ÷ ativos totais.',
            melhor: Melhor.maior),
        Indicador('Margem bruta', _pct(numero(fd['grossMargins'])),
            Formato.percentual, 'Lucro bruto ÷ receita.',
            melhor: Melhor.maior),
        Indicador('Margem EBITDA', _pct(numero(fd['ebitdaMargins'])),
            Formato.percentual, 'EBITDA ÷ receita.',
            melhor: Melhor.maior),
        Indicador('Margem líquida', _pct(numero(fd['profitMargins'])),
            Formato.percentual, 'Lucro líquido ÷ receita.',
            melhor: Melhor.maior),
      ]),
      GrupoIndicadores('Endividamento e liquidez', [
        Indicador('Dív. líquida/EBITDA', _div(dividaLiquida, ebitda),
            Formato.multiplo,
            'Quantos anos de EBITDA pagariam a dívida líquida. Negativo = caixa maior que a dívida.',
            melhor: Melhor.menor),
        Indicador('Dívida líquida', dividaLiquida, Formato.moedaCompacta,
            'Dívida bruta − caixa.'),
        Indicador('Liquidez corrente', numero(fd['currentRatio']),
            Formato.multiplo,
            'Ativo circulante ÷ passivo circulante. Acima de 1, cobre as obrigações de curto prazo.',
            melhor: Melhor.maior),
      ]),
      GrupoIndicadores('Tamanho e crescimento', [
        Indicador('Valor de mercado', numero(j['marketCap']),
            Formato.moedaCompacta, 'Preço × total de ações.'),
        Indicador('Receita (12m)', numero(fd['totalRevenue']),
            Formato.moedaCompacta, 'Receita líquida dos últimos 12 meses.'),
        Indicador('EBITDA (12m)', ebitda, Formato.moedaCompacta,
            'Lucro antes de juros, impostos, depreciação e amortização.'),
        Indicador('Crescimento da receita', _pct(numero(fd['revenueGrowth'])),
            Formato.percentual, 'Variação da receita contra o mesmo período do ano anterior.',
            melhor: Melhor.maior),
        Indicador('Crescimento do lucro', _pct(numero(fd['earningsGrowth'])),
            Formato.percentual, 'Variação do lucro contra o mesmo período do ano anterior.',
            melhor: Melhor.maior),
      ]),
    ];

    final historico = <PontoHistorico>[];
    for (final p in (j['historicalDataPrice'] as List? ?? const [])) {
      if (p is! Map) continue;
      final d = numero(p['date']);
      final c = numero(p['close']) ?? numero(p['adjustedClose']);
      if (d == null || c == null) continue;
      historico.add(PontoHistorico(
          DateTime.fromMillisecondsSinceEpoch(d.toInt() * 1000), c));
    }
    historico.sort((a, b) => a.data.compareTo(b.data));

    final ticker = '${j['symbol'] ?? ''}'.toUpperCase();
    return Acao(
      ticker: ticker,
      nome: '${j['longName'] ?? j['shortName'] ?? ticker}',
      setor: sp['sector'] as String?,
      preco: preco,
      variacaoPct: numero(j['regularMarketChangePercent']),
      minimo52: numero(j['fiftyTwoWeekLow']),
      maximo52: numero(j['fiftyTwoWeekHigh']),
      historico: historico,
      grupos: grupos,
      temFundamentos: fd.isNotEmpty || dks.isNotEmpty,
    );
  }
}

/// Aceita número, texto ou o formato {raw: x, fmt: "..."}.
double? numero(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is Map && v['raw'] is num) return (v['raw'] as num).toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

Map<String, dynamic> _mapa(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

double? _div(double? a, double? b) =>
    (a == null || b == null || b == 0) ? null : a / b;

/// A API devolve margens e retornos como fração (0,25 = 25%).
double? _pct(double? v) => v == null ? null : v * 100;

double? _pctTalvez(double? v) =>
    v == null ? null : (v.abs() < 1 ? v * 100 : v);

/// Soma os proventos com data-com nos últimos 12 meses.
double? _dy12m(Map<String, dynamic> j, double? preco) {
  final dados = j['dividendsData'];
  final lista = dados is Map ? dados['cashDividends'] : null;
  if (lista is! List || lista.isEmpty || preco == null || preco == 0) {
    return null;
  }
  final agora = DateTime.now();
  final corte = agora.subtract(const Duration(days: 365));
  var soma = 0.0;
  var achou = false;
  for (final d in lista) {
    if (d is! Map) continue;
    final data =
        DateTime.tryParse('${d['lastDatePrior'] ?? d['paymentDate'] ?? ''}');
    final valor = numero(d['rate']);
    if (data == null || valor == null) continue;
    if (data.isAfter(corte) && !data.isAfter(agora)) {
      soma += valor;
      achou = true;
    }
  }
  return achou ? soma / preco * 100 : null;
}
