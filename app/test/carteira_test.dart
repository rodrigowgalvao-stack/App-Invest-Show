import 'dart:convert';

import 'package:acoes_app/models/carteira.dart';
import 'package:acoes_app/models/fundamentos.dart';
import 'package:acoes_app/models/ranking.dart';
import 'package:acoes_app/screens/carteira_screen.dart';
import 'package:acoes_app/services/brapi_service.dart';
import 'package:acoes_app/services/carteira_storage.dart';
import 'package:acoes_app/services/oportunidades_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Operacao op(String t, TipoOperacao tipo, String data, int q, double p,
        {double taxas = 0, String? id}) =>
    Operacao(
        id: id ?? '$t$data$q',
        ticker: t,
        tipo: tipo,
        data: DateTime.parse(data),
        quantidade: q,
        preco: p,
        taxas: taxas);

const c = TipoOperacao.compra, v = TipoOperacao.venda;

void main() {
  group('posições', () {
    test('preço médio com taxas e venda parcial', () {
      final pos = calcularPosicoes([
        op('PETR4', c, '2026-01-10', 100, 30, taxas: 10),
        op('PETR4', c, '2026-02-10', 100, 40),
        op('PETR4', v, '2026-03-10', 50, 45, taxas: 5),
      ])['PETR4']!;
      // Custo 3010 + 4000 = 7010 → PM 35,05.
      expect(pos.quantidade, 150);
      expect(pos.precoMedio, closeTo(35.05, 1e-9));
      // Venda: 50 × (45 − 35,05) − 5 = 492,50.
      expect(pos.realizado, closeTo(492.5, 1e-9));
      expect(pos.custo, closeTo(150 * 35.05, 1e-9));
      expect(pos.resultado(40), closeTo(150 * (40 - 35.05), 1e-9));
    });

    test('vender tudo encerra e zera o custo', () {
      final pos = calcularPosicoes([
        op('VALE3', c, '2026-01-10', 10, 60),
        op('VALE3', v, '2026-01-20', 10, 50),
      ])['VALE3']!;
      expect(pos.aberta, isFalse);
      expect(pos.custo, 0);
      expect(pos.realizado, -100);
    });

    test('ordem cronológica, não a de cadastro', () {
      final pos = calcularPosicoes([
        op('ITUB4', v, '2026-02-01', 10, 40),
        op('ITUB4', c, '2026-01-01', 10, 30),
      ])['ITUB4']!;
      expect(pos.realizado, 100);
    });

    test('venda maior que a posição é recusada', () {
      expect(
          () => calcularPosicoes([
                op('ITUB4', c, '2026-01-01', 10, 30),
                op('ITUB4', v, '2026-01-02', 11, 30),
              ]),
          throwsA(isA<ErroCarteira>()));
    });

    test('resumo da carteira', () {
      final pos = calcularPosicoes([
        op('A', c, '2026-01-01', 10, 10),
        op('B', c, '2026-01-01', 10, 20),
      ]);
      final r = ResumoCarteira(pos, {'A': 12});
      expect(r.investido, 300);
      expect(r.patrimonio, 120 + 200); // B sem preço entra pelo custo
      expect(r.semPreco, 1);
      expect(r.resultadoPct, closeTo(20 / 300 * 100, 1e-9));
    });

    test('json ida e volta', () {
      final o = op('TAEE11', v, '2026-05-02', 7, 35.5, taxas: 1.2);
      final de = Operacao.fromJson(jsonDecode(jsonEncode(o.toJson())));
      expect([de.ticker, de.tipo, de.data, de.quantidade, de.preco, de.taxas],
          [o.ticker, o.tipo, o.data, o.quantidade, o.preco, o.taxas]);
    });
  });

  group('sinais', () {
    final hoje = DateTime(2026, 11, 7);
    final boa = Fundamentos.fromJson({
      'data_balanco': '2026-06-30',
      'lpa': 4.0,
      'vpa': 20.0,
      'dpa': 2.0,
      'roe': 20.0,
      'margem_liquida': 15.0,
      'div_liq_ebitda': 1.0,
      'valor_mercado': 5e9,
      'preco_ref': 30.0,
    });
    // Graham = √(22,5·4·20) ≈ 42,4; Bazin = 2/0,06 ≈ 33,3.
    test('abaixo do preço justo e bons fundamentos: compra', () {
      expect(avaliarAtivo(boa, 30, hoje: hoje).sinal, Sinal.compra);
    });
    test('acima de Graham e Bazin: venda', () {
      expect(avaliarAtivo(boa, 50, hoje: hoje).sinal, Sinal.venda);
    });
    test('prejuízo: atenção', () {
      final ruim = Fundamentos.fromJson({
        'data_balanco': '2026-06-30', 'lpa': -1.0, 'vpa': 20.0, 'roe': -5.0,
      });
      expect(avaliarAtivo(ruim, 10, hoje: hoje).sinal, Sinal.atencao);
    });
    test('FII sem balanço: sem análise', () {
      expect(avaliarAtivo(null, 100).sinal, Sinal.semAnalise);
    });
  });

  group('saldo em conta', () {
    test('efeito de compra e venda no saldo', () {
      expect(op('PETR4', c, '2026-01-10', 100, 30, taxas: 10).efeitoNoSaldo, -3010);
      expect(op('PETR4', v, '2026-01-10', 50, 40, taxas: 5).efeitoNoSaldo, 1995);
    });

    test('compra, edição e exclusão ajustam o saldo', () async {
      SharedPreferences.setMockInitialValues({});
      final s = CarteiraStorage();
      expect(await s.saldo(), isNull);

      // Sem saldo informado, nada muda.
      await s.salvar(op('PETR4', c, '2026-01-10', 10, 30, id: 'a'),
          ajustarSaldo: true);
      expect(await s.saldo(), isNull);

      await s.definirSaldo(1000);
      await s.salvar(op('VALE3', c, '2026-01-10', 10, 50, taxas: 2, id: 'b'),
          ajustarSaldo: true);
      expect(await s.saldo(), closeTo(498, 1e-9));

      // Edição: só a diferença (10 → 12 ações a 50).
      await s.salvar(op('VALE3', c, '2026-01-10', 12, 50, taxas: 2, id: 'b'),
          ajustarSaldo: true);
      expect(await s.saldo(), closeTo(398, 1e-9));

      await s.salvar(op('VALE3', v, '2026-02-10', 12, 60, taxas: 3, id: 'cc'),
          ajustarSaldo: true);
      expect(await s.saldo(), closeTo(1115, 1e-9));

      // Sem pedir ajuste, não mexe.
      await s.salvar(op('PETR4', c, '2026-03-10', 1, 30, id: 'd'));
      expect(await s.saldo(), closeTo(1115, 1e-9));

      await s.remover('cc', ajustarSaldo: true);
      expect(await s.saldo(), closeTo(398, 1e-9));

      await s.movimentarSaldo(-98);
      expect(await s.saldo(), closeTo(300, 1e-9));

      // Persiste entre instâncias.
      expect(await CarteiraStorage().saldo(), closeTo(300, 1e-9));

      await s.limparSaldo();
      expect(await CarteiraStorage().saldo(), isNull);
    });
  });

  testWidgets('tela da carteira com preços da brapi', (t) async {
    SharedPreferences.setMockInitialValues({
      'carteira_operacoes': jsonEncode([
        op('PETR4', c, '2026-01-10', 100, 30).toJson(),
        op('VALE3', c, '2026-01-10', 20, 70).toJson(),
        op('VALE3', v, '2026-03-10', 20, 60).toJson(),
      ]),
    });
    final cliente = MockClient((r) async {
      if (r.url.path.endsWith('/quote/list')) {
        return http.Response(
            jsonEncode({
              'stocks': [
                {'stock': 'PETR4', 'close': 36.0, 'change': 1.5},
              ]
            }),
            200);
      }
      return http.Response('{}', 404);
    });
    await t.pumpWidget(MaterialApp(
      home: CarteiraScreen(
        api: BrapiService(client: cliente),
        storage: CarteiraStorage(),
        servico: OportunidadesService(client: cliente),
      ),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining('3.600,00'), findsWidgets); // patrimônio e cartão
    expect(find.textContaining('600,00 (+20,00%)'), findsWidgets);
    expect(find.text('Posições encerradas (1)'), findsOneWidget);
    expect(find.text('Sem análise'), findsOneWidget); // sem fundamentos
    expect(find.text('Saldo em conta'), findsOneWidget); // ainda não informado
  });

  testWidgets('saldo em conta na carteira', (t) async {
    SharedPreferences.setMockInitialValues({
      'carteira_operacoes': jsonEncode([op('PETR4', c, '2026-01-10', 100, 30).toJson()]),
      'carteira_saldo': 1250.5,
    });
    final cliente = MockClient((r) async => r.url.path.endsWith('/quote/list')
        ? http.Response(
            jsonEncode({
              'stocks': [
                {'stock': 'PETR4', 'close': 36.0, 'change': 1.5},
              ]
            }),
            200)
        : http.Response('{}', 404));
    final storage = CarteiraStorage();
    await t.pumpWidget(MaterialApp(
      home: CarteiraScreen(
        api: BrapiService(client: cliente),
        storage: storage,
        servico: OportunidadesService(client: cliente),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('1.250,50'), findsOneWidget);
    expect(find.textContaining(RegExp(r'Total com a carteira: R\$.4\.850,50')), findsOneWidget);

    // Depósito pelo diálogo.
    await t.tap(find.byTooltip('Ajustar saldo'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '100');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(await storage.saldo(), closeTo(1350.5, 1e-9));
    expect(find.textContaining('1.350,50'), findsOneWidget);
  });
}
