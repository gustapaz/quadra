import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model.dart';

const blue = Color(0xff2448db),
    ink = Color(0xff192848),
    paper = Color(0xfffaf8f0),
    orange = Color(0xffff8a52),
    mint = Color(0xffd7edbe);
late final SemanticsHandle semanticsHandle;
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  semanticsHandle = SemanticsBinding.instance.ensureSemantics();
  runApp(const QuadraApp());
}

class QuadraApp extends StatelessWidget {
  const QuadraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Quadra — um quadrado de cada vez',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        primary: blue,
        surface: paper,
      ),
      scaffoldBackgroundColor: blue,
      focusColor: orange,
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    home: const Studio(),
  );
}

class Studio extends StatefulWidget {
  const Studio({super.key});
  @override
  State<Studio> createState() => _StudioState();
}

class _StudioState extends State<Studio> with WidgetsBindingObserver {
  final games = {for (final p in puzzles) p.id: Game(p)};
  final completed = <String>{};
  final best = <String, int>{};
  final nodes = List.generate(81, (_) => FocusNode());
  String active = puzzles.first.id, filter = 'Todos';
  int tab = 0, mode = 1, cursor = 0;
  bool ready = false, announced = false, storageError = false;
  Set<int> errors = {};
  Timer? timer;
  SharedPreferences? prefs;
  Game get game => games[active]!;
  Puzzle get puzzle => game.puzzle;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ready && tab == 0 && !game.paused && !game.complete && game.started) {
        setState(() => game.seconds++);
        if (game.seconds % 5 == 0) _save();
      }
    });
  }

  @override
  void dispose() {
    _save();
    timer?.cancel();
    for (final node in nodes) {
      node.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && ready) {
      setState(() => game.paused = true);
      _save();
    }
  }

  Future<void> _load() async {
    try {
      prefs = await SharedPreferences.getInstance();
      final text = prefs!.getString('quadra-progress');
      if (text != null) {
        final data = jsonDecode(text);
        if (data is Map && data['version'] == 1) {
          for (final p in puzzles) {
            games[p.id] = Game.restore(p, data['games']?[p.id]);
          }
          final list = data['completed'];
          if (list is List) {
            completed.addAll(list.whereType<String>().where(games.containsKey));
          }
          if (data['best'] is Map) {
            for (final entry in (data['best'] as Map).entries) {
              if (games.containsKey(entry.key) &&
                  entry.value is int &&
                  entry.value >= 0) {
                best[entry.key] = entry.value;
              }
            }
          }
          if (games.containsKey(data['active'])) active = data['active'];
        }
      }
    } catch (_) {
      storageError = true;
    }
    if (mounted) setState(() => ready = true);
  }

  Future<void> _save() async {
    if (!ready) return;
    try {
      final ok = await prefs?.setString(
        'quadra-progress',
        jsonEncode({
          'version': 1,
          'games': games.map((k, v) => MapEntry(k, v.toJson())),
          'completed': completed.toList(),
          'best': best,
          'active': active,
        }),
      );
      if (ok != true && mounted) setState(() => storageError = true);
    } catch (_) {
      if (mounted) setState(() => storageError = true);
    }
  }

  void toast(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void choose(Puzzle p) {
    _save();
    setState(() {
      active = p.id;
      tab = 0;
      game.paused = false;
      errors = {};
      cursor = 0;
      announced = game.complete;
    });
    _save();
  }

  Future<void> openPuzzle(Puzzle p) async {
    if (games[p.id]!.complete) {
      if (!await confirm(
        'Jogar ${p.name} novamente?',
        'Uma nova tentativa começa do zero. Seu melhor tempo e a conquista continuam salvos.',
        'Novo jogo',
      )) {
        return;
      }
      games[p.id] = Game(p);
    }
    choose(p);
  }

  void move(int index, int value) {
    if (game.paused || game.complete) return;
    setState(() {
      game.setCell(index, value);
      errors = {};
      cursor = index;
    });
    _after();
  }

  void _after() {
    _save();
    if (game.complete && !announced) {
      announced = true;
      completed.add(active);
      best[active] = math.min(best[active] ?? game.seconds, game.seconds);
      _save();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _victory();
      });
    }
  }

  void _hint() {
    if (game.paused || game.complete) return;
    setState(() {
      game.hint();
      errors = {};
    });
    toast('Uma célula revelada. Continue seguindo as pistas.');
    _after();
  }

  void _check() {
    setState(() {
      game.checks++;
      errors = game.mistakes.toSet();
    });
    toast(
      errors.isEmpty
          ? 'Suas células pintadas estão certas. Continue!'
          : 'Há ${errors.length} célula(s) pintada(s) fora do desenho. Elas estão destacadas.',
    );
    _save();
  }

  void _undo() {
    setState(() {
      game.undo();
      errors = {};
      announced = game.complete;
    });
    _save();
  }

  void _redo() {
    setState(() {
      game.redo();
      errors = {};
    });
    _after();
  }

  String clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  Future<void> reset() async {
    if (await confirm(
      'Recomeçar este desenho?',
      'As jogadas e o tempo desta tentativa serão apagados. Conquistas anteriores continuam no seu progresso.',
      'Recomeçar',
    )) {
      setState(() {
        games[active] = Game(puzzle);
        errors = {};
        announced = false;
      });
      _save();
    }
  }

  Future<bool> confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontFamily: 'RobotoCondensed', fontSize: 28),
          ),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  void help() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Lógica, não adivinhação.',
          style: TextStyle(fontFamily: 'RobotoCondensed', fontSize: 31),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Os números nas bordas mostram os blocos de quadrados pintados em cada linha e coluna. A ordem importa.',
                  style: TextStyle(height: 1.6),
                ),
                const SizedBox(height: 20),
                _rule(
                  '1',
                  'Leia os blocos',
                  'Uma pista 2 1 significa: dois pintados, pelo menos um vazio, depois um pintado.',
                ),
                _example(),
                _rule(
                  '2',
                  'Cruze os vazios',
                  'Use o modo X para marcar onde não há desenho. Não é obrigatório cruzar todos os vazios para concluir.',
                ),
                _rule(
                  '3',
                  'Encontre o desenho',
                  'Combine linhas e colunas. Uma pista fica verde quando seus blocos correspondem ao tabuleiro. Isso não garante que aquela linha esteja na posição final correta.',
                ),
                _rule(
                  '4',
                  'Use o teclado',
                  'Tab entra nas células. Setas navegam. Espaço ou Enter joga no modo atual. X marca vazio. Ctrl+Z desfaz; Ctrl+Y refaz.',
                ),
                const Text(
                  'Toque longo ou botão direito também marca X. Dicas revelam uma célula; verificar destaca preenchimentos incorretos. Não há penalidade nem dados enviados à nuvem.',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Entendi, vamos jogar'),
          ),
        ],
      ),
    );
  }

  Widget _rule(String n, String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(n, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(text, style: const TextStyle(fontSize: 13, height: 1.6)),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _example() => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('2  1  →  ', style: TextStyle(fontWeight: FontWeight.bold)),
        ...List.generate(
          5,
          (i) => Container(
            margin: const EdgeInsets.all(2),
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: [0, 1, 3].contains(i) ? blue : const Color(0xffe5e9ed),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              i == 2 || i == 4 ? '×' : '',
              style: const TextStyle(color: ink),
            ),
          ),
        ),
      ],
    ),
  );
  void _victory() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(
          'Você juntou as peças!',
          style: TextStyle(fontFamily: 'RobotoCondensed', fontSize: 33),
        ),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _mini(puzzle, 100),
              const SizedBox(height: 20),
              Text(
                puzzle.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${clock(game.seconds)} de jogo · ${game.hints} dica(s)',
                style: const TextStyle(color: Color(0xff667086)),
              ),
              const SizedBox(height: 10),
              const Text(
                'Mais um desenho descoberto, no seu ritmo.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Ficar aqui'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              final next = puzzles.firstWhere(
                (p) => !completed.contains(p.id),
                orElse: () => puzzles.first,
              );
              choose(next);
            },
            child: const Text('Próximo desafio'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1000;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(wide),
            Expanded(
              child: !ready
                  ? const Center(child: CircularProgressIndicator(color: paper))
                  : SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 45 : 12,
                        24,
                        wide ? 45 : 12,
                        30,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1320),
                          child: Column(
                            children: [
                              if (storageError)
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  margin: const EdgeInsets.only(bottom: 20),
                                  color: orange,
                                  child: const Text(
                                    'O armazenamento deste navegador não está disponível. Seu progresso pode não ser recuperado ao fechar a página.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              if (tab == 0)
                                _play(wide)
                              else if (tab == 1)
                                _collection()
                              else
                                _progress(),
                              const SizedBox(height: 30),
                              Text(
                                'SEM PRESSA. SEM CONTA. SÓ MAIS UM QUADRADO.',
                                style: TextStyle(
                                  color: paper.withValues(alpha: .75),
                                  fontSize: 9,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Um jogo de Gustavo Paz · dados apenas neste navegador',
                                style: TextStyle(
                                  color: paper.withValues(alpha: .7),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool wide) => Container(
    padding: EdgeInsets.symmetric(horizontal: wide ? 45 : 16, vertical: 18),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xff5570e7))),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final small = constraints.maxWidth < 650;
        final brand = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _logo(),
            const SizedBox(width: 12),
            const Text(
              'quadra.',
              style: TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.w700,
                fontSize: 37,
                color: paper,
                letterSpacing: -1.5,
              ),
            ),
          ],
        );
        final nav = Wrap(
          spacing: small ? 5 : 16,
          children: [
            for (var i = 0; i < 3; i++)
              TextButton(
                onPressed: () {
                  _save();
                  setState(() => tab = i);
                },
                style: TextButton.styleFrom(
                  foregroundColor: tab == i ? ink : paper,
                  backgroundColor: tab == i ? paper : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                ),
                child: Text(
                  ['Jogar', 'Desafios', 'Meu progresso'][i],
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        );
        final question = IconButton(
          onPressed: help,
          tooltip: 'Como jogar',
          style: IconButton.styleFrom(
            foregroundColor: paper,
            side: const BorderSide(color: Color(0xff8195f0)),
          ),
          icon: const Icon(Icons.question_mark, size: 18),
        );
        return small
            ? Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(fit: BoxFit.scaleDown, child: brand),
                        ),
                      ),
                      question,
                    ],
                  ),
                  const SizedBox(height: 18),
                  nav,
                ],
              )
            : Row(
                children: [
                  brand,
                  const Spacer(),
                  nav,
                  const SizedBox(width: 25),
                  question,
                ],
              );
      },
    ),
  );
  Widget _logo() => SizedBox(
    width: 32,
    height: 32,
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(
        4,
        (i) => Transform.rotate(
          angle: i == 3 ? 0.18 : 0,
          child: Container(
            width: 14,
            height: 14,
            color: i == 3 ? orange : paper,
          ),
        ),
      ),
    ),
  );
  Widget _play(bool wide) {
    final board = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: _paper(),
    );
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 50, right: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'UM JOGO DE\nPEQUENAS DESCOBERTAS',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: paper,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'PENSE\nFORA.\nPINTE\nDENTRO.',
                        style: TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.bold,
                          fontSize: 56,
                          height: .96,
                          letterSpacing: -2,
                          color: paper,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'Um pouco de lógica.\nUm quadrado de cada vez.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.7,
                          color: Color(0xffd4dcff),
                        ),
                      ),
                      const SizedBox(height: 35),
                      Transform.rotate(
                        angle: -.08,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          color: orange,
                          child: const Text(
                            'NÃO É SORTE.\nÉ SEU JEITO DE VER.',
                            style: TextStyle(
                              fontFamily: 'RobotoCondensed',
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              height: 1.2,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(flex: 3, child: board),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 32, top: 55),
                  child: _side(),
                ),
              ),
            ],
          )
        : Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'UM QUADRADO\nDE CADA VEZ.',
                    style: TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontWeight: FontWeight.bold,
                      fontSize: 29,
                      height: .98,
                      color: paper,
                    ),
                  ),
                  Text(
                    '${completed.length.toString().padLeft(2, '0')} / 08\nDESCOBERTOS',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 10,
                      color: paper,
                      height: 1.7,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              board,
              const SizedBox(height: 22),
              TextButton(
                onPressed: help,
                style: TextButton.styleFrom(foregroundColor: paper),
                child: const Text('Primeira vez? Veja como jogar →'),
              ),
            ],
          );
  }

  Widget _side() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'SEU PERCURSO',
        style: TextStyle(
          color: Color(0xffc8d3ff),
          fontSize: 9,
          letterSpacing: 1.8,
        ),
      ),
      const SizedBox(height: 18),
      Text(
        '${completed.length.toString().padLeft(2, '0')}/08',
        style: const TextStyle(
          fontFamily: 'RobotoCondensed',
          fontSize: 43,
          color: paper,
          fontWeight: FontWeight.bold,
        ),
      ),
      const Text(
        'desenhos descobertos',
        style: TextStyle(color: Color(0xffc8d3ff), fontSize: 11),
      ),
      const SizedBox(height: 30),
      const Divider(color: Color(0xff6881eb)),
      const SizedBox(height: 20),
      const Text(
        'COMO LER\nUMA PISTA',
        style: TextStyle(
          fontFamily: 'RobotoCondensed',
          fontWeight: FontWeight.bold,
          fontSize: 22,
          color: paper,
          height: 1.1,
        ),
      ),
      const SizedBox(height: 15),
      const Text(
        '2  1',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: orange,
          letterSpacing: 8,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Dois pintados.\nUm intervalo vazio.\nMais um pintado.',
        style: TextStyle(color: Color(0xffd4dcff), fontSize: 12, height: 1.9),
      ),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: help,
        style: OutlinedButton.styleFrom(
          foregroundColor: paper,
          side: const BorderSide(color: Color(0xff8195f0)),
        ),
        child: const Text('Aprender a jogar'),
      ),
    ],
  );
  Widget _paper() => Container(
    decoration: BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(15),
      boxShadow: const [
        BoxShadow(color: Color(0xff17319a), offset: Offset(8, 10)),
      ],
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: mint,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${puzzle.n} × ${puzzle.n}  /  ${puzzle.difficulty.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: .6,
                ),
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.timer_outlined,
              size: 16,
              color: Color(0xff68748a),
            ),
            const SizedBox(width: 7),
            Text(
              clock(game.seconds),
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              onPressed: game.complete
                  ? null
                  : () {
                      setState(() => game.paused = !game.paused);
                      _save();
                    },
              tooltip: game.paused ? 'Continuar jogo' : 'Pausar jogo',
              icon: Icon(
                game.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 20,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    puzzle.name,
                    style: const TextStyle(
                      fontFamily: 'RobotoCondensed',
                      fontWeight: FontWeight.w700,
                      fontSize: 29,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    puzzle.subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xff667086),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                setState(() => tab = 1);
              },
              tooltip: 'Trocar desafio',
              icon: const Icon(Icons.apps_rounded, color: blue),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (game.paused) _paused() else _board(),
        const SizedBox(height: 20),
        if (game.complete)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: mint,
            child: const Text(
              'DESENHO DESCOBERTO! ✓',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          )
        else
          _modes(),
        const SizedBox(height: 16),
        const Divider(height: 1, color: Color(0xffdadddf)),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            _tool(
              'Desfazer',
              Icons.undo_rounded,
              game.canUndo && !game.paused ? _undo : null,
            ),
            _tool(
              'Refazer',
              Icons.redo_rounded,
              game.canRedo && !game.paused ? _redo : null,
            ),
            _tool(
              'Dica',
              Icons.lightbulb_outline,
              !game.complete && !game.paused ? _hint : null,
            ),
            _tool(
              'Verificar',
              Icons.fact_check_outlined,
              !game.complete && !game.paused ? _check : null,
            ),
            _tool('Recomeçar', Icons.refresh_rounded, reset),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${game.filled} pintados  ·  ${game.hints} dicas usadas',
          style: const TextStyle(fontSize: 9, color: Color(0xff6b7487)),
        ),
      ],
    ),
  );
  Widget _tool(String label, IconData icon, VoidCallback? action) => TextButton(
    onPressed: action,
    style: TextButton.styleFrom(
      minimumSize: const Size(45, 45),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 9)),
      ],
    ),
  );
  Widget _modes() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final value in [1, 2])
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Semantics(
            selected: mode == value,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => mode = value);
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: mode == value ? blue : paper,
                foregroundColor: mode == value ? Colors.white : ink,
                side: BorderSide(
                  color: mode == value ? blue : const Color(0xffcbd0d9),
                ),
                minimumSize: const Size(105, 44),
              ),
              icon: Icon(
                value == 1 ? Icons.square_rounded : Icons.close,
                size: 16,
              ),
              label: Text(
                value == 1 ? 'Pintar' : 'Marcar X',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
    ],
  );
  Widget _paused() => SizedBox(
    height: 320,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pause_circle_outline, color: blue, size: 50),
          const SizedBox(height: 15),
          const Text(
            'A pausa também faz parte.',
            style: TextStyle(
              fontFamily: 'RobotoCondensed',
              fontWeight: FontWeight.bold,
              fontSize: 25,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => setState(() => game.paused = false),
            child: const Text('Voltar ao tabuleiro'),
          ),
        ],
      ),
    ),
  );
  Widget _board() => LayoutBuilder(
    builder: (context, constraints) {
      final n = puzzle.n;
      final cell = math.min(
        n == 5 ? 64.0 : 48.0,
        (constraints.maxWidth - 44) / n,
      );
      final top = math.max(
        55.0,
        puzzle.columns.map((c) => c.length).reduce(math.max) * 14.0 + 14,
      );
      return Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          final ctrl =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          if (ctrl && key == LogicalKeyboardKey.keyZ) {
            _undo();
            return KeyEventResult.handled;
          }
          if (ctrl && key == LogicalKeyboardKey.keyY) {
            _redo();
            return KeyEventResult.handled;
          }
          var next = cursor;
          if (key == LogicalKeyboardKey.arrowRight) {
            next = (cursor + 1).clamp(0, n * n - 1);
          } else if (key == LogicalKeyboardKey.arrowLeft) {
            next = (cursor - 1).clamp(0, n * n - 1);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            next = (cursor + n).clamp(0, n * n - 1);
          } else if (key == LogicalKeyboardKey.arrowUp) {
            next = (cursor - n).clamp(0, n * n - 1);
          } else if (key == LogicalKeyboardKey.keyX) {
            move(cursor, 2);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.enter) {
            move(cursor, mode);
            return KeyEventResult.handled;
          } else {
            return KeyEventResult.ignored;
          }
          nodes[next].requestFocus();
          return KeyEventResult.handled;
        },
        child: Center(
          child: SizedBox(
            width: 44 + n * cell,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 44,
                      height: top,
                      child: const Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            '↓ →',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff8a96aa),
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (var c = 0; c < n; c++)
                      SizedBox(
                        width: cell,
                        height: top,
                        child: Semantics(
                          label:
                              'Coluna ${c + 1}, pistas ${puzzle.columns[c].join(', ')}',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              for (final clue in puzzle.columns[c])
                                Text(
                                  '$clue',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    height: 1.25,
                                    color: game.lineDone(c, true)
                                        ? const Color(0xff49723b)
                                        : ink,
                                  ),
                                ),
                              const SizedBox(height: 9),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                for (var r = 0; r < n; r++)
                  Row(
                    children: [
                      SizedBox(
                        width: 44,
                        height: cell,
                        child: Center(
                          child: Semantics(
                            label:
                                'Linha ${r + 1}, pistas ${puzzle.rows[r].join(', ')}',
                            child: Text(
                              puzzle.rows[r].join(' '),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: game.lineDone(r, false)
                                    ? const Color(0xff49723b)
                                    : ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (var c = 0; c < n; c++) _cell(r * n + c, cell),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _cell(int i, double size) {
    final value = game.cells[i], wrong = errors.contains(i), n = puzzle.n;
    return Semantics(
      label:
          'Linha ${i ~/ n + 1}, coluna ${i % n + 1}: ${value == 1
              ? 'pintada'
              : value == 2
              ? 'marcada com X'
              : 'vazia'}',
      button: true,
      focusable: true,
      focused: nodes[i].hasFocus,
      onDidGainAccessibilityFocus: () => nodes[i].requestFocus(),
      enabled: !game.complete,
      onTap: () {
        nodes[i].requestFocus();
        move(i, mode);
      },
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Padding(
            padding: const EdgeInsets.all(1.5),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                focusNode: nodes[i],
                onFocusChange: (focused) {
                  if (focused && mounted) setState(() => cursor = i);
                },
                onTap: () {
                  nodes[i].requestFocus();
                  move(i, mode);
                },
                onSecondaryTap: () => move(i, 2),
                onLongPress: () => move(i, 2),
                borderRadius: BorderRadius.circular(4),
                focusColor: orange,
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 100),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: wrong
                        ? const Color(0xffffcfb8)
                        : value == 1
                        ? blue
                        : const Color(0xffe9edf1),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: nodes[i].hasFocus
                          ? orange
                          : wrong
                          ? const Color(0xffb64221)
                          : const Color(0xffdbe0e7),
                      width: nodes[i].hasFocus ? 2 : 1,
                    ),
                  ),
                  child: value == 2
                      ? const Icon(
                          Icons.close,
                          size: 17,
                          color: Color(0xff8390a5),
                        )
                      : wrong
                      ? const Icon(
                          Icons.priority_high,
                          size: 17,
                          color: Color(0xffa53319),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mini(Puzzle p, double width, {bool reveal = true}) => SizedBox(
    width: width,
    height: width,
    child: Column(
      children: [
        for (var r = 0; r < p.n; r++)
          Expanded(
            child: Row(
              children: [
                for (var c = 0; c < p.n; c++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(.8),
                      decoration: BoxDecoration(
                        color: reveal
                            ? (p.pattern[r][c] == '#'
                                  ? blue
                                  : const Color(0xffe0e5eb))
                            : ((r + c) % 3 == 0
                                  ? const Color(0xffaebdea)
                                  : const Color(0xffdce2ee)),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _collection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(
        'ESCOLHA SEU PRÓXIMO ENCONTRO',
        'OITO JEITOS\nDE DESCOBRIR.',
      ),
      const SizedBox(height: 25),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in ['Todos', 'Leve', 'Médio', 'Intenso'])
            ChoiceChip(
              label: Text(value),
              selected: filter == value,
              onSelected: (_) => setState(() => filter = value),
              selectedColor: orange,
              backgroundColor: paper,
              labelStyle: const TextStyle(color: ink, fontSize: 12),
            ),
        ],
      ),
      const SizedBox(height: 25),
      LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 1050
              ? 4
              : c.maxWidth > 650
              ? 3
              : 2;
          final w = (c.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(
            spacing: 16,
            runSpacing: 18,
            children: [
              for (final p in puzzles.where(
                (p) => filter == 'Todos' || p.difficulty == filter,
              ))
                SizedBox(width: w, child: _puzzleTile(p, w)),
            ],
          );
        },
      ),
      const SizedBox(height: 25),
      OutlinedButton.icon(
        onPressed: () => choose(dailyPuzzle(DateTime.now())),
        style: OutlinedButton.styleFrom(
          foregroundColor: paper,
          side: const BorderSide(color: Color(0xff9fb0f6)),
        ),
        icon: const Icon(Icons.today, size: 18),
        label: const Text('Escolher o desafio do dia'),
      ),
    ],
  );
  Widget _puzzleTile(Puzzle p, double width) => Material(
    color: paper,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: () => openPuzzle(p),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${p.n} × ${p.n}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xff637087),
                  ),
                ),
                const Spacer(),
                if (completed.contains(p.id))
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xff51733d),
                    size: 18,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: _mini(
                p,
                math.min(width - 40, 120),
                reveal: completed.contains(p.id),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              completed.contains(p.id)
                  ? p.name
                  : 'Desenho ${puzzles.indexOf(p) + 1}',
              style: const TextStyle(
                fontFamily: 'RobotoCondensed',
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              p.difficulty,
              style: const TextStyle(fontSize: 10, color: Color(0xff637087)),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: Text(
                    completed.contains(p.id)
                        ? 'Jogar de novo'
                        : games[p.id]!.started
                        ? 'Continuar'
                        : 'Começar',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: blue,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 17, color: blue),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  Widget _sectionTitle(String eyebrow, String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          color: Color(0xffd0daff),
          fontSize: 10,
          letterSpacing: 1.4,
        ),
      ),
      const SizedBox(height: 17),
      Text(
        title,
        style: const TextStyle(
          fontFamily: 'RobotoCondensed',
          fontWeight: FontWeight.bold,
          fontSize: 48,
          height: .97,
          color: paper,
          letterSpacing: -1.5,
        ),
      ),
    ],
  );
  Widget _progress() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('CADA DESCOBERTA CONTA', 'SEU RITMO.\nSUAS CONQUISTAS.'),
      const SizedBox(height: 30),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: mint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
          spacing: 50,
          runSpacing: 25,
          children: [
            _stat('${completed.length}/8', 'desenhos descobertos'),
            _stat(
              '${games.values.where((g) => g.started && !g.complete).length}',
              'em andamento',
            ),
            _stat(
              clock(games.values.fold(0, (t, g) => t + g.seconds)),
              'tempo nas tentativas atuais',
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      if (completed.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(30),
          color: paper,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sua primeira descoberta espera por você.',
                style: TextStyle(
                  fontFamily: 'RobotoCondensed',
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Conclua um desafio para revelar seu desenho e registrar o melhor tempo.',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => setState(() => tab = 0),
                child: const Text('Voltar ao jogo'),
              ),
            ],
          ),
        )
      else ...[
        for (final p in puzzles.where((p) => completed.contains(p.id)))
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            color: paper,
            child: Row(
              children: [
                _mini(p, 60),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontFamily: 'RobotoCondensed',
                          fontWeight: FontWeight.bold,
                          fontSize: 25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Melhor tempo: ${clock(best[p.id] ?? 0)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff647188),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => openPuzzle(p),
                  tooltip: 'Jogar ${p.name} novamente',
                  icon: const Icon(Icons.arrow_forward, color: blue),
                ),
              ],
            ),
          ),
      ],
      const SizedBox(height: 25),
      const Text(
        'Seu progresso fica apenas neste navegador. Não há conta, nuvem ou ranking real. O desafio do dia é escolhido localmente entre os oito desenhos.',
        style: TextStyle(color: Color(0xffd0daff), fontSize: 12, height: 1.8),
      ),
      const SizedBox(height: 20),
      TextButton(
        onPressed: () async {
          if (await confirm(
            'Apagar todo o progresso?',
            'Isso remove as tentativas, tempos e desenhos descobertos deste navegador.',
            'Apagar progresso',
          )) {
            setState(() {
              completed.clear();
              best.clear();
              for (final p in puzzles) {
                games[p.id] = Game(p);
              }
              announced = false;
              errors = {};
            });
            _save();
            toast('Progresso apagado. Um novo começo.');
          }
        },
        style: TextButton.styleFrom(foregroundColor: paper),
        child: const Text('Apagar meu progresso local'),
      ),
    ],
  );
  Widget _stat(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'RobotoCondensed',
          fontWeight: FontWeight.bold,
          fontSize: 40,
        ),
      ),
      const SizedBox(height: 5),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}
