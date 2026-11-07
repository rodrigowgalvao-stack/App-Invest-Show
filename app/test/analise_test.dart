import 'package:acoes_app/services/analises_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lê analises.json do robô', () {
    final mapa = analisesDeJson({
      'gerado_em': '2026-11-02T19:00-03:00',
      'modelo': 'gemini-3.8-flash',
      'acoes': {
        'VULC3': {
          'resumo': 'Empresa lucrativa.',
          'pontos_fortes': ['ROE alto', ''],
          'riscos': ['DY inflado'],
          'leitura_fatos': '',
          'fatos': [
            {'data': '2026-10-20', 'categoria': 'Fato Relevante', 'assunto': 'Recompra'},
          ],
        },
        'XPTO3': 'inválido',
      },
    });
    expect(mapa.keys, ['VULC3']);
    final a = mapa['VULC3']!;
    expect(a.pontosFortes, ['ROE alto']);
    expect(a.riscos, ['DY inflado']);
    expect(a.modelo, 'gemini-3.8-flash');
    expect(a.geradoEm, isNotNull);
    expect(a.fatos.single.relevante, isTrue);
    expect(a.fatos.single.data, DateTime(2026, 10, 20));
  });

  test('arquivo inválido vira mapa vazio', () {
    expect(analisesDeJson(null), isEmpty);
    expect(analisesDeJson({'acoes': []}), isEmpty);
  });
}
