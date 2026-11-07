import 'acao.dart' show numero;

class Oportunidade {
  const Oportunidade({
    required this.ticker,
    required this.nome,
    this.setor,
    this.preco,
    this.precoJustoGraham,
    this.potencialGraham,
    this.precoJustoBazin,
    this.potencialBazin,
    this.pl,
    this.pvp,
    this.roe,
    this.margemLiquida,
    this.divLiqEbitda,
    this.dy,
    this.nota,
  });

  final String ticker;
  final String nome;
  final String? setor;
  final double? preco;
  final double? precoJustoGraham;
  final double? potencialGraham;
  final double? precoJustoBazin;
  final double? potencialBazin;
  final double? pl;
  final double? pvp;
  final double? roe;
  final double? margemLiquida;
  final double? divLiqEbitda;
  final double? dy;
  final double? nota;

  factory Oportunidade.fromJson(Map<String, dynamic> j) => Oportunidade(
        ticker: '${j['ticker'] ?? ''}',
        nome: '${j['nome'] ?? j['ticker'] ?? ''}',
        setor: j['setor'] as String?,
        preco: numero(j['preco']),
        precoJustoGraham: numero(j['preco_justo_graham']),
        potencialGraham: numero(j['potencial_graham']),
        precoJustoBazin: numero(j['preco_justo_bazin']),
        potencialBazin: numero(j['potencial_bazin']),
        pl: numero(j['pl']),
        pvp: numero(j['pvp']),
        roe: numero(j['roe']),
        margemLiquida: numero(j['margem_liquida']),
        divLiqEbitda: numero(j['div_liq_ebitda']),
        dy: numero(j['dy']),
        nota: numero(j['nota']),
      );
}

class RelatorioOportunidades {
  const RelatorioOportunidades({
    this.geradoEm,
    required this.analisadas,
    required this.aprovadas,
    required this.criterios,
    required this.itens,
    this.universo = const [],
  });

  final DateTime? geradoEm;
  final int analisadas;
  final int aprovadas;
  final Map<String, dynamic> criterios;
  final List<Oportunidade> itens;

  /// Todas as ações que o robô analisou (para o app refazer o ranking com
  /// o preço do dia). Vazio em arquivos gerados antes desta versão.
  final List<String> universo;

  factory RelatorioOportunidades.fromJson(Map<String, dynamic> j) =>
      RelatorioOportunidades(
        geradoEm: DateTime.tryParse('${j['gerado_em'] ?? ''}')?.toLocal(),
        analisadas: numero(j['analisadas'])?.toInt() ?? 0,
        aprovadas: numero(j['aprovadas'])?.toInt() ?? 0,
        criterios: j['criterios'] is Map
            ? Map<String, dynamic>.from(j['criterios'] as Map)
            : const {},
        itens: [
          for (final o in (j['oportunidades'] as List? ?? const []))
            if (o is Map) Oportunidade.fromJson(Map<String, dynamic>.from(o)),
        ],
        universo: [
          for (final t in (j['universo'] as List? ?? const []))
            if (t is String) t.toUpperCase(),
        ],
      );
}
