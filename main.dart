import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

const categorias = <String>[
  'Alimentação',
  'Moradia',
  'Transporte',
  'Saúde',
  'Lazer',
  'Educação',
  'Compras',
  'Contas',
  'Outros',
];

class Gasto {
  final int? id;
  final String descricao;
  final double valor;
  final String categoria;
  final DateTime data;

  Gasto({
    this.id,
    required this.descricao,
    required this.valor,
    required this.categoria,
    required this.data,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'descricao': descricao,
        'valor': valor,
        'categoria': categoria,
        'data': data.toIso8601String(),
      };

  factory Gasto.fromMap(Map<String, Object?> m) => Gasto(
        id: m['id'] as int?,
        descricao: m['descricao'] as String,
        valor: (m['valor'] as num).toDouble(),
        categoria: m['categoria'] as String,
        data: DateTime.parse(m['data'] as String),
      );
}

// ---------------------------------------------------------------------------
// Banco de dados local (SQLite)
// ---------------------------------------------------------------------------

class Banco {
  Banco._();
  static final Banco instancia = Banco._();

  Database? _db;

  Future<Database> get db async => _db ??= await _abrir();

  Future<Database> _abrir() async {
    final caminho = join(await getDatabasesPath(), 'gastos.db');
    return openDatabase(
      caminho,
      version: 1,
      onCreate: (db, versao) => db.execute('''
        CREATE TABLE gastos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          descricao TEXT NOT NULL,
          valor REAL NOT NULL,
          categoria TEXT NOT NULL,
          data TEXT NOT NULL
        )
      '''),
    );
  }

  Future<List<Gasto>> doMes(DateTime mes) async {
    final inicio = DateTime(mes.year, mes.month);
    final fim = DateTime(mes.year, mes.month + 1);
    final linhas = await (await db).query(
      'gastos',
      where: 'data >= ? AND data < ?',
      whereArgs: [inicio.toIso8601String(), fim.toIso8601String()],
      orderBy: 'data DESC, id DESC',
    );
    return linhas.map(Gasto.fromMap).toList();
  }

  Future<int> inserir(Gasto g) async => (await db).insert('gastos', g.toMap());

  Future<void> atualizar(Gasto g) async => (await db)
      .update('gastos', g.toMap(), where: 'id = ?', whereArgs: [g.id]);

  Future<void> excluir(int id) async =>
      (await db).delete('gastos', where: 'id = ?', whereArgs: [id]);
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  runApp(const MeusGastosApp());
}

class MeusGastosApp extends StatelessWidget {
  const MeusGastosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meus Gastos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Tela principal: mês, resumo e lista
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime mes = DateTime(DateTime.now().year, DateTime.now().month);
  List<Gasto> gastos = [];
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    final lista = await Banco.instancia.doMes(mes);
    if (!mounted) return;
    setState(() {
      gastos = lista;
      carregando = false;
    });
  }

  void mudarMes(int delta) {
    setState(() => mes = DateTime(mes.year, mes.month + delta));
    carregar();
  }

  Future<void> abrirFormulario([Gasto? gasto]) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FormularioPage(gasto: gasto)),
    );
    if (salvou == true) carregar();
  }

  Future<void> excluir(Gasto g) async {
    await Banco.instancia.excluir(g.id!);
    await carregar();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Gasto excluído'),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () async {
              await Banco.instancia.inserir(Gasto(
                descricao: g.descricao,
                valor: g.valor,
                categoria: g.categoria,
                data: g.data,
              ));
              carregar();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = toBeginningOfSentenceCase(
        DateFormat('MMMM yyyy', 'pt_BR').format(mes))!;
    final total = gastos.fold<double>(0, (soma, g) => soma + g.valor);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Mês anterior',
              onPressed: () => mudarMes(-1),
            ),
            Text(titulo),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Próximo mês',
              onPressed: () => mudarMes(1),
            ),
          ],
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Novo gasto'),
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                ResumoCard(gastos: gastos, total: total),
                const SizedBox(height: 8),
                if (gastos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        'Nenhum gasto neste mês.\nToque em "Novo gasto" para começar.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ...gastos.map(
                  (g) => Dismissible(
                    key: ValueKey(g.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red.shade400,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => excluir(g),
                    child: ListTile(
                      onTap: () => abrirFormulario(g),
                      leading: CircleAvatar(
                        child: Text(g.categoria[0]),
                      ),
                      title: Text(g.descricao),
                      subtitle: Text(
                        '${g.categoria} • ${DateFormat('dd/MM', 'pt_BR').format(g.data)}',
                      ),
                      trailing: Text(
                        moeda.format(g.valor),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cartão de resumo: total do mês e barras por categoria
// ---------------------------------------------------------------------------

class ResumoCard extends StatelessWidget {
  final List<Gasto> gastos;
  final double total;

  const ResumoCard({super.key, required this.gastos, required this.total});

  @override
  Widget build(BuildContext context) {
    final porCategoria = <String, double>{};
    for (final g in gastos) {
      porCategoria[g.categoria] = (porCategoria[g.categoria] ?? 0) + g.valor;
    }
    final ordenadas = porCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total do mês',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              moeda.format(total),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (ordenadas.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...ordenadas.map((e) {
                final fracao = total == 0 ? 0.0 : e.value / total;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key),
                          Text(
                              '${moeda.format(e.value)}  (${(fracao * 100).toStringAsFixed(0)}%)'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fracao,
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formulário: adicionar / editar
// ---------------------------------------------------------------------------

class FormularioPage extends StatefulWidget {
  final Gasto? gasto;

  const FormularioPage({super.key, this.gasto});

  @override
  State<FormularioPage> createState() => _FormularioPageState();
}

class _FormularioPageState extends State<FormularioPage> {
  final _chave = GlobalKey<FormState>();
  late final TextEditingController _descricao;
  late final TextEditingController _valor;
  late String _categoria;
  late DateTime _data;

  bool get editando => widget.gasto != null;

  @override
  void initState() {
    super.initState();
    final g = widget.gasto;
    _descricao = TextEditingController(text: g?.descricao ?? '');
    _valor = TextEditingController(
      text: g == null ? '' : g.valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    _categoria = g?.categoria ?? categorias.first;
    _data = g?.data ?? DateTime.now();
  }

  @override
  void dispose() {
    _descricao.dispose();
    _valor.dispose();
    super.dispose();
  }

  Future<void> escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (escolhida != null) setState(() => _data = escolhida);
  }

  Future<void> salvar() async {
    if (!_chave.currentState!.validate()) return;
    final valor = double.parse(_valor.text.trim().replaceAll(',', '.'));
    final gasto = Gasto(
      id: widget.gasto?.id,
      descricao: _descricao.text.trim(),
      valor: valor,
      categoria: _categoria,
      data: _data,
    );
    if (editando) {
      await Banco.instancia.atualizar(gasto);
    } else {
      await Banco.instancia.inserir(gasto);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(editando ? 'Editar gasto' : 'Novo gasto')),
      body: Form(
        key: _chave,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _descricao,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Informe uma descrição'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _valor,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                if (n == null || n <= 0) return 'Informe um valor válido';
                return null;
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: escolherData,
              icon: const Icon(Icons.calendar_today),
              label: Text(DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR')
                  .format(_data)),
            ),
            const SizedBox(height: 24),
            Text('Categoria', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categorias
                  .map((c) => ChoiceChip(
                        label: Text(c),
                        selected: _categoria == c,
                        onSelected: (_) => setState(() => _categoria = c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: salvar,
              icon: const Icon(Icons.check),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
