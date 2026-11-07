import 'package:flutter/material.dart';

import '../models/carteira.dart';
import '../models/fundamentos.dart';
import '../models/ranking.dart';
import '../services/brapi_service.dart';
import '../services/carteira_storage.dart';
import '../widgets/formatacao.dart';
import '../widgets/sinal.dart';
import 'carteira_screen.dart' show calcularPosicoesSeguro;
import 'detalhe_screen.dart';
import 'operacao_screen.dart';

/// Situação de um ativo da carteira: resultado, sinal e operações.
class PosicaoScreen extends StatefulWidget {
  const PosicaoScreen({
    super.key,
    required this.ticker,
    required this.api,
    required this.storage,
    required this.fundamentos,
    required this.criterios,
  });

  final String ticker;
  final BrapiService api;
  final CarteiraStorage storage;
  final Fundamentos? fundamentos;
  final Map<String, dynamic> criterios;

  @override
  State<PosicaoScreen> createState() => _PosicaoScreenState();
}

class _PosicaoScreenState extends State<PosicaoScreen> {
  List<Operacao> _ops = [];

  @override
  void initState() {
    super.initState();
    widget.storage.addListener(_carregar);
    widget.api.precos.addListener(_mudou);
    _carregar();
  }

  @override
  void dispose() {
    widget.storage.removeListener(_carregar);
    widget.api.precos.removeListener(_mudou);
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  Future<void> _carregar() async {
    final ops = await widget.storage.carregar();
    if (mounted) setState(() => _ops = ops);
  }

  Future<void> _operar(TipoOperacao tipo) => abrirOperacao(context,
      api: widget.api, storage: widget.storage, ticker: widget.ticker, tipo: tipo);

  Future<void> _apagar(Operacao o) async {
    final saldo = await widget.storage.saldo();
    if (!mounted) return;
    var ajustar = false;
    final efeito = -o.efeitoNoSaldo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar operação?'),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${o.tipo == TipoOperacao.compra ? 'Compra' : 'Venda'} de '
                  '${o.quantidade} ${o.ticker} em ${fmtData(o.data)}.'),
              if (saldo != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: ajustar,
                  onChanged: (v) => setDialog(() => ajustar = v ?? false),
                  title: Text(efeito >= 0
                      ? 'Devolver ${fmtMoeda(efeito)} ao saldo em conta'
                      : 'Tirar ${fmtMoeda(-efeito)} do saldo em conta'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.storage.remover(o.id, ajustarSaldo: ajustar);
    } on ErroCarteira catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Não dá para apagar: ${e.mensagem} '
              'Apague antes a venda.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final cinza = tema.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final p = calcularPosicoesSeguro(_ops)[widget.ticker];
    final atual = widget.api.precos.de(widget.ticker);
    final preco = atual?.preco;
    final av = avaliarAtivo(widget.fundamentos, preco, criterios: widget.criterios);
    final (_, _, corSinal) = estiloSinal(context, av.sinal);

    Widget linha(String a, String b, {Color? cor}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(a),
              Text(b,
                  style: TextStyle(fontWeight: FontWeight.w600, color: cor)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ticker),
        actions: [
          IconButton(
            tooltip: 'Análise da ação',
            icon: const Icon(Icons.query_stats),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      DetalheScreen(ticker: widget.ticker, api: widget.api)),
            ),
          ),
        ],
      ),
      body: p == null
          ? const Center(child: Text('Nenhuma operação com este ativo.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (p.aberta) ...[
                          linha('Quantidade', '${p.quantidade}'),
                          linha('Preço médio', fmtMoeda(p.precoMedio)),
                          linha('Preço atual',
                              '${fmtMoeda(preco)}  ${fmtVariacao(atual?.variacaoPct)} hoje'),
                          linha('Investido', fmtMoeda(p.custo)),
                          linha('Valor atual', fmtMoeda(p.valorAtual(preco))),
                          linha(
                            'Resultado',
                            '${fmtMoedaSinal(p.resultado(preco))} (${fmtVariacao(p.resultadoPct(preco))})',
                            cor: corVariacao(context, p.resultado(preco)),
                          ),
                        ] else
                          linha('Posição', 'encerrada'),
                        if (p.realizado != 0)
                          linha('Resultado das vendas', fmtMoedaSinal(p.realizado),
                              cor: corVariacao(context, p.realizado)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  color: corSinal.withAlpha(20),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SeloSinal(av.sinal),
                        const SizedBox(height: 8),
                        Text(av.motivo),
                        if (av.precoJustoGraham != null || av.precoTetoBazin != null)
                          const SizedBox(height: 8),
                        if (av.precoJustoGraham != null)
                          linha('Preço justo (Graham)', fmtMoeda(av.precoJustoGraham),
                              cor: preco != null && av.precoJustoGraham! >= preco
                                  ? Colors.green.shade600
                                  : null),
                        if (av.precoTetoBazin != null)
                          linha('Preço teto (Bazin)', fmtMoeda(av.precoTetoBazin),
                              cor: preco != null && av.precoTetoBazin! >= preco
                                  ? Colors.green.shade600
                                  : null),
                        const SizedBox(height: 4),
                        Text('Alerta para analisar, não recomendação.', style: cinza),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _operar(TipoOperacao.compra),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Comprar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            p.aberta ? () => _operar(TipoOperacao.venda) : null,
                        icon: const Icon(Icons.sell_outlined),
                        label: const Text('Vender'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Operações', style: tema.textTheme.titleSmall),
                Text('Toque para editar.', style: cinza),
                for (final o in p.operacoes.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: (o.tipo == TipoOperacao.compra
                              ? Colors.green.shade600
                              : Colors.red.shade600)
                          .withAlpha(30),
                      child: Icon(
                        o.tipo == TipoOperacao.compra
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        size: 18,
                        color: o.tipo == TipoOperacao.compra
                            ? Colors.green.shade600
                            : Colors.red.shade600,
                      ),
                    ),
                    title: Text(
                        '${o.tipo == TipoOperacao.compra ? 'Compra' : 'Venda'} · '
                        '${o.quantidade} × ${fmtMoeda(o.preco)}'),
                    subtitle: Text(
                        '${fmtData(o.data)}${o.taxas > 0 ? ' · taxas ${fmtMoeda(o.taxas)}' : ''}'),
                    trailing: IconButton(
                      tooltip: 'Apagar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _apagar(o),
                    ),
                    onTap: () => abrirOperacao(context,
                        api: widget.api, storage: widget.storage, editar: o),
                  ),
              ],
            ),
    );
  }
}
