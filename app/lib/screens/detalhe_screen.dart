import 'package:flutter/material.dart';

import '../models/acao.dart';
import '../services/brapi_service.dart';
import '../widgets/estado_erro.dart';
import '../widgets/formatacao.dart';
import '../widgets/grafico_preco.dart';

class DetalheScreen extends StatefulWidget {
  const DetalheScreen({super.key, required this.ticker, required this.api});
  final String ticker;
  final BrapiService api;

  @override
  State<DetalheScreen> createState() => _DetalheScreenState();
}

class _DetalheScreenState extends State<DetalheScreen> {
  static const _periodos = {'1mo': '1M', '3mo': '3M', '1y': '1A'};

  String _range = '3mo';
  late Future<Acao> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _buscar();
  }

  Future<Acao> _buscar({bool forcar = false}) => widget.api
      .cotacao(widget.ticker, completo: true, range: _range, forcar: forcar);

  void _recarregar({bool forcar = false}) =>
      setState(() => _futuro = _buscar(forcar: forcar));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.ticker)),
      body: FutureBuilder<Acao>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EstadoErro(
              mensagem: snap.error.toString(),
              onTentar: () {
                _range = '3mo';
                _recarregar(forcar: true);
              },
            );
          }
          return _conteudo(snap.data!);
        },
      ),
    );
  }

  Widget _conteudo(Acao a) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return RefreshIndicator(
      onRefresh: () async {
        _recarregar(forcar: true);
        await _futuro.catchError((_) => a);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(a.nome, style: tema.textTheme.titleMedium),
          if (a.setor != null)
            Text(a.setor!,
                style: tema.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(fmtMoeda(a.preco),
                  style: tema.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Text(fmtVariacao(a.variacaoPct),
                  style: tema.textTheme.titleMedium
                      ?.copyWith(color: corVariacao(context, a.variacaoPct))),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: SegmentedButton<String>(
              segments: [
                for (final e in _periodos.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {_range},
              onSelectionChanged: (s) {
                _range = s.first;
                _recarregar();
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 220, child: GraficoPreco(pontos: a.historico)),
          if (a.minimo52 != null && a.maximo52 != null && a.preco != null)
            _Faixa52(min: a.minimo52!, max: a.maximo52!, atual: a.preco!),
          if (!a.temFundamentos)
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'A brapi não devolveu indicadores para este ativo. '
                  'Ou o seu plano não inclui os módulos fundamentalistas, '
                  'ou o ativo não tem esses dados (FIIs e ETFs, por exemplo).',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            for (final g in a.grupos) _CardGrupo(grupo: g),
        ],
      ),
    );
  }
}

class _Faixa52 extends StatelessWidget {
  const _Faixa52({required this.min, required this.max, required this.atual});
  final double min, max, atual;

  @override
  Widget build(BuildContext context) {
    final pos = max > min ? ((atual - min) / (max - min)).clamp(0.0, 1.0) : 0.5;
    final estilo = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Faixa de 52 semanas', style: estilo),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: pos.toDouble(),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(fmtMoeda(min), style: estilo),
              Text(fmtMoeda(max), style: estilo),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardGrupo extends StatelessWidget {
  const _CardGrupo({required this.grupo});
  final GrupoIndicadores grupo;

  void _ajuda(BuildContext context, Indicador i) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i.nome, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(i.ajuda),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(grupo.titulo,
                  style: tema.textTheme.titleSmall
                      ?.copyWith(color: tema.colorScheme.primary)),
            ),
            for (final i in grupo.itens)
              ListTile(
                dense: true,
                title: Text(i.nome),
                trailing: Text(formatar(i.valor, i.formato),
                    style: tema.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                onTap: () => _ajuda(context, i),
              ),
          ],
        ),
      ),
    );
  }
}
