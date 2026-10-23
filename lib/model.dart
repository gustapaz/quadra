import 'dart:convert';

List<int> clues(Iterable<bool> cells) {
  final result = <int>[];
  var run = 0;
  for (final cell in cells) {
    if (cell) {
      run++;
    } else if (run > 0) {
      result.add(run);
      run = 0;
    }
  }
  if (run > 0) result.add(run);
  return result.isEmpty ? [0] : result;
}

bool same(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);

class Puzzle {
  final String id, name, subtitle;
  final List<String> pattern;
  const Puzzle(this.id, this.name, this.subtitle, this.pattern);
  int get n => pattern.length;
  List<bool> get solution =>
      pattern.join().split('').map((c) => c == '#').toList();
  List<List<int>> get rows =>
      pattern.map((r) => clues(r.split('').map((c) => c == '#'))).toList();
  List<List<int>> get columns => List.generate(
    n,
    (c) => clues(List.generate(n, (r) => pattern[r][c] == '#')),
  );
  String get difficulty => n == 5
      ? 'Leve'
      : n == 7
      ? 'Médio'
      : 'Intenso';
}

const puzzles = [
  Puzzle('coracao', 'De coração', 'Um pequeno gesto, quadrado por quadrado.', [
    '.##..',
    '####.',
    '####.',
    '.##..',
    '..#..',
  ]),
  Puzzle('casa', 'Porta aberta', 'Todo começo precisa de um lugar.', [
    '..#..',
    '.###.',
    '#####',
    '#.#.#',
    '#####',
  ]),
  Puzzle('cacto', 'Sem pressa', 'Crescer também é saber esperar.', [
    '..#..',
    '#.#..',
    '###.#',
    '..###',
    '..#..',
  ]),
  Puzzle('diamante', 'Brilho próprio', 'Encontre o que está escondido.', [
    '..#..',
    '.###.',
    '#####',
    '.###.',
    '..#..',
  ]),
  Puzzle('cafe', 'Mais um gole', 'Uma pausa com um desenho no fundo.', [
    '.......',
    '.####..',
    '.#####.',
    '.##..#.',
    '.#####.',
    '.####..',
    '#######',
  ]),
  Puzzle('foguete', 'Lá no alto', 'Uma ideia pronta para ganhar o céu.', [
    '...#...',
    '..###..',
    '..###..',
    '.#####.',
    '#######',
    '..#.#..',
    '..#.#..',
  ]),
  Puzzle('flor', 'Florescer', 'Há uma estação dentro de cada ideia.', [
    '..###..',
    '.#####.',
    '#######',
    '.#####.',
    '..###..',
    '...#...',
    '..###..',
  ]),
  Puzzle('farol', 'Bom caminho', 'Uma luz para o próximo passo.', [
    '....#....',
    '...###...',
    '..#####..',
    '...###...',
    '...###...',
    '..#####..',
    '..#####..',
    '.#######.',
    '#########',
  ]),
];
Puzzle dailyPuzzle(DateTime now) =>
    puzzles[DateTime.utc(
          now.year,
          now.month,
          now.day,
        ).difference(DateTime.utc(2026, 1, 1)).inDays.abs() %
        puzzles.length];

class Game {
  final Puzzle puzzle;
  List<int> cells;
  int seconds, checks, hints;
  bool paused = false;
  final List<List<int>> _undo = [], _redo = [];
  Game(
    this.puzzle, {
    List<int>? cells,
    this.seconds = 0,
    this.checks = 0,
    this.hints = 0,
  }) : cells = cells ?? List.filled(puzzle.n * puzzle.n, 0);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get started => cells.any((c) => c != 0) || seconds > 0;
  bool get complete => List.generate(
    cells.length,
    (i) => (cells[i] == 1) == puzzle.solution[i],
  ).every((v) => v);
  int get filled => cells.where((c) => c == 1).length;
  double get progress =>
      List.generate(
        cells.length,
        (i) => cells[i] == 1 && puzzle.solution[i] ? 1 : 0,
      ).fold(0, (a, b) => a + b) /
      puzzle.solution.where((v) => v).length;
  List<int> get mistakes => List.generate(
    cells.length,
    (i) => i,
  ).where((i) => cells[i] == 1 && !puzzle.solution[i]).toList();
  void setCell(int i, int mode) {
    if (paused || complete || i < 0 || i >= cells.length) return;
    _undo.add([...cells]);
    if (_undo.length > 150) _undo.removeAt(0);
    _redo.clear();
    cells[i] = cells[i] == mode ? 0 : mode;
  }

  void undo() {
    if (!canUndo) return;
    _redo.add([...cells]);
    cells = _undo.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add([...cells]);
    cells = _redo.removeLast();
  }

  int? hint() {
    if (complete || paused) return null;
    final i = List.generate(
      cells.length,
      (i) => i,
    ).where((i) => (cells[i] == 1) != puzzle.solution[i]).first;
    _undo.add([...cells]);
    _redo.clear();
    cells[i] = puzzle.solution[i] ? 1 : 2;
    hints++;
    return i;
  }

  bool lineDone(int index, bool column) {
    final line = List.generate(
      puzzle.n,
      (j) => cells[column ? j * puzzle.n + index : index * puzzle.n + j] == 1,
    );
    return same(
      clues(line),
      column ? puzzle.columns[index] : puzzle.rows[index],
    );
  }

  Map<String, dynamic> toJson() => {
    'cells': cells,
    'seconds': seconds,
    'checks': checks,
    'hints': hints,
  };
  static Game restore(Puzzle puzzle, dynamic value) {
    try {
      if (value is! Map || value['cells'] is! List) return Game(puzzle);
      final data = List<int>.from(value['cells']);
      if (data.length != puzzle.n * puzzle.n ||
          data.any((c) => c < 0 || c > 2)) {
        return Game(puzzle);
      }
      int number(String key) {
        final n = value[key];
        return n is int && n >= 0 && n < 10000000 ? n : 0;
      }

      return Game(
        puzzle,
        cells: data,
        seconds: number('seconds'),
        checks: number('checks'),
        hints: number('hints'),
      );
    } catch (_) {
      return Game(puzzle);
    }
  }
}

String encodeGames(Map<String, Game> games, Set<String> completed) =>
    jsonEncode({
      'version': 1,
      'games': games.map((key, value) => MapEntry(key, value.toJson())),
      'completed': completed.toList(),
    });
int solutionCount(Puzzle p, {int limit = 2}) {
  List<int> candidates(List<int> target) => List.generate(1 << p.n, (i) => i)
      .where(
        (mask) => same(
          clues(List.generate(p.n, (b) => (mask & (1 << b)) != 0)),
          target,
        ),
      )
      .toList();
  final rows = p.rows.map(candidates).toList(),
      cols = p.columns.map(candidates).toList(),
      values = List.filled(p.n, 0);
  var count = 0;
  void search(int r) {
    if (count >= limit) return;
    if (r == p.n) {
      count++;
      return;
    }
    for (final mask in rows[r]) {
      final prior = [...values];
      for (var c = 0; c < p.n; c++) {
        values[c] |= ((mask >> c) & 1) << r;
      }
      final prefix = (1 << (r + 1)) - 1;
      if (List.generate(
        p.n,
        (c) => cols[c].any((m) => (m & prefix) == values[c]),
      ).every((v) => v)) {
        search(r + 1);
      }
      for (var c = 0; c < p.n; c++) {
        values[c] = prior[c];
      }
    }
  }

  search(0);
  return count;
}
