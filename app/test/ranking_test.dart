import 'dart:convert';
import 'dart:io';

import 'package:acoes_app/models/fundamentos.dart';
import 'package:acoes_app/models/oportunidade.dart';
import 'package:acoes_app/models/ranking.dart';
import 'package:flutter_test/flutter_test.dart';

/// ranking_esperado.json foi gerado rodando reprovar() e pontuar() do robô
/// (screener/screener.py) sobre um retrato de dados/fundamentos.json, com
/// 1 em cada 3 ações 30% mais barata. O app tem de chegar no mesmo ranking.
void main() {
  final j = jsonDecode(File('test/ranking_esperado.json').readAsStringSync())
      as Map<String, dynamic>;
  final fundamentos = {
    for (final e in (j['fundamentos'] as Map).entries)
      e.key as String:
          Fundamentos.fromJson(Map<String, dynamic>.from(e.value as Map)),
  };
  final precos = {
    for (final e in (j['precos'] as Map).entries)
      e.key as String: (e.value as num).toDouble(),
  };
  final base = RelatorioOportunidades(
    analisadas: 0,
    aprovadas: 0,
    criterios: const {
      'valor_mercado_min': 500000000.0,
      'roe_min': 10.0,
      'margem_liquida_min': 0.0,
      'div_liq_ebitda_max': 3.0,
      'pl_max': 30.0,
      'taxa_bazin': 6.0,
      'top': 15,
    },
    itens: const [],
    universo: [for (final t in j['universo'] as List) t as String],
  );

  test('mesmo ranking que o robô em Python', () {
    final r = recalcularRanking(base, fundamentos, precos,
        hoje: DateTime.parse(j['hoje'] as String));
    final esperado = j['top'] as List;
    expect(r.analisadas, j['analisadas']);
    expect(r.aprovadas, j['aprovadas']);
    expect([for (final o in r.itens) o.ticker],
        [for (final e in esperado) e[0]]);
    for (var i = 0; i < esperado.length; i++) {
      expect(r.itens[i].nota, closeTo((esperado[i][1] as num).toDouble(), 1e-6));
    }
  });

  test('preço novo muda o ranking', () {
    final hoje = DateTime.parse(j['hoje'] as String);
    final antes = recalcularRanking(base, fundamentos, precos, hoje: hoje);
    final lider = antes.itens.first;
    // Líder sobe 10x: passa do preço justo e do P/L máximo, sai do ranking.
    final depois = recalcularRanking(
        base, fundamentos, {...precos, lider.ticker: lider.preco! * 10},
        hoje: hoje);
    expect(depois.itens.map((o) => o.ticker), isNot(contains(lider.ticker)));
    expect(depois.aprovadas, antes.aprovadas - 1);
  });

  test('arquivo antigo sem universo e sem preço novo fica como está', () {
    const o = Oportunidade(ticker: 'PETR4', nome: 'Petrobras', nota: 50);
    const antigo = RelatorioOportunidades(
        analisadas: 10, aprovadas: 3, criterios: {}, itens: [o]);
    expect(identical(recalcularRanking(antigo, fundamentos, {}), antigo), isTrue);
  });

  test('percentis iguais ao bisect_left do Python', () {
    expect(percentis([3, null, 1, 2, 2]), [1.0, null, 0.0, 1 / 3, 1 / 3]);
    expect(percentis([5]), [1.0]);
  });
}
