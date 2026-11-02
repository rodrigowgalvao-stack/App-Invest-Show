import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/acao.dart';
import 'formatacao.dart';

enum TipoGrafico { linha, candles }

/// Cores das médias móveis e das séries do comparador: evitam o
/// verde/vermelho, que no app querem dizer alta/queda.
const coresSeries = [Color(0xFF2F6FDE), Color(0xFFE07B00), Color(0xFF8E44AD)];
const _coresMedias = {20: Color(0xFFE0A100), 50: Color(0xFF8E44AD)};
const mediasDisponiveis = [20, 50];

/// Média móvel simples; null enquanto não há [n] pontos.
List<double?> mediaMovel(List<double> valores, int n) {
  final r = List<double?>.filled(valores.length, null);
  var soma = 0.0;
  for (var i = 0; i < valores.length; i++) {
    soma += valores[i];
    if (i >= n) soma -= valores[i - n];
    if (i >= n - 1) r[i] = soma / n;
  }
  return r;
}

class GraficoPreco extends StatefulWidget {
  const GraficoPreco({
    super.key,
    required this.pontos,
    this.tipo = TipoGrafico.linha,
    this.medias = const {},
    this.volume = false,
  });

  final List<PontoHistorico> pontos;
  final TipoGrafico tipo;

  /// Períodos das médias móveis a desenhar (ex.: {20, 50}).
  final Set<int> medias;
  final bool volume;

  @override
  State<GraficoPreco> createState() => _GraficoPrecoState();
}

class _GraficoPrecoState extends State<GraficoPreco> {
  /// Candle tocado (o gráfico de linha usa o tooltip do fl_chart).
  int? _tocado;

  List<PontoHistorico> get _p => widget.pontos;

  @override
  void didUpdateWidget(GraficoPreco old) {
    super.didUpdateWidget(old);
    if (old.pontos != widget.pontos || old.tipo != widget.tipo) _tocado = null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_p.length < 2) {
      return Center(
        child: Text('Sem histórico para este período.',
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    final fechamentos = [for (final p in _p) p.fechamento];
    final medias = {
      for (final n in widget.medias)
        if (_p.length > n) n: mediaMovel(fechamentos, n),
    };
    final temVolume =
        widget.volume && _p.any((p) => (p.volume ?? 0) > 0);

    final principal = widget.tipo == TipoGrafico.candles
        ? _candles(cs, medias)
        : _linha(cs, medias);

    return Column(
      children: [
        if (medias.isNotEmpty) _Legenda(medias: medias.keys.toList()),
        Expanded(child: principal),
        if (temVolume) ...[
          const SizedBox(height: 6),
          SizedBox(height: 48, child: _barrasVolume(cs)),
        ],
      ],
    );
  }

  Widget _linha(ColorScheme cs, Map<int, List<double?>> medias) {
    final subiu = _p.last.fechamento >= _p.first.fechamento;
    final cor = subiu ? Colors.green.shade600 : Colors.red.shade600;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            fitInsideHorizontally: true,
            getTooltipItems: (spots) => spots.map((s) {
              // Só a linha de preço tem tooltip; as médias entram no texto.
              if (s.barIndex != 0) return null;
              final i = s.x.toInt();
              final p = _p[i];
              final extras = [
                for (final e in medias.entries)
                  if (e.value[i] != null) '\nMM${e.key}: ${fmtMoeda(e.value[i])}',
              ].join();
              return LineTooltipItem(
                '${fmtData(p.data)}\n${fmtMoeda(p.fechamento)}$extras',
                TextStyle(color: cs.onInverseSurface, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < _p.length; i++)
                FlSpot(i.toDouble(), _p[i].fechamento),
            ],
            barWidth: 2,
            color: cor,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: cor.withAlpha(30)),
          ),
          for (final e in medias.entries)
            LineChartBarData(
              spots: [
                for (var i = 0; i < _p.length; i++)
                  e.value[i] == null
                      ? FlSpot.nullSpot
                      : FlSpot(i.toDouble(), e.value[i]!),
              ],
              barWidth: 1.5,
              color: _coresMedias[e.key],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  Widget _candles(ColorScheme cs, Map<int, List<double?>> medias) {
    return LayoutBuilder(builder: (context, c) {
      int indice(Offset o) =>
          (o.dx / c.maxWidth * _p.length).floor().clamp(0, _p.length - 1);
      void tocar(Offset o) => setState(() => _tocado = indice(o));

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => tocar(d.localPosition),
        onHorizontalDragStart: (d) => tocar(d.localPosition),
        onHorizontalDragUpdate: (d) => tocar(d.localPosition),
        onHorizontalDragEnd: (_) => setState(() => _tocado = null),
        onTapUp: (_) => setState(() => _tocado = null),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PintorCandles(
                  pontos: _p,
                  medias: medias,
                  alta: Colors.green.shade600,
                  baixa: Colors.red.shade600,
                  cursor: cs.onSurfaceVariant,
                  tocado: _tocado,
                ),
              ),
            ),
            if (_tocado != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(child: _detalheCandle(cs, _tocado!, medias)),
              ),
          ],
        ),
      );
    });
  }

  Widget _detalheCandle(
      ColorScheme cs, int i, Map<int, List<double?>> medias) {
    final p = _p[i];
    final estilo = TextStyle(color: cs.onInverseSurface, fontSize: 12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${fmtData(p.data)}\n'
        'Abertura ${fmtMoeda(p.abertura)} · Fechamento ${fmtMoeda(p.fechamento)}\n'
        'Máxima ${fmtMoeda(p.maxima)} · Mínima ${fmtMoeda(p.minima)}'
        '${[
          for (final e in medias.entries)
            if (e.value[i] != null) '\nMM${e.key}: ${fmtMoeda(e.value[i])}',
        ].join()}',
        style: estilo,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _barrasVolume(ColorScheme cs) {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        alignment: BarChartAlignment.spaceBetween,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            fitInsideHorizontally: true,
            getTooltipItem: (g, _, __, ___) {
              final p = _p[g.x];
              return BarTooltipItem(
                '${fmtData(p.data)}\nVolume ${fmtVolume(p.volume)}',
                TextStyle(color: cs.onInverseSurface, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < _p.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: _p[i].volume ?? 0,
                width: math.max(1, 240 / _p.length),
                borderRadius: BorderRadius.zero,
                color: (_p[i].fechamento >= _p[i].abertura
                        ? Colors.green.shade600
                        : Colors.red.shade600)
                    .withAlpha(110),
              ),
            ]),
        ],
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.medias});
  final List<int> medias;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 12,
        children: [
          for (final n in medias)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 3, color: _coresMedias[n]),
              const SizedBox(width: 4),
              Text('Média $n dias', style: estilo),
            ]),
        ],
      ),
    );
  }
}

class _PintorCandles extends CustomPainter {
  _PintorCandles({
    required this.pontos,
    required this.medias,
    required this.alta,
    required this.baixa,
    required this.cursor,
    required this.tocado,
  });

  final List<PontoHistorico> pontos;
  final Map<int, List<double?>> medias;
  final Color alta, baixa, cursor;
  final int? tocado;

  @override
  void paint(Canvas canvas, Size size) {
    var minimo = double.infinity, maximo = -double.infinity;
    for (final p in pontos) {
      minimo = math.min(minimo, p.minima);
      maximo = math.max(maximo, p.maxima);
    }
    for (final serie in medias.values) {
      for (final v in serie) {
        if (v == null) continue;
        minimo = math.min(minimo, v);
        maximo = math.max(maximo, v);
      }
    }
    final folga = (maximo - minimo) * 0.05;
    minimo -= folga;
    maximo += folga;
    final faixa = maximo - minimo == 0 ? 1.0 : maximo - minimo;
    double y(double v) => size.height * (1 - (v - minimo) / faixa);

    final passo = size.width / pontos.length;
    final corpo = math.max(1.0, passo * 0.7);
    double x(int i) => passo * (i + 0.5);

    if (tocado != null) {
      canvas.drawLine(
        Offset(x(tocado!), 0),
        Offset(x(tocado!), size.height),
        Paint()
          ..color = cursor.withAlpha(90)
          ..strokeWidth = 1,
      );
    }

    final pincel = Paint()..strokeWidth = 1;
    for (var i = 0; i < pontos.length; i++) {
      final p = pontos[i];
      pincel.color = p.fechamento >= p.abertura ? alta : baixa;
      canvas.drawLine(Offset(x(i), y(p.maxima)), Offset(x(i), y(p.minima)), pincel);
      final topo = y(math.max(p.abertura, p.fechamento));
      final base = y(math.min(p.abertura, p.fechamento));
      canvas.drawRect(
        Rect.fromLTRB(x(i) - corpo / 2, topo, x(i) + corpo / 2,
            math.max(base, topo + 1)),
        pincel..style = PaintingStyle.fill,
      );
    }

    for (final e in medias.entries) {
      final caminho = Path();
      var comecou = false;
      for (var i = 0; i < e.value.length; i++) {
        final v = e.value[i];
        if (v == null) continue;
        if (comecou) {
          caminho.lineTo(x(i), y(v));
        } else {
          caminho.moveTo(x(i), y(v));
          comecou = true;
        }
      }
      canvas.drawPath(
        caminho,
        Paint()
          ..color = _coresMedias[e.key] ?? cursor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorCandles old) =>
      old.pontos != pontos || old.medias != medias || old.tocado != tocado;
}

/// Compara o desempenho de várias ações no período: cada linha começa
/// em 0% e mostra quanto subiu ou caiu desde o primeiro dia.
class GraficoRentabilidade extends StatelessWidget {
  const GraficoRentabilidade({super.key, required this.series});

  /// Ticker → histórico (na ordem das cores de [coresSeries]).
  final Map<String, List<PontoHistorico>> series;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final validas = {
      for (final e in series.entries)
        if (e.value.length >= 2 && e.value.first.fechamento > 0) e.key: e.value,
    };
    if (validas.isEmpty) {
      return Center(
        child: Text('Sem histórico para comparar.',
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    // Eixo x em dias desde a primeira data, para alinhar pregões iguais.
    final inicio = validas.values
        .map((l) => l.first.data)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    double dia(DateTime d) => d.difference(inicio).inHours / 24;
    final tickers = validas.keys.toList();

    return Column(
      children: [
        Wrap(
          spacing: 12,
          children: [
            for (var k = 0; k < tickers.length; k++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 12,
                    height: 3,
                    color: coresSeries[k % coresSeries.length]),
                const SizedBox(width: 4),
                Text(
                  '${tickers[k]} ${fmtVariacao(_rent(validas[tickers[k]]!, validas[tickers[k]]!.length - 1))}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                checkToShowHorizontalLine: (v) => v == 0,
                getDrawingHorizontalLine: (_) => FlLine(
                    color: cs.outlineVariant, strokeWidth: 1, dashArray: [4, 4]),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                bottomTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, meta) {
                      if (v == meta.min || v == meta.max) {
                        return const SizedBox();
                      }
                      return Text('${v.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 10, color: cs.onSurfaceVariant));
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => cs.inverseSurface,
                  fitInsideHorizontally: true,
                  getTooltipItems: (spots) => spots.map((s) {
                    final t = tickers[s.barIndex];
                    final p = validas[t]![s.spotIndex];
                    return LineTooltipItem(
                      '${s.barIndex == spots.first.barIndex ? '${fmtData(p.data)}\n' : ''}'
                      '$t ${fmtVariacao(s.y)}',
                      TextStyle(color: coresSeries[s.barIndex % coresSeries.length],
                          fontSize: 12, fontWeight: FontWeight.w600),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                for (var k = 0; k < tickers.length; k++)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < validas[tickers[k]]!.length; i++)
                        FlSpot(dia(validas[tickers[k]]![i].data),
                            _rent(validas[tickers[k]]!, i)),
                    ],
                    barWidth: 2,
                    color: coresSeries[k % coresSeries.length],
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static double _rent(List<PontoHistorico> l, int i) =>
      (l[i].fechamento / l.first.fechamento - 1) * 100;
}
