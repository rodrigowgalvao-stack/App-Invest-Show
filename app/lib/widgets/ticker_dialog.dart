import 'package:flutter/material.dart';

/// Pede um ticker e devolve em maiúsculas, ou null se cancelar.
Future<String?> pedirTicker(BuildContext context) {
  final ctrl = TextEditingController();
  String? erro;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        void confirmar() {
          final t = ctrl.text.trim().toUpperCase();
          if (!RegExp(r'^[A-Z0-9]{4}\d{1,2}F?$').hasMatch(t)) {
            setDialog(() => erro = 'Use o código da B3, como PETR4 ou TAEE11');
            return;
          }
          Navigator.pop(ctx, t);
        }

        return AlertDialog(
          title: const Text('Adicionar ação'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: 'Ex.: WEGE3', errorText: erro),
            onSubmitted: (_) => confirmar(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(onPressed: confirmar, child: const Text('Adicionar')),
          ],
        );
      },
    ),
  );
}
