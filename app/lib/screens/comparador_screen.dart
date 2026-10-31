import 'package:flutter/material.dart';

import '../models/acao.dart';
import '../services/brapi_service.dart';
import '../services/watchlist_storage.dart';
import '../widgets/formatacao.dart';
import '../widgets/ticker_dialog.dart';

class ComparadorScreen extends StatefulWidget {
  const ComparadorScreen({super.key, required this.api, required this.storage});
  final BrapiService api;
  final WatchlistStorage storage;

  @override
  State<ComparadorScreen> createState() => _ComparadorScreenState();
}

class _ComparadorScreenState extends State<ComparadorScreen> {
  static const _maximo = 3;

  List<String> _opcoes = [];
  final Set<String> _selecionadas = {};
  List<ResultadoCotacao>? _resultado;
  bool _carregando = false;

  @override
  void initState() {
    super.initState();
    widget.storage.carregar().then((l) {
      if (mounted) setState(() => _opcoes = [...l]);
    });
  }

  Future<void> _comparar() async {
    setState(() {
      _carregando = true;
      _resultado = null;
    });
    final r = await widget.api.varias(_selecionadas.toList(), completo: true);
    if (!mounted) return;
    setState(() {
      _resultado = r;
      _carregando = false;
    });
  }

  Future<void> _outra() async {
    final t = await pedirTicker(context);
    if (t == null) return;
    setState(() {
      if (!_opcoes.contains(t)) _opcoes.add(t);
      if (_selecionadas.length < _maximo) _selecionadas.add(t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Comparar ações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Escolha de 2 a $_maximo ações', style: tema.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _opcoes)
                FilterChip(
                  label: Text(t),
                  selected: _selecionadas.contains(t),
                  onSelected: (s) => setState(() {
                    if (!s) {
                      _selecionadas.remove(t);
                    } else if (_selecionadas.length < _maximo) {
                      _selecionadas.add(t);
                    }
                  }),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Outra'),
                onPressed: _outra,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                _selecionadas.length >= 2 && !_carregando ? _comparar : null,
            icon: const Icon(Icons.compare_arrows),
            label: const Text('Comparar'),
          ),
          const SizedBox(height: 16),
          if (_carregando) const Center(child: CircularProgressIndicator()),
          if (_resultado != null) ..._mostrarResultado(_resultado!),
        ],
      ),
    );
  }

  List<Widget> _mostrarResultado(List<ResultadoCotacao> r) {
    final cs = Theme.of(context).colorScheme;
    final ok = [for (final x in r) if (x.acao != null) x.acao!];
    return [
      for (final x in r)
        if (x.erro != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${x.ticker}: ${x.erro}',
                style: TextStyle(color: cs.error)),
          ),
      if (ok.isNotEmpty) ...[
        Card(clipBehavior: Clip.antiAlias, child: _tabela(ok)),
        const SizedBox(height: 8),
        Text('Em verde, o melhor valor entre as ações comparadas.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    ];
  }

  Widget _tabela(List<Acao> acoes) {
    final destaque = TextStyle(
        fontWeight: FontWeight.w700, color: Colors.green.shade600);
    final tituloGrupo = TextStyle(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary);
    final base = acoes.first.grupos;
    final linhas = <DataRow>[
      DataRow(cells: [
        const DataCell(Text('Preço')),
        for (final a in acoes) DataCell(Text(fmtMoeda(a.preco))),
      ]),
      DataRow(cells: [
        const DataCell(Text('Variação no dia')),
        for (final a in acoes)
          DataCell(Text(fmtVariacao(a.variacaoPct),
              style: TextStyle(color: corVariacao(context, a.variacaoPct)))),
      ]),
    ];

    for (var g = 0; g < base.length; g++) {
      linhas.add(DataRow(cells: [
        DataCell(Text(base[g].titulo, style: tituloGrupo)),
        for (var k = 0; k < acoes.length; k++) const DataCell(SizedBox()),
      ]));
      for (var i = 0; i < base[g].itens.length; i++) {
        final itens = [for (final a in acoes) a.grupos[g].itens[i]];
        final melhor = _indiceMelhor(itens);
        linhas.add(DataRow(cells: [
          DataCell(Text(itens.first.nome)),
          for (var k = 0; k < itens.length; k++)
            DataCell(Text(formatar(itens[k].valor, itens[k].formato),
                style: k == melhor ? destaque : null)),
        ]));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        columns: [
          const DataColumn(label: Text('Indicador')),
          for (final a in acoes)
            DataColumn(
              numeric: true,
              label: Text(a.ticker,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
        rows: linhas,
      ),
    );
  }

  int? _indiceMelhor(List<Indicador> itens) {
    final criterio = itens.first.melhor;
    if (criterio == null || itens.length < 2) return null;
    int? indice;
    double? melhor;
    for (var k = 0; k < itens.length; k++) {
      final v = itens[k].valor;
      if (v == null || !v.isFinite) continue;
      if (itens[k].soPositivos && v <= 0) continue;
      final ganha = melhor == null ||
          (criterio == Melhor.maior ? v > melhor : v < melhor);
      if (ganha) {
        melhor = v;
        indice = k;
      }
    }
    return indice;
  }
}
