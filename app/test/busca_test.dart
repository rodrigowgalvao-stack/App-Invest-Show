import 'package:acoes_app/models/ativo_busca.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ativos = [
    AtivoBusca(ticker: 'ITUB4', nome: 'ITAÚ UNIBANCO HOLDING S.A.', setor: 'Bancos'),
    AtivoBusca(ticker: 'ITSA4', nome: 'ITAÚSA S.A.', setor: 'Bancos'),
    AtivoBusca(ticker: 'PETR4', nome: 'PETRÓLEO BRASILEIRO S.A. PETROBRAS',
        setor: 'Petróleo e Gás Integrado'),
    AtivoBusca(ticker: 'PETR3', nome: 'PETRÓLEO BRASILEIRO S.A. PETROBRAS'),
    AtivoBusca(ticker: 'TAEE11', nome: 'TRANSMISSORA ALIANÇA DE ENERGIA ELÉTRICA S.A.',
        setor: 'Energia Elétrica'),
  ];
  List<String> busca(String q) => [for (final a in filtrarAtivos(ativos, q)) a.ticker];

  test('normaliza acento e pontuação', () {
    expect(normalizar('Itaú S.A.'), 'itau sa');
  });

  test('código exato vem primeiro', () {
    expect(busca('petr4').first, 'PETR4');
    expect(busca('PETR'), ['PETR3', 'PETR4']);
  });

  test('busca pelo nome sem acento', () {
    expect(busca('itau'), containsAll(['ITUB4', 'ITSA4']));
    expect(busca('petrobras'), ['PETR3', 'PETR4']);
    expect(busca('alianca energia'), ['TAEE11']);
  });

  test('busca pelo setor', () {
    expect(busca('eletrica'), ['TAEE11']);
  });

  test('sem resultado', () {
    expect(busca('xyz'), isEmpty);
    expect(busca('  '), isEmpty);
  });
}
