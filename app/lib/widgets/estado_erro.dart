import 'package:flutter/material.dart';

class EstadoErro extends StatelessWidget {
  const EstadoErro({super.key, required this.mensagem, required this.onTentar});
  final String mensagem;
  final VoidCallback onTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
                onPressed: onTentar, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
