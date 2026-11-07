import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/acao.dart' show Formato;
import '../models/carteira.dart';
import '../models/fundamentos.dart';
import '../models/ranking.dart';
import '../services/brapi_service.dart';
import '../services/carteira_storage.dart';
import '../services/oportunidades_service.dart';
import '../widgets/formatacao.dart';
import '../widgets/sinal.dart';
import 'operacao_screen.dart';
import 'posicao_screen.dart';

/// Cores da alocação: distintas entre si e longe do verde/vermelho de alta e queda.
const coresAlocacao = [
  Color(0xFF2F6FDE),
  Color(0xFFE07B00),
  Color(0xFF8E44AD),
  Color(0xFF00897B),
  Color(0xFFC2185B),
  Color(0xFF5D4037),
  Color(0xFF607D8B),
  Color(0xFFAFB42B),
];

class CarteiraScreen extends StatefulWidget {
  const CarteiraScreen({
    super.key,
    required this.api,
    required this.storage,
    required this.servico,
  });

  final BrapiService api;
  final CarteiraStorage storage;
  final OportunidadesService servico;

  @override
  State<CarteiraScreen> createState() => _CarteiraScreenState();
}

class _CarteiraScreenState extends State<CarteiraScreen> {
  List<Operacao> _ops = [];
  Map<String, Fundamentos> _fund = const {};
  Map<String, dynamic> _criterios = criteriosPadrao;
  bool _carregando = true;
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    widget.api.precos.addListener(_mudou);
    widget.storage.addListener(_mudouOperacoes);
    _relogio = Timer.periodic(
        const Duration(minutes: 5), (_) => widget.api.atualizarPrecos());
    _carregar();
  }

  @override
  void dispose() {
    widget.api.precos.removeListener(_mudou);
    widget.storage.removeListener(_mudouOperacoes);
    _relogio?.cancel();
    super.dispose();
  }

  void _mudou() {
    if (mounted) setState(() {});
  }

  Future<void> _mudouOperacoes() async {
    final ops = await widget.storage.carregar();
    if (!mounted) return;
    setState(() => _ops = ops);
    _precosQueFaltam();
  }

  Future<void> _carregar({bool forcar = false}) async {
    if (mounted) setState(() => _carregando = true);
    final ops = widget.storage.carregar();
    final fund = widget.api.todosFundamentos();
    final criterios = widget.servico
        .carregar()
        .then((r) => r.criterios.isEmpty ? criteriosPadrao : r.criterios)
        .catchError((_) => criteriosPadrao);
    await widget.api.atualizarPrecos(forcar: forcar);
    _ops = await ops;
    _fund = await fund;
    _criterios = await criterios;
    if (mounted) setState(() => _carregando = false);
    await _precosQueFaltam(forcar: forcar);
  }

  /// A lista geral da brapi às vezes não traz um ativo (ex.: ETF pouco
  /// negociado): busca esses um a um.
  Future<void> _precosQueFaltam({bool forcar = false}) async {
    final abertos = calcularPosicoesSeguro(_ops)
        .values
        .where((p) => p.aberta)
        .map((p) => p.ticker);
    final faltam = [
      for (final t in abertos)
        if (forcar || widget.api.precos.de(t) == null) t,
    ];
    if (faltam.isNotEmpty) await widget.api.varias(faltam, forcar: forcar);
  }

  Future<void> _novaOperacao() =>
      abrirOperacao(context, api: widget.api, storage: widget.storage);

  @override
  Widget build(BuildContext context) {
    final posicoes = calcularPosicoesSeguro(_ops);
    final abertas = posicoes.values.where((p) => p.aberta).toList();
    final encerradas = posicoes.values.where((p) => !p.aberta).toList();
    final precos = widget.api.precos.mapa;
    final resumo = ResumoCarteira(posicoes, precos);
    abertas.sort((a, b) => (b.valorAtual(precos[b.ticker]) ?? b.custo)
        .compareTo(a.valorAtual(precos[a.ticker]) ?? a.custo));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carteira'),
        actions: [
          IconButton(
            tooltip: 'Atualizar preços',
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : () => _carregar(forcar: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novaOperacao,
        icon: const Icon(Icons.add),
        label: const Text('Compra / venda'),
      ),
      body: _carregando && _ops.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _carregar(forcar: true),
              child: _ops.isEmpty
                  ? _vazia()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      children: [
                        if (_carregando) const LinearProgressIndicator(),
                        _Resumo(resumo: resumo, abertas: abertas, api: widget.api),
                        if (abertas.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _Alocacao(abertas: abertas, precos: precos),
                        ],
                        const SizedBox(height: 8),
                        for (final p in abertas)
                          _CartaoPosicao(
                            p: p,
                            preco: precos[p.ticker],
                            variacao: widget.api.precos.de(p.ticker)?.variacaoPct,
                            peso: resumo.patrimonio > 0
                                ? (p.valorAtual(precos[p.ticker]) ?? p.custo) /
                                    resumo.patrimonio *
                                    100
                                : null,
                            avaliacao: avaliarAtivo(_fund[p.ticker], precos[p.ticker],
                                criterios: _criterios),
                            onTap: () => _abrir(p.ticker),
                          ),
                        if (encerradas.isNotEmpty)
                          Card(
                            margin: const EdgeInsets.only(top: 12),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              title: Text('Posições encerradas (${encerradas.length})'),
                              children: [
                                for (final p in encerradas)
                                  ListTile(
                                    title: Text(p.ticker),
                                    subtitle: Text('${p.operacoes.length} operações'),
                                    trailing: Text(fmtMoedaSinal(p.realizado),
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: corVariacao(context, p.realizado))),
                                    onTap: () => _abrir(p.ticker),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          'Possível compra/venda usa os mesmos filtros do ranking '
                          '(preço justo de Graham e Bazin, P/L, ROE, dívida). É um '
                          'alerta para você analisar, não uma recomendação.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
            ),
    );
  }

  void _abrir(String ticker) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PosicaoScreen(
            ticker: ticker,
            api: widget.api,
            storage: widget.storage,
            fundamentos: _fund[ticker],
            criterios: _criterios,
          ),
        ),
      );

  Widget _vazia() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.account_balance_wallet_outlined,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text(
            'Registre suas compras e vendas para acompanhar preço médio, '
            'resultado e sinais de compra ou venda de cada ação.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: _novaOperacao,
              icon: const Icon(Icons.add),
              label: const Text('Registrar primeira compra'),
            ),
          ),
        ],
      );
}

/// Na tela, uma operação inconsistente (não deveria acontecer: o storage
/// recusa) não pode derrubar tudo.
Map<String, Posicao> calcularPosicoesSeguro(List<Operacao> ops) {
  try {
    return calcularPosicoes(ops);
  } on ErroCarteira {
    return const {};
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.resumo, required this.abertas, required this.api});
  final ResumoCarteira resumo;
  final List<Posicao> abertas;
  final BrapiService api;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cinza = tema.textTheme.labelMedium
        ?.copyWith(color: tema.colorScheme.onSurfaceVariant);

    // Variação de hoje: valor atual × var / (1 + var), somado por ativo.
    double? hoje;
    for (final p in abertas) {
      final pa = api.precos.de(p.ticker);
      if (pa?.variacaoPct == null) continue;
      final v = pa!.preco * p.quantidade;
      hoje = (hoje ?? 0) + v - v / (1 + pa.variacaoPct! / 100);
    }

    Widget item(String titulo, String valor, {Color? cor}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: cinza),
              Text(valor,
                  style: tema.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: cor)),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patrimônio', style: cinza),
            Text(fmtMoeda(resumo.patrimonio),
                style: tema.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              '${fmtMoedaSinal(resumo.resultado)} (${fmtVariacao(resumo.resultadoPct)})',
              style: tema.textTheme.titleMedium?.copyWith(
                  color: corVariacao(context, resumo.resultado)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              item('Investido', fmtMoeda(resumo.investido)),
              item('Hoje', hoje == null ? '—' : fmtMoedaSinal(hoje),
                  cor: corVariacao(context, hoje)),
              item('Vendas (realizado)', fmtMoedaSinal(resumo.realizado),
                  cor: corVariacao(context, resumo.realizado)),
            ]),
            if (resumo.semPreco > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${resumo.semPreco} ativo(s) sem cotação: entram pelo valor investido.',
                style: cinza,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Alocacao extends StatelessWidget {
  const _Alocacao({required this.abertas, required this.precos});
  final List<Posicao> abertas;
  final Map<String, double> precos;

  @override
  Widget build(BuildContext context) {
    final valores = [
      for (final p in abertas) p.valorAtual(precos[p.ticker]) ?? p.custo,
    ];
    final total = valores.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const SizedBox();
    // Até 7 fatias; o resto vira "Outros".
    const maxFatias = 7;
    final fatias = <(String, double)>[
      for (var i = 0; i < abertas.length && i < maxFatias; i++)
        (abertas[i].ticker, valores[i]),
      if (abertas.length > maxFatias)
        ('Outros', valores.skip(maxFatias).fold(0.0, (a, b) => a + b)),
    ];
    final estilo = Theme.of(context).textTheme.bodySmall;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 30,
                  sections: [
                    for (var i = 0; i < fatias.length; i++)
                      PieChartSectionData(
                        value: fatias[i].$2,
                        color: coresAlocacao[i % coresAlocacao.length],
                        radius: 22,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alocação', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  for (var i = 0; i < fatias.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Row(children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: coresAlocacao[i % coresAlocacao.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(fatias[i].$1, style: estilo)),
                        Text(
                            formatar(fatias[i].$2 / total * 100, Formato.percentual),
                            style: estilo),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoPosicao extends StatelessWidget {
  const _CartaoPosicao({
    required this.p,
    required this.preco,
    required this.variacao,
    required this.peso,
    required this.avaliacao,
    required this.onTap,
  });

  final Posicao p;
  final double? preco;
  final double? variacao;
  final double? peso;
  final Avaliacao avaliacao;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cinza = tema.textTheme.bodySmall
        ?.copyWith(color: tema.colorScheme.onSurfaceVariant);
    final resultado = p.resultado(preco);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(p.ticker,
                      style: tema.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  SeloSinal(avaliacao.sinal),
                  const Spacer(),
                  Text(fmtMoeda(p.valorAtual(preco) ?? p.custo),
                      style: tema.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${p.quantidade} × PM ${fmtMoeda(p.precoMedio)}'
                      '${peso == null ? '' : ' · ${formatar(peso, Formato.percentual)} da carteira'}',
                      style: cinza,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    resultado == null
                        ? '—'
                        : '${fmtMoedaSinal(resultado)} (${fmtVariacao(p.resultadoPct(preco))})',
                    style: tema.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: corVariacao(context, resultado)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text('Atual ${fmtMoeda(preco)}', style: cinza),
                  const SizedBox(width: 6),
                  Text(fmtVariacao(variacao),
                      style: tema.textTheme.bodySmall
                          ?.copyWith(color: corVariacao(context, variacao))),
                  Text(' hoje', style: cinza),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
