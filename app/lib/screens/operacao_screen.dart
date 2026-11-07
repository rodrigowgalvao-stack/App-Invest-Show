import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/carteira.dart';
import '../services/brapi_service.dart';
import '../services/carteira_storage.dart';
import '../widgets/formatacao.dart';
import '../widgets/ticker_dialog.dart';

/// Registra (ou edita) uma compra ou venda. Devolve true se salvou.
Future<bool?> abrirOperacao(
  BuildContext context, {
  required BrapiService api,
  required CarteiraStorage storage,
  Operacao? editar,
  String? ticker,
  TipoOperacao tipo = TipoOperacao.compra,
}) =>
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OperacaoScreen(
          api: api,
          storage: storage,
          editar: editar,
          ticker: ticker,
          tipo: tipo,
        ),
      ),
    );

class OperacaoScreen extends StatefulWidget {
  const OperacaoScreen({
    super.key,
    required this.api,
    required this.storage,
    this.editar,
    this.ticker,
    this.tipo = TipoOperacao.compra,
  });

  final BrapiService api;
  final CarteiraStorage storage;
  final Operacao? editar;
  final String? ticker;
  final TipoOperacao tipo;

  @override
  State<OperacaoScreen> createState() => _OperacaoScreenState();
}

/// Aceita "1.234,56", "1234,56" e "1234.56".
double? _lerNumero(String s) {
  var t = s.trim().replaceAll(RegExp(r'[R$\s]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}

String _escrever(double v) =>
    v.toStringAsFixed(2).replaceAll('.', ',');

class _OperacaoScreenState extends State<OperacaoScreen> {
  final _form = GlobalKey<FormState>();
  final _qtd = TextEditingController();
  final _preco = TextEditingController();
  final _taxas = TextEditingController();
  late TipoOperacao _tipo;
  String? _ticker;
  late DateTime _data;
  String? _erro;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editar;
    _tipo = e?.tipo ?? widget.tipo;
    _ticker = e?.ticker ?? widget.ticker;
    _data = e?.data ?? DateUtils.dateOnly(DateTime.now());
    if (e != null) {
      _qtd.text = '${e.quantidade}';
      _preco.text = _escrever(e.preco);
      if (e.taxas > 0) _taxas.text = _escrever(e.taxas);
    } else if (_ticker != null) {
      _sugerirPreco();
    }
  }

  @override
  void dispose() {
    _qtd.dispose();
    _preco.dispose();
    _taxas.dispose();
    super.dispose();
  }

  /// Preenche com a cotação atual (o usuário corrige se pagou outro valor).
  Future<void> _sugerirPreco() async {
    final t = _ticker;
    if (t == null) return;
    final conhecido = widget.api.precos.de(t)?.preco;
    if (conhecido != null) {
      _preco.text = _escrever(conhecido);
      setState(() {});
      return;
    }
    final r = await widget.api.resultado(t);
    if (!mounted || _ticker != t || _preco.text.isNotEmpty) return;
    final p = r.acao?.preco;
    if (p != null) setState(() => _preco.text = _escrever(p));
  }

  Future<void> _escolherAtivo() async {
    final t = await pedirTicker(context, widget.api, titulo: 'Qual ativo?');
    if (t == null) return;
    setState(() {
      _ticker = t;
      _preco.clear();
    });
    _sugerirPreco();
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _data = d);
  }

  double get _total {
    final q = int.tryParse(_qtd.text) ?? 0;
    final p = _lerNumero(_preco.text) ?? 0;
    final tx = _lerNumero(_taxas.text) ?? 0;
    return _tipo == TipoOperacao.compra ? q * p + tx : q * p - tx;
  }

  Future<void> _salvar() async {
    setState(() => _erro = null);
    if (_ticker == null) {
      setState(() => _erro = 'Escolha o ativo.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    final op = Operacao(
      id: widget.editar?.id ?? '${DateTime.now().microsecondsSinceEpoch}',
      ticker: _ticker!,
      tipo: _tipo,
      data: _data,
      quantidade: int.parse(_qtd.text),
      preco: _lerNumero(_preco.text)!,
      taxas: _lerNumero(_taxas.text) ?? 0,
    );
    setState(() => _salvando = true);
    try {
      await widget.storage.salvar(op);
      if (mounted) Navigator.pop(context, true);
    } on ErroCarteira catch (e) {
      setState(() {
        _erro = e.mensagem;
        _salvando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editar == null ? 'Nova operação' : 'Editar operação'),
        actions: [
          TextButton(
            onPressed: _salvando ? null : _salvar,
            child: const Text('Salvar'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<TipoOperacao>(
              segments: const [
                ButtonSegment(
                    value: TipoOperacao.compra,
                    label: Text('Compra'),
                    icon: Icon(Icons.add_shopping_cart)),
                ButtonSegment(
                    value: TipoOperacao.venda,
                    label: Text('Venda'),
                    icon: Icon(Icons.sell_outlined)),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.search),
                title: Text(_ticker ?? 'Escolher ativo',
                    style: TextStyle(
                        fontWeight: _ticker == null ? null : FontWeight.w700)),
                subtitle: const Text('Código ou nome'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _escolherAtivo,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.event),
                title: Text(fmtData(_data)),
                subtitle: const Text('Data do pregão'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _escolherData,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _qtd,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Quantidade', border: OutlineInputBorder()),
              validator: (v) =>
                  (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Informe a quantidade' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _preco,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preço por ação',
                prefixText: 'R\$ ',
                helperText: 'Vem com a cotação atual; corrija para o preço pago.',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (_lerNumero(v ?? '') ?? 0) <= 0
                  ? 'Informe o preço'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _taxas,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Taxas (opcional)',
                prefixText: 'R\$ ',
                helperText: 'Corretagem e emolumentos da nota.',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().isNotEmpty && (_lerNumero(v!) ?? -1) < 0
                      ? 'Valor inválido'
                      : null,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_tipo == TipoOperacao.compra ? 'Total pago' : 'Total recebido',
                    style: tema.textTheme.titleMedium),
                Text(fmtMoeda(_total),
                    style: tema.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(_erro!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: Text(_tipo == TipoOperacao.compra
                  ? 'Registrar compra'
                  : 'Registrar venda'),
            ),
          ],
        ),
      ),
    );
  }
}
