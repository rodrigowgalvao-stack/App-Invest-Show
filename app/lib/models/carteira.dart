enum TipoOperacao { compra, venda }

/// Uma compra ou venda registrada pelo usuário.
class Operacao {
  const Operacao({
    required this.id,
    required this.ticker,
    required this.tipo,
    required this.data,
    required this.quantidade,
    required this.preco,
    this.taxas = 0,
  });

  final String id;
  final String ticker;
  final TipoOperacao tipo;
  final DateTime data;
  final int quantidade;

  /// Preço por ação.
  final double preco;

  /// Corretagem, emolumentos etc. (total da operação).
  final double taxas;

  double get valorBruto => quantidade * preco;

  /// Quanto a operação mexe no saldo em conta: a compra tira o total pago
  /// (com taxas) e a venda põe o total recebido (sem as taxas).
  double get efeitoNoSaldo => tipo == TipoOperacao.compra
      ? -(valorBruto + taxas)
      : valorBruto - taxas;

  factory Operacao.fromJson(Map<String, dynamic> j) => Operacao(
        id: '${j['id']}',
        ticker: '${j['ticker']}'.toUpperCase(),
        tipo: j['tipo'] == 'venda' ? TipoOperacao.venda : TipoOperacao.compra,
        data: DateTime.tryParse('${j['data']}') ?? DateTime(2000),
        quantidade: (j['quantidade'] as num).toInt(),
        preco: (j['preco'] as num).toDouble(),
        taxas: (j['taxas'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticker': ticker,
        'tipo': tipo.name,
        'data': data.toIso8601String().substring(0, 10),
        'quantidade': quantidade,
        'preco': preco,
        'taxas': taxas,
      };
}

/// Situação de um ativo depois de todas as operações.
class Posicao {
  Posicao(this.ticker);

  final String ticker;
  final List<Operacao> operacoes = [];

  int quantidade = 0;

  /// Custo das ações que ainda estão na carteira (com as taxas de compra).
  double custo = 0;

  /// Lucro ou prejuízo das vendas já feitas (já descontadas as taxas).
  double realizado = 0;

  double get precoMedio => quantidade > 0 ? custo / quantidade : 0;
  bool get aberta => quantidade > 0;

  double? valorAtual(double? preco) => preco == null ? null : preco * quantidade;

  double? resultado(double? preco) {
    final v = valorAtual(preco);
    return v == null ? null : v - custo;
  }

  double? resultadoPct(double? preco) {
    final r = resultado(preco);
    return (r == null || custo == 0) ? null : r / custo * 100;
  }
}

/// Erro de consistência: venda maior do que a posição na data.
class ErroCarteira implements Exception {
  ErroCarteira(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Ordem cronológica; no mesmo dia, compras antes das vendas (day trade).
List<Operacao> ordenar(Iterable<Operacao> ops) => [...ops]..sort((a, b) {
    final d = a.data.compareTo(b.data);
    if (d != 0) return d;
    return a.tipo.index.compareTo(b.tipo.index);
  });

/// Preço médio pelo custo de aquisição (como a Receita pede): compras somam
/// ao custo; vendas tiram custo pelo preço médio e geram resultado realizado.
/// Lança [ErroCarteira] se alguma venda for maior que a posição na data.
Map<String, Posicao> calcularPosicoes(Iterable<Operacao> operacoes) {
  final pos = <String, Posicao>{};
  for (final o in ordenar(operacoes)) {
    final p = pos.putIfAbsent(o.ticker, () => Posicao(o.ticker));
    p.operacoes.add(o);
    if (o.tipo == TipoOperacao.compra) {
      p.quantidade += o.quantidade;
      p.custo += o.valorBruto + o.taxas;
    } else {
      if (o.quantidade > p.quantidade) {
        throw ErroCarteira(
            'Venda de ${o.quantidade} ${o.ticker} maior que a posição '
            '(${p.quantidade}) na data.');
      }
      final pm = p.precoMedio;
      p.realizado += o.quantidade * (o.preco - pm) - o.taxas;
      p.quantidade -= o.quantidade;
      p.custo = p.quantidade == 0 ? 0 : p.custo - o.quantidade * pm;
    }
  }
  return pos;
}

/// Totais da carteira com os preços atuais (ativo sem preço entra pelo custo).
class ResumoCarteira {
  ResumoCarteira(Map<String, Posicao> posicoes, Map<String, double> precos) {
    for (final p in posicoes.values) {
      realizado += p.realizado;
      if (!p.aberta) continue;
      investido += p.custo;
      final preco = precos[p.ticker];
      if (preco == null) {
        patrimonio += p.custo;
        semPreco++;
      } else {
        patrimonio += p.valorAtual(preco)!;
      }
    }
  }

  double investido = 0;
  double patrimonio = 0;
  double realizado = 0;
  int semPreco = 0;

  double get resultado => patrimonio - investido;
  double? get resultadoPct => investido == 0 ? null : resultado / investido * 100;
}
