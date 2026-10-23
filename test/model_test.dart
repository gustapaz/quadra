import 'package:flutter_test/flutter_test.dart';
import 'package:quadra/model.dart';

void main() {
  test('pistas agrupam blocos e representam linhas vazias', () {
    expect(clues([false, false]), [0]);
    expect(clues([true, true, false, true]), [2, 1]);
  });
  test('todos os desafios têm tamanho correto e solução única', () {
    for (final p in puzzles) {
      expect(p.pattern.every((r) => r.length == p.n), isTrue, reason: p.id);
      expect(solutionCount(p), 1, reason: p.id);
    }
  });
  test('desfazer e refazer preservam jogadas sem alterar a solução', () {
    final g = Game(puzzles.first);
    g.setCell(1, 1);
    expect(g.cells[1], 1);
    g.undo();
    expect(g.cells[1], 0);
    g.redo();
    expect(g.cells[1], 1);
    g.setCell(2, 2);
    expect(g.canRedo, isFalse);
  });
  test('dica corrige célula e conclusão não exige X nos vazios', () {
    final g = Game(puzzles.first);
    g.setCell(0, 1);
    expect(g.mistakes, [0]);
    g.hint();
    expect(g.cells[0], 2);
    while (!g.complete) {
      g.hint();
    }
    expect(g.progress, 1);
    expect(g.mistakes, isEmpty);
  });
  test('pausa bloqueia jogadas e restauração recusa corrupção', () {
    final g = Game(puzzles.first)..paused = true;
    g.setCell(1, 1);
    expect(g.filled, 0);
    expect(
      Game.restore(puzzles.first, {
        'cells': [9],
      }).filled,
      0,
    );
    final h = Game(puzzles.first)..setCell(1, 1);
    expect(Game.restore(puzzles.first, h.toJson()).cells, h.cells);
  });
  test('desafio do dia é estável dentro da mesma data', () {
    expect(
      dailyPuzzle(DateTime(2026, 10, 22, 1)).id,
      dailyPuzzle(DateTime(2026, 10, 22, 23)).id,
    );
  });
}
