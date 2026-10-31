import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/acao.dart' show Formato;
import '../models/oportunidade.dart';
import '../services/brapi_service.dart';
import '../services/oportunidades_service.dart';
import '../services/watchlist_storage.dart';
import '../widgets/estado_erro.dart';
import '../widgets/formatacao.dart';
import 'detalhe_screen.dart';

class OportunidadesScreen extends StatefulWidget {
  const OportunidadesScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.servico,
  });

  final BrapiService api;
  final WatchlistStorage storage;
  final OportunidadesService servico;

  @override
  State<OportunidadesScreen> createState() => _OportunidadesScreenState();
}

class _OportunidadesScreenState extends State<OportunidadesScreen> {
  late Future<RelatorioOportunidades> _futuro;
  Set<String> _naLista = {};

  @override
  void initState() {
    super.initState();
    _futuro = widget.servico.carregar();
    widget.storage.carregar().then((l) {
      if (mounted) setState(() => _naLista = l.toSet());
    });
  }

  Future<void> _recarregar() async {
    setState(() => _futuro = widget.servico.carregar());
    await _futuro.then((_) {}, onError: (_) {});
  }

  Future<void> _adicionar(String ticker) async {
    final lista = await widget.storage.carregar();
    if (!lista.contains(ticker)) {
      lista.add(ticker);
      await widget.storage.salvar(lista);
    }
    if (!mounted) return;
    setState(() => _naLista.add(ticker));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$ticker adicionada à Minha lista')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Oportunidades')),
      body: FutureBuilder<RelatorioOportunidades>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EstadoErro(
                mensagem: snap.error.toString(), onTentar: _recarregar);
          }
          return _conteudo(snap.data!);
        },
      ),
    );
  }

  Widget _conteudo(RelatorioOportunidades rel) {
    final tema = Theme.of(context);
    final quando = rel.geradoEm == null
        ? 'data desconhecida'
        : DateFormat("dd/MM/yyyy 'às' HH:mm").format(rel.geradoEm!);

    return RefreshIndicator(
      onRefresh: _recarregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Ranking de $quando', style: tema.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            '${rel.aprovadas} de ${rel.analisadas} ações passaram nos filtros. '
            'Estas são as melhores notas.',
            style: tema.textTheme.bodySmall
                ?.copyWith(color: tema.colorScheme.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Como o ranking é feito'),
              onPressed: () => _mostrarCriterios(rel),
            ),
          ),
          if (rel.itens.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                  child: Text('Nenhuma ação passou nos filtros esta semana.')),
            ),
          for (var i = 0; i < rel.itens.length; i++)
            _CartaoOportunidade(
              posicao: i + 1,
              o: rel.itens[i],
              naLista: _naLista.contains(rel.itens[i].ticker),
              onAdicionar: () => _adicionar(rel.itens[i].ticker),
              onAbrir: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DetalheScreen(ticker: rel.itens[i].ticker, api: widget.api),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _mostrarCriterios(RelatorioOportunidades rel) {
    const rotulos = {
      'universo_por_liquidez': ('Ações mais negociadas analisadas', Formato.multiplo),
      'valor_mercado_min': ('Valor de mercado mínimo', Formato.moedaCompacta),
      'roe_min': ('ROE mínimo', Formato.percentual),
      'margem_liquida_min': ('Margem líquida mínima', Formato.percentual),
      'div_liq_ebitda_max': ('Dív. líquida/EBITDA máxima', Formato.multiplo),
      'pl_max': ('P/L máximo', Formato.multiplo),
      'taxa_bazin': ('Taxa de Bazin', Formato.percentual),
    };
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text('Como o ranking é feito',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Toda semana o robô analisa as ações mais negociadas da B3 '
              '(uma classe por empresa) e elimina as que não passam nos filtros abaixo. '
              'Os indicadores vêm dos balanços oficiais entregues à CVM, '
              'somando os últimos 12 meses.\n\n'
              'Preço justo de Graham: √(22,5 × LPA × VPA).\n'
              'Preço justo de Bazin: dividendos e JCP pagos nos últimos 12 meses ÷ taxa de Bazin.\n'
              'Potencial: quanto o preço justo está acima do preço atual.\n\n'
              'A nota (0 a 100) pesa ROE (30%), margem líquida (20%), '
              'lucro sobre preço (25%) e o maior potencial entre Graham e Bazin (25%). '
              'Para bancos, que não têm margem líquida, os outros fatores pesam mais.',
            ),
            const SizedBox(height: 16),
            for (final e in rotulos.entries)
              if (rel.criterios[e.key] != null)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value.$1),
                  trailing: Text(e.key == 'universo_por_liquidez'
                      ? '${rel.criterios[e.key]}'
                      : formatar((rel.criterios[e.key] as num).toDouble(),
                          e.value.$2)),
                ),
            const SizedBox(height: 8),
            Text(
              'É um filtro para escolher o que analisar, não uma recomendação. '
              'Graham funciona mal para empresas de crescimento, e um lucro '
              'não recorrente ou um dividendo extraordinário pode distorcer tudo.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoOportunidade extends StatelessWidget {
  const _CartaoOportunidade({
    required this.posicao,
    required this.o,
    required this.naLista,
    required this.onAdicionar,
    required this.onAbrir,
  });

  final int posicao;
  final Oportunidade o;
  final bool naLista;
  final VoidCallback onAdicionar;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAbrir,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('$posicao',
                      style: tema.textTheme.headlineSmall?.copyWith(
                          color: cs.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.ticker,
                            style: tema.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(o.nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tema.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: naLista ? 'Já está na sua lista' : 'Adicionar à Minha lista',
                    onPressed: naLista ? null : onAdicionar,
                    icon: Icon(naLista ? Icons.bookmark : Icons.bookmark_add_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Valor(titulo: 'Preço', valor: fmtMoeda(o.preco)),
                    _Valor(
                      titulo: 'Justo (Graham)',
                      valor: fmtMoeda(o.precoJustoGraham),
                      potencial: o.potencialGraham,
                    ),
                    _Valor(
                      titulo: 'Justo (Bazin)',
                      valor: fmtMoeda(o.precoJustoBazin),
                      potencial: o.potencialBazin,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Etiqueta('Nota ${o.nota?.toStringAsFixed(0) ?? '—'}', destaque: true),
                  _Etiqueta('ROE ${formatar(o.roe, Formato.percentual)}'),
                  _Etiqueta('P/L ${formatar(o.pl, Formato.multiplo)}'),
                  _Etiqueta('P/VP ${formatar(o.pvp, Formato.multiplo)}'),
                  _Etiqueta('DY ${formatar(o.dy, Formato.percentual)}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor({required this.titulo, required this.valor, this.potencial});
  final String titulo;
  final String valor;
  final double? potencial;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: tema.textTheme.labelSmall
                  ?.copyWith(color: tema.colorScheme.onSurfaceVariant)),
          Text(valor, style: tema.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (potencial != null)
            Text(fmtVariacao(potencial),
                style: tema.textTheme.labelSmall
                    ?.copyWith(color: corVariacao(context, potencial))),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, {this.destaque = false});
  final String texto;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: destaque ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 12,
              color: destaque ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
    );
  }
}
