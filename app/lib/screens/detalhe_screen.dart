import 'package:flutter/material.dart';

import '../models/acao.dart';
import '../models/analise.dart';
import '../services/analises_service.dart';
import '../services/brapi_service.dart';
import '../widgets/estado_erro.dart';
import '../widgets/formatacao.dart';
import '../widgets/grafico_preco.dart';

class DetalheScreen extends StatefulWidget {
  const DetalheScreen(
      {super.key, required this.ticker, required this.api, this.analises});
  final String ticker;
  final BrapiService api;
  final AnalisesService? analises;

  @override
  State<DetalheScreen> createState() => _DetalheScreenState();
}

class _DetalheScreenState extends State<DetalheScreen> {
  static const _periodos = {
    '5d': '5D',
    '1mo': '1M',
    '3mo': '3M',
    '6mo': '6M',
    '1y': '1A',
  };

  String _range = '3mo';
  TipoGrafico _tipo = TipoGrafico.linha;
  final Set<int> _medias = {};
  bool _volume = false;
  late Future<Acao> _futuro;
  late final Future<Analise?> _analise;

  @override
  void initState() {
    super.initState();
    _futuro = _buscar();
    _analise =
        (widget.analises ?? AnalisesService.padrao).de(widget.ticker);
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

  Widget _opcoesGrafico() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<TipoGrafico>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(
                value: TipoGrafico.linha,
                icon: Icon(Icons.show_chart),
                tooltip: 'Linha'),
            ButtonSegment(
                value: TipoGrafico.candles,
                icon: Icon(Icons.candlestick_chart),
                tooltip: 'Candles'),
          ],
          selected: {_tipo},
          onSelectionChanged: (s) => setState(() => _tipo = s.first),
        ),
        for (final n in mediasDisponiveis)
          FilterChip(
            label: Text('MM$n'),
            tooltip: 'Média móvel de $n pregões',
            visualDensity: VisualDensity.compact,
            selected: _medias.contains(n),
            onSelected: (v) =>
                setState(() => v ? _medias.add(n) : _medias.remove(n)),
          ),
        FilterChip(
          label: const Text('Volume'),
          visualDensity: VisualDensity.compact,
          selected: _volume,
          onSelected: (v) => setState(() => _volume = v),
        ),
      ],
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
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
          const SizedBox(height: 8),
          _opcoesGrafico(),
          const SizedBox(height: 12),
          SizedBox(
            height: _volume ? 290 : 240,
            child: GraficoPreco(
              pontos: a.historico,
              tipo: _tipo,
              medias: _medias,
              volume: _volume,
            ),
          ),
          if (a.minimo52 != null && a.maximo52 != null && a.preco != null)
            _Faixa52(min: a.minimo52!, max: a.maximo52!, atual: a.preco!),
          FutureBuilder<Analise?>(
            future: _analise,
            builder: (context, snap) => snap.data == null
                ? const SizedBox.shrink()
                : _CardAnalise(analise: snap.data!),
          ),
          if (!a.temFundamentos)
            Card(
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sem indicadores para este ativo. Eles vêm dos balanços da CVM, '
                  'que FIIs, ETFs e BDRs não publicam. Se for uma ação, o robô '
                  'diário pode ainda não ter rodado (veja o README).',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else ...[
            for (final g in a.grupos) _CardGrupo(grupo: g),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Balanço de ${a.fundamentos!.dataBalanco == null ? '—' : fmtData(a.fundamentos!.dataBalanco!)} '
                '(CVM). P/L, P/VP, DY e valor de mercado usam o preço atual. '
                '✔ verde: dentro da referência; ! laranja: fora dela. Toque num '
                'indicador para ver a explicação.',
                style: tema.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
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

class _CardAnalise extends StatelessWidget {
  const _CardAnalise({required this.analise});
  final Analise analise;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final pequeno = tema.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final a = analise;

    Widget lista(String titulo, List<String> itens, IconData icone, Color cor) =>
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: tema.textTheme.labelLarge),
              for (final s in itens)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icone, size: 16, color: cor),
                      const SizedBox(width: 6),
                      Expanded(child: Text(s)),
                    ],
                  ),
                ),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('Leitura da IA',
                    style: tema.textTheme.titleSmall?.copyWith(color: cs.primary)),
              ],
            ),
            if (a.resumo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(a.resumo),
            ],
            if (a.pontosFortes.isNotEmpty)
              lista('Pontos fortes', a.pontosFortes, Icons.add_circle_outline,
                  Colors.green.shade600),
            if (a.riscos.isNotEmpty)
              lista('Riscos e o que conferir', a.riscos, Icons.error_outline,
                  Colors.orange.shade700),
            if (a.leituraFatos.isNotEmpty || a.fatos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Fatos recentes (CVM)', style: tema.textTheme.labelLarge),
              if (a.leituraFatos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(a.leituraFatos),
                ),
              if (a.fatos.isNotEmpty)
                Theme(
                  data: tema.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Ver os ${a.fatos.length} documentos', style: pequeno),
                    children: [
                      for (final f in a.fatos)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                              f.relevante ? Icons.priority_high : Icons.campaign_outlined,
                              size: 18),
                          title: Text(f.assunto),
                          subtitle: Text(
                              '${f.data == null ? '' : '${fmtData(f.data!)} · '}${f.categoria}'),
                        ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              'Texto gerado por IA${a.modelo == null ? '' : ' (${a.modelo})'}'
              '${a.geradoEm == null ? '' : ' em ${fmtData(a.geradoEm!)}'} a partir dos '
              'indicadores do robô e dos assuntos dos documentos da CVM. Pode conter '
              'erros e não é recomendação de investimento.',
              style: pequeno,
            ),
          ],
        ),
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
            if (i.referencia != null) ...[
              const SizedBox(height: 12),
              Text('Referência: ${fmtReferencia(i.referencia!, i.formato)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Valor usado pela literatura de análise fundamentalista ou pelo '
                'mercado. Serve de régua, não de regra: compare também com '
                'empresas do mesmo setor.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
                subtitle: i.referencia == null
                    ? null
                    : Text('Ref.: ${fmtReferencia(i.referencia!, i.formato)}',
                        style: TextStyle(color: tema.colorScheme.onSurfaceVariant)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatar(i.valor, i.formato),
                        style: tema.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    SizedBox(width: 16, child: seloReferencia(i)),
                  ],
                ),
                onTap: () => _ajuda(context, i),
              ),
          ],
        ),
      ),
    );
  }
}
