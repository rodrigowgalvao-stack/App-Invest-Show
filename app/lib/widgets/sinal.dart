import 'package:flutter/material.dart';

import '../models/ranking.dart';

/// Cores e rótulos dos sinais da carteira. Verde/vermelho seguem o resto do
/// app (bom/ruim); laranja é "olhe com cuidado".
(String, IconData, Color) estiloSinal(BuildContext context, Sinal s) {
  final cs = Theme.of(context).colorScheme;
  return switch (s) {
    Sinal.compra => ('Possível compra', Icons.trending_up, Colors.green.shade600),
    Sinal.venda => ('Possível venda', Icons.trending_down, Colors.red.shade600),
    Sinal.atencao => ('Atenção', Icons.warning_amber, Colors.orange.shade700),
    Sinal.manter => ('Manter', Icons.pause_circle_outline, cs.onSurfaceVariant),
    Sinal.semAnalise => ('Sem análise', Icons.help_outline, cs.onSurfaceVariant),
  };
}

class SeloSinal extends StatelessWidget {
  const SeloSinal(this.sinal, {super.key});
  final Sinal sinal;

  @override
  Widget build(BuildContext context) {
    final (rotulo, icone, cor) = estiloSinal(context, sinal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withAlpha(28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: cor),
          const SizedBox(width: 4),
          Text(rotulo,
              style: TextStyle(
                  fontSize: 12, color: cor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
