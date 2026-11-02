import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ativo_busca.dart';
import '../screens/detalhe_screen.dart';
import '../services/brapi_service.dart';
import 'formatacao.dart';

final _formatoTicker = RegExp(r'^[A-Z0-9]{4}\d{1,2}F?$');

/// Abre a busca (por código ou nome) e devolve o ticker escolhido, ou null
/// se cancelar. [titulo] aparece na barra, ex.: "Adicionar à lista".
Future<String?> pedirTicker(BuildContext context, BrapiService api,
    {String titulo = 'Buscar ação'}) {
  return Navigator.push<String>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BuscaAtivoScreen(api: api, titulo: titulo),
    ),
  );
}

/// Busca e abre a tela de detalhe do ativo escolhido.
Future<void> abrirBusca(BuildContext context, BrapiService api) async {
  final t = await pedirTicker(context, api);
  if (t == null || !context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DetalheScreen(ticker: t, api: api)),
  );
}

class BuscaAtivoScreen extends StatefulWidget {
  const BuscaAtivoScreen({super.key, required this.api, required this.titulo});
  final BrapiService api;
  final String titulo;

  @override
  State<BuscaAtivoScreen> createState() => _BuscaAtivoScreenState();
}

class _BuscaAtivoScreenState extends State<BuscaAtivoScreen> {
  final _ctrl = TextEditingController();
  Timer? _espera;
  List<AtivoBusca> _resultados = const [];
  bool _buscando = false;
  int _consulta = 0;

  @override
  void dispose() {
    _espera?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _mudou(String texto) {
    _espera?.cancel();
    final q = texto.trim();
    final id = ++_consulta;
    if (q.isEmpty) {
      setState(() {
        _resultados = const [];
        _buscando = false;
      });
      return;
    }
    // Lista local na hora; a brapi só depois de uma pausa na digitação.
    widget.api.buscarLocal(q).then((l) {
      if (mounted && id == _consulta) setState(() => _resultados = l);
    });
    setState(() => _buscando = true);
    _espera = Timer(const Duration(milliseconds: 400), () async {
      final l = await widget.api.buscar(q);
      if (!mounted || id != _consulta) return;
      setState(() {
        _resultados = l;
        _buscando = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final digitado = _ctrl.text.trim().toUpperCase();
    final podeUsarDigitado = _formatoTicker.hasMatch(digitado) &&
        !_resultados.any((a) => a.ticker == digitado);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _mudou,
              onSubmitted: (_) {
                if (_resultados.isNotEmpty) {
                  Navigator.pop(context, _resultados.first.ticker);
                } else if (_formatoTicker.hasMatch(digitado)) {
                  Navigator.pop(context, digitado);
                }
              },
              decoration: InputDecoration(
                hintText: 'Código ou nome: WEGE3, Itaú, energia…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          _mudou('');
                        },
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_buscando) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              children: [
                if (podeUsarDigitado)
                  ListTile(
                    leading: const Icon(Icons.keyboard_return),
                    title: Text('Usar $digitado'),
                    subtitle: const Text('Código digitado'),
                    onTap: () => Navigator.pop(context, digitado),
                  ),
                for (final a in _resultados) _ItemResultado(a: a),
                if (_ctrl.text.trim().isNotEmpty &&
                    !_buscando &&
                    _resultados.isEmpty &&
                    !podeUsarDigitado)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Nada encontrado.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                if (_ctrl.text.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Digite o código (PETR4) ou parte do nome da empresa '
                      '(petrobras, banco, energia).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemResultado extends StatelessWidget {
  const _ItemResultado({required this.a});
  final AtivoBusca a;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = [a.nome, if (a.setor != null) a.setor!].join(' · ');
    return ListTile(
      leading: CircleAvatar(
        child: Text(a.ticker.substring(0, a.ticker.length < 2 ? a.ticker.length : 2)),
      ),
      title: Row(
        children: [
          Text(a.ticker, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (a.rotuloTipo.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(a.rotuloTipo,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSecondaryContainer)),
            ),
          ],
        ],
      ),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: a.preco == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmtMoeda(a.preco)),
                Text(fmtVariacao(a.variacaoPct),
                    style: TextStyle(
                        fontSize: 12,
                        color: corVariacao(context, a.variacaoPct))),
              ],
            ),
      onTap: () => Navigator.pop(context, a.ticker),
    );
  }
}
