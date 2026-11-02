import 'package:acoes_app/models/acao.dart';
import 'package:acoes_app/widgets/grafico_preco.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<PontoHistorico> historico(int n) => [
      for (var i = 0; i < n; i++)
        PontoHistorico(DateTime(2026, 1, 1).add(Duration(days: i)), 10.0 + i % 7,
            abertura: 10.0 + (i + 3) % 7,
            maxima: 18,
            minima: 9,
            volume: 1000.0 * (i + 1)),
    ];

void main() {
  test('média móvel simples', () {
    expect(mediaMovel([1, 2, 3, 4], 2), [null, 1.5, 2.5, 3.5]);
    expect(mediaMovel([1, 2], 3), [null, null]);
  });

  test('sem abertura/máxima/mínima, usa o fechamento', () {
    final p = PontoHistorico(DateTime(2026), 5);
    expect([p.abertura, p.maxima, p.minima], [5, 5, 5]);
  });

  for (final tipo in TipoGrafico.values) {
    testWidgets('desenha $tipo com médias e volume', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: GraficoPreco(
                pontos: historico(70), tipo: tipo, medias: const {20, 50}, volume: true),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.text('Média 20 dias'), findsOneWidget);
      await t.tapAt(t.getCenter(find.byType(GraficoPreco)));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('gráfico de rentabilidade', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: GraficoRentabilidade(
              series: {'AAAA3': historico(30), 'BBBB4': historico(20)}),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.textContaining('AAAA3'), findsOneWidget);
  });
}
