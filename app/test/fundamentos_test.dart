import 'package:acoes_app/models/acao.dart';
import 'package:acoes_app/models/fundamentos.dart';
import 'package:flutter_test/flutter_test.dart';

double? valor(List<GrupoIndicadores> grupos, String nome) =>
    grupos.expand((g) => g.itens).firstWhere((i) => i.nome == nome).valor;

void main() {
  // Trecho real de dados/fundamentos.json (PETR4, balanço de 30/06/2026).
  final petr4 = Fundamentos.fromJson({
    'setor': 'Petróleo e Gás Integrado',
    'data_balanco': '2026-06-30',
    'financeira': false,
    'preco_ref': 52.71,
    'lpa': 10.3483,
    'vpa': 37.3155,
    'dpa': 2.9737,
    'roe': 27.7318,
    'divida_liquida': 312769000000,
    'valor_mercado': 716786114653,
    'ebitda_12m': 273323000000,
  });

  test('indicadores de preço usam a cotação do dia', () {
    final g = gruposIndicadores(petr4, 60.0);
    expect(valor(g, 'P/L'), closeTo(60.0 / 10.3483, 1e-9));
    expect(valor(g, 'P/VP'), closeTo(60.0 / 37.3155, 1e-9));
    expect(valor(g, 'Dividend yield (12m)'), closeTo(2.9737 / 60.0 * 100, 1e-9));
    // Valor de mercado acompanha o preço desde o relatório do robô.
    expect(valor(g, 'Valor de mercado'), closeTo(716786114653 * 60.0 / 52.71, 1));
    expect(valor(g, 'ROE'), 27.7318);
  });

  test('sem fundamentos mantém a mesma estrutura, com valores vazios', () {
    final cheio = gruposIndicadores(petr4, 60.0);
    final vazio = gruposIndicadores(null, 60.0);
    expect(vazio.map((g) => g.itens.length), cheio.map((g) => g.itens.length));
    expect(vazio.expand((g) => g.itens).every((i) => i.valor == null), isTrue);
  });

  test('EV/EBITDA fica vazio com EBITDA negativo', () {
    final f = Fundamentos.fromJson({'valor_mercado': 1e9, 'preco_ref': 10, 'divida_liquida': 1e8, 'ebitda_12m': -5e7});
    expect(valor(gruposIndicadores(f, 10), 'EV/EBITDA'), isNull);
  });
}
