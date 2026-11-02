import 'acao.dart';

/// Um resultado da busca: vem da lista da CVM (ações) ou da brapi
/// (que também tem FIIs, ETFs e BDRs).
class AtivoBusca {
  const AtivoBusca({
    required this.ticker,
    required this.nome,
    this.setor,
    this.tipo,
    this.preco,
    this.variacaoPct,
  });

  final String ticker;
  final String nome;
  final String? setor;

  /// stock, fund, bdr... (só quando vem da brapi).
  final String? tipo;
  final double? preco;
  final double? variacaoPct;

  /// Item de /quote/list da brapi.
  factory AtivoBusca.fromBrapi(Map<String, dynamic> j) {
    final t = '${j['stock'] ?? ''}'.toUpperCase();
    return AtivoBusca(
      ticker: t,
      nome: '${j['name'] ?? t}',
      setor: j['sector'] as String?,
      tipo: j['type'] as String?,
      preco: numero(j['close']),
      variacaoPct: numero(j['change']),
    );
  }

  /// Junta os dados das duas fontes: nome e setor da CVM, preço da brapi.
  AtivoBusca completar(AtivoBusca outro) => AtivoBusca(
        ticker: ticker,
        nome: nome,
        setor: setor ?? outro.setor,
        tipo: tipo ?? outro.tipo,
        preco: preco ?? outro.preco,
        variacaoPct: variacaoPct ?? outro.variacaoPct,
      );

  String get rotuloTipo => switch (tipo) {
        'fund' => 'FII',
        'bdr' => 'BDR',
        _ => '',
      };
}

const _acentos = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Minúsculas, sem acento e sem pontuação: "Itaú S.A." → "itau sa".
String normalizar(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final c = _acentos[ch] ?? ch;
    if (RegExp(r'[a-z0-9 ]').hasMatch(c)) b.write(c);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Nota de relevância (0 = não combina). Código exato vence, depois
/// começo do código, depois palavras do nome, depois trecho do nome.
int relevancia(AtivoBusca a, String termo) {
  final q = normalizar(termo);
  if (q.isEmpty) return 0;
  final t = a.ticker.toLowerCase();
  final nome = normalizar(a.nome);
  if (t == q) return 100;
  if (t.startsWith(q)) return 80 - (t.length - q.length);
  final palavras = q.split(' ');
  final doNome = nome.split(' ');
  // Todas as palavras digitadas começam alguma palavra do nome.
  if (palavras.every((p) => doNome.any((n) => n.startsWith(p)))) {
    return nome.startsWith(q) ? 60 : 50;
  }
  if (nome.contains(q)) return 30;
  final setor = normalizar(a.setor ?? '');
  if (setor.isNotEmpty && setor.contains(q)) return 10;
  return 0;
}

/// Filtra e ordena por relevância; empate fica com o ticker em ordem.
List<AtivoBusca> filtrarAtivos(Iterable<AtivoBusca> ativos, String termo,
    {int limite = 30}) {
  final comNota = [
    for (final a in ativos)
      if (relevancia(a, termo) case final n when n > 0) (a, n),
  ]..sort((x, y) {
      final c = y.$2.compareTo(x.$2);
      return c != 0 ? c : x.$1.ticker.compareTo(y.$1.ticker);
    });
  return [for (final e in comNota.take(limite)) e.$1];
}
