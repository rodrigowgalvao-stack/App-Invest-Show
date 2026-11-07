import 'dart:math' as math;

import 'acao.dart' show numero;
import 'fundamentos.dart';
import 'oportunidade.dart';

/// Mesmos filtros e mesma nota do robô (screener/screener.py), refeitos no
/// app com o preço mais recente. Os balanços só mudam a cada trimestre;
/// o que move o ranking no dia a dia é o preço.
const _balancoMaxDias = 400;
const _pesos = {
  'roe': 0.30,
  'margem_liquida': 0.20,
  'rendimento_lucro': 0.25,
  'potencial': 0.25,
};

class _Metricas {
  _Metricas({
    required this.ticker,
    required this.nome,
    required this.setor,
    required this.f,
    required this.preco,
    required this.taxaBazin,
  });

  final String ticker;
  final String nome;
  final String? setor;
  final Fundamentos f;
  final double preco;
  final double taxaBazin;
  double nota = 0;

  double? get lpa => f.lpa;
  double? get vpa => f.vpa;
  double? get dpa => f.dpa;

  /// Valor de mercado acompanha o preço desde a data do robô.
  double? get valorMercado =>
      (f.valorMercado != null && (f.precoRef ?? 0) > 0)
          ? f.valorMercado! * preco / f.precoRef!
          : f.valorMercado;

  double? get pl => lpa == null || lpa == 0 ? null : preco / lpa!;
  double? get pvp => vpa == null || vpa == 0 ? null : preco / vpa!;
  double? get dy => dpa == null ? null : dpa! / preco * 100;

  double? get graham => (lpa != null && vpa != null && lpa! > 0 && vpa! > 0)
      ? math.sqrt(22.5 * lpa! * vpa!)
      : null;
  double? get bazin =>
      (dpa != null && dpa != 0) ? dpa! / (taxaBazin / 100) : null;
  double? _potencial(double? justo) =>
      justo == null || justo == 0 ? null : (justo / preco - 1) * 100;
  double? get potencialGraham => _potencial(graham);
  double? get potencialBazin => _potencial(bazin);

  Oportunidade paraOportunidade() => Oportunidade(
        ticker: ticker,
        nome: nome,
        setor: setor,
        preco: preco,
        precoJustoGraham: graham,
        potencialGraham: potencialGraham,
        precoJustoBazin: bazin,
        potencialBazin: potencialBazin,
        pl: pl,
        pvp: pvp,
        roe: f.roe,
        margemLiquida: f.margemLiquida,
        divLiqEbitda: f.divLiqEbitda,
        dy: dy,
        nota: nota,
      );
}

/// Motivo da reprovação, ou null se passou (igual a `reprovar` do robô).
String? _reprovar(_Metricas m, Map<String, dynamic> c, DateTime hoje) {
  double? crit(String k) => numero(c[k]);
  final data = m.f.dataBalanco;
  if (data != null && hoje.difference(data).inDays > _balancoMaxDias) {
    return 'balanço desatualizado';
  }
  final vmMin = crit('valor_mercado_min');
  if (vmMin != null && m.valorMercado != null && m.valorMercado! < vmMin) {
    return 'valor de mercado pequeno';
  }
  if (m.lpa == null || m.lpa! <= 0) return 'lucro zero ou negativo';
  if (m.vpa == null || m.vpa! <= 0) return 'patrimônio zero ou negativo';
  final roeMin = crit('roe_min');
  if (m.f.roe == null || (roeMin != null && m.f.roe! < roeMin)) {
    return 'ROE abaixo do mínimo';
  }
  final mlMin = crit('margem_liquida_min');
  if (mlMin != null && m.f.margemLiquida != null && m.f.margemLiquida! <= mlMin) {
    return 'margem líquida baixa';
  }
  final divMax = crit('div_liq_ebitda_max');
  if (divMax != null && m.f.divLiqEbitda != null && m.f.divLiqEbitda! > divMax) {
    return 'dívida alta';
  }
  final plMax = crit('pl_max');
  if (plMax != null && m.pl != null && m.pl! > plMax) {
    return 'P/L acima do máximo';
  }
  if ((m.potencialGraham ?? -1) <= 0 && (m.potencialBazin ?? -1) <= 0) {
    return 'preço acima do preço justo (Graham e Bazin)';
  }
  return null;
}

/// 0 = pior, 1 = melhor (maior). null continua null.
List<double?> percentis(List<double?> valores) {
  final validos = [for (final v in valores) if (v != null) v]..sort();
  final n = validos.length;
  int esquerda(double v) {
    var lo = 0, hi = n;
    while (lo < hi) {
      final meio = (lo + hi) >> 1;
      if (validos[meio] < v) {
        lo = meio + 1;
      } else {
        hi = meio;
      }
    }
    return lo;
  }

  return [
    for (final v in valores)
      v == null ? null : (n > 1 ? esquerda(v) / (n - 1) : 1.0),
  ];
}

void _pontuar(List<_Metricas> aprovadas) {
  double? maiorPotencial(_Metricas m) {
    final p = [m.potencialGraham, m.potencialBazin].whereType<double>();
    return p.isEmpty ? null : p.reduce(math.max);
  }

  final fatores = {
    'roe': [for (final m in aprovadas) m.f.roe],
    'margem_liquida': [for (final m in aprovadas) m.f.margemLiquida],
    'rendimento_lucro': [
      for (final m in aprovadas)
        m.pl == null || m.pl == 0 ? null : 100 / m.pl!,
    ],
    'potencial': [for (final m in aprovadas) maiorPotencial(m)],
  };
  final soma = List.filled(aprovadas.length, 0.0);
  final pesos = List.filled(aprovadas.length, 0.0);
  for (final e in fatores.entries) {
    final p = percentis(e.value);
    for (var i = 0; i < p.length; i++) {
      if (p[i] != null) {
        soma[i] += _pesos[e.key]! * p[i]!;
        pesos[i] += _pesos[e.key]!;
      }
    }
  }
  for (var i = 0; i < aprovadas.length; i++) {
    aprovadas[i].nota = pesos[i] > 0 ? soma[i] / pesos[i] * 100 : 0;
  }
}

/// Refaz o ranking do robô com [precos] (ticker → preço atual). Usa o
/// universo completo que o robô analisou; se o arquivo for antigo e não
/// tiver essa lista, refaz só entre as ações que já estavam no ranking.
/// Ativo sem preço novo fica com o preço do robô.
RelatorioOportunidades recalcularRanking(
  RelatorioOportunidades base,
  Map<String, Fundamentos> fundamentos,
  Map<String, double> precos, {
  DateTime? hoje,
}) {
  final dia = hoje ?? DateTime.now();
  final taxaBazin = numero(base.criterios['taxa_bazin']) ?? 6;
  final porTicker = {for (final o in base.itens) o.ticker: o};
  // Arquivo antigo e nenhum preço novo: refazer só mudaria a escala da nota.
  if (base.universo.isEmpty &&
      !base.itens.any((o) => precos.containsKey(o.ticker))) {
    return base;
  }
  final universo = base.universo.isNotEmpty
      ? base.universo
      : [for (final o in base.itens) o.ticker];

  final metricas = <_Metricas>[];
  for (final t in universo) {
    final f = fundamentos[t];
    final preco = precos[t] ?? f?.precoRef ?? porTicker[t]?.preco;
    if (f == null || preco == null || preco <= 0) continue;
    metricas.add(_Metricas(
      ticker: t,
      nome: porTicker[t]?.nome ?? f.nome ?? t,
      setor: porTicker[t]?.setor ?? f.setor,
      f: f,
      preco: preco,
      taxaBazin: taxaBazin,
    ));
  }
  // Sem os balanços (arquivo não baixou), não dá para refazer: fica o do robô.
  if (metricas.isEmpty) return base;

  final aprovadas = [
    for (final m in metricas)
      if (_reprovar(m, base.criterios, dia) == null) m,
  ];
  _pontuar(aprovadas);
  aprovadas.sort((a, b) => b.nota.compareTo(a.nota));

  final top = numero(base.criterios['top'])?.toInt() ?? 15;
  return RelatorioOportunidades(
    geradoEm: base.geradoEm,
    analisadas: base.universo.isNotEmpty ? metricas.length : base.analisadas,
    aprovadas: base.universo.isNotEmpty ? aprovadas.length : base.aprovadas,
    criterios: base.criterios,
    universo: base.universo,
    itens: [for (final m in aprovadas.take(top)) m.paraOportunidade()],
  );
}
