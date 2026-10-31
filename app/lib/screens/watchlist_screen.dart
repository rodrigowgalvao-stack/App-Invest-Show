import 'package:flutter/material.dart';

import '../config.dart';
import '../services/brapi_service.dart';
import '../services/watchlist_storage.dart';
import '../widgets/formatacao.dart';
import '../widgets/ticker_dialog.dart';
import 'detalhe_screen.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key, required this.api, required this.storage});
  final BrapiService api;
  final WatchlistStorage storage;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<String> _tickers = [];
  Map<String, ResultadoCotacao> _dados = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    _tickers = await widget.storage.carregar();
    await _atualizar();
  }

  Future<void> _atualizar({bool forcar = false}) async {
    if (mounted) setState(() => _carregando = true);
    final res = await widget.api.varias(_tickers, forcar: forcar);
    if (!mounted) return;
    setState(() {
      _dados = {for (final r in res) r.ticker: r};
      _carregando = false;
    });
  }

  Future<void> _adicionar() async {
    final t = await pedirTicker(context);
    if (t == null || _tickers.contains(t)) return;
    setState(() => _tickers.add(t));
    await widget.storage.salvar(_tickers);
    final r = await widget.api.resultado(t);
    if (mounted) setState(() => _dados[t] = r);
  }

  Future<void> _remover(String t) async {
    setState(() {
      _tickers.remove(t);
      _dados.remove(t);
    });
    await widget.storage.salvar(_tickers);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha lista'),
        actions: [
          IconButton(
            tooltip: 'Atualizar cotações',
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : () => _atualizar(forcar: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionar,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar ação'),
      ),
      body: Column(
        children: [
          if (brapiToken.isEmpty) const _AvisoToken(),
          if (_carregando) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _atualizar(forcar: true),
              child: _tickers.isEmpty ? _vazio() : _lista(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vazio() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Toque em “Adicionar ação” para montar sua lista.')),
        ],
      );

  Widget _lista() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _tickers.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final t = _tickers[i];
        final r = _dados[t];
        final a = r?.acao;
        return Dismissible(
          key: ValueKey(t),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) => _remover(t),
          child: ListTile(
            leading: CircleAvatar(child: Text(t.substring(0, 2))),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              a?.nome ?? r?.erro ?? 'Carregando…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: r?.erro != null
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
            trailing: a == null
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fmtMoeda(a.preco),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(fmtVariacao(a.variacaoPct),
                          style: TextStyle(
                              color: corVariacao(context, a.variacaoPct))),
                    ],
                  ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetalheScreen(ticker: t, api: widget.api),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AvisoToken extends StatelessWidget {
  const _AvisoToken();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        'Sem token da brapi: só PETR4, VALE3, ITUB4 e MGLU3 respondem. '
        'Veja o README para configurar.',
        style: TextStyle(color: cs.onTertiaryContainer),
      ),
    );
  }
}
