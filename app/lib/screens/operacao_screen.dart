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
double? lerNumero(String s) {
  var t = s.trim().replaceAll(RegExp(r'[R$\s]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(t);
}

String escreverValor(double v) =>
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

  /// Saldo em conta (null se o usuário não informou) e se a operação mexe nele.
  double? _saldo;
  bool _ajustarSaldo = true;

  @override
  void initState() {
    super.initState();
    final e = widget.editar;
    _tipo = e?.tipo ?? widget.tipo;
    _ticker = e?.ticker ?? widget.ticker;
    _data = e?.data ?? DateUtils.dateOnly(DateTime.now());
    if (e != null) {
      _qtd.text = '${e.quantidade}';
      _preco.text = escreverValor(e.preco);
      if (e.taxas > 0) _taxas.text = escreverValor(e.taxas);
    } else if (_ticker != null) {
      _sugerirPreco();
    }
    // Numa edição, o padrão é não mexer: o saldo pode ter sido informado
    // depois da operação original.
    _ajustarSaldo = e == null;
    widget.storage.saldo().then((v) {
      if (mounted) setState(() => _saldo = v);
    });
  }

  /// Quanto o saldo muda ao salvar (numa edição, só a diferença).
  double get _efeitoNoSaldo {
    final atual = _tipo == TipoOperacao.compra ? -_total : _total;
    return atual - (widget.editar?.efeitoNoSaldo ?? 0);
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
      _preco.text = escreverValor(conhecido);
      setState(() {});
      return;
    }
    final r = await widget.api.resultado(t);
    if (!mounted || _ticker != t || _preco.text.isNotEmpty) return;
    final p = r.acao?.preco;
    if (p != null) setState(() => _preco.text = escreverValor(p));
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
    final p = lerNumero(_preco.text) ?? 0;
    final tx = lerNumero(_taxas.text) ?? 0;
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
      preco: lerNumero(_preco.text)!,
      taxas: lerNumero(_taxas.text) ?? 0,
    );
    setState(() => _salvando = true);
    try {
      await widget.storage
          .salvar(op, ajustarSaldo: _saldo != null && _ajustarSaldo);
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
              validator: (v) => (lerNumero(v ?? '') ?? 0) <= 0
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
                  (v ?? '').trim().isNotEmpty && (lerNumero(v!) ?? -1) < 0
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
            if (_saldo != null) ...[
              const SizedBox(height: 8),
              _SaldoNaOperacao(
                saldo: _saldo!,
                efeito: _efeitoNoSaldo,
                ajustar: _ajustarSaldo,
                onAjustar: (v) => setState(() => _ajustarSaldo = v),
              ),
            ],
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

class _SaldoNaOperacao extends StatelessWidget {
  const _SaldoNaOperacao({
    required this.saldo,
    required this.efeito,
    required this.ajustar,
    required this.onAjustar,
  });

  final double saldo;
  final double efeito;
  final bool ajustar;
  final ValueChanged<bool> onAjustar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;
    final depois = saldo + efeito;
    final falta = ajustar && depois < 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.account_balance_outlined),
            title: const Text('Atualizar saldo em conta'),
            subtitle: Text('Saldo agora: ${fmtMoeda(saldo)}'),
            value: ajustar,
            onChanged: onAjustar,
          ),
          if (ajustar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Saldo depois'),
                      Text(fmtMoeda(depois),
                          style: tema.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: falta ? cs.error : null)),
                    ],
                  ),
                  if (falta)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'O saldo não cobre a compra (faltam ${fmtMoeda(-depois)}). '
                        'Dá para salvar mesmo assim.',
                        style: tema.textTheme.bodySmall?.copyWith(color: cs.error),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
