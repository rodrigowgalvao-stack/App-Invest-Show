import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/acao.dart';
import 'formatacao.dart';

class GraficoPreco extends StatelessWidget {
  const GraficoPreco({super.key, required this.pontos});
  final List<PontoHistorico> pontos;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (pontos.length < 2) {
      return Center(
        child: Text('Sem histórico para este período.',
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    final subiu = pontos.last.fechamento >= pontos.first.fechamento;
    final cor = subiu ? Colors.green.shade600 : Colors.red.shade600;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (spots) => spots.map((s) {
              final p = pontos[s.x.toInt()];
              return LineTooltipItem(
                '${fmtData(p.data)}\n${fmtMoeda(p.fechamento)}',
                TextStyle(color: cs.onInverseSurface, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < pontos.length; i++)
                FlSpot(i.toDouble(), pontos[i].fechamento),
            ],
            barWidth: 2,
            color: cor,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: cor.withAlpha(30)),
          ),
        ],
      ),
    );
  }
}
