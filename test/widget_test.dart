import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quadra/main.dart';
import 'package:quadra/model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'RobotoCondensed': 'robotocondensed-bold.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await loader.load();
    }
  });
  testWidgets('tabuleiro e coleção cabem em mobile, tablet e desktop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [320.0, 390.0, 768.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpWidget(const QuadraApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');
      await tester.tap(find.text('Desafios'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Intenso'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desenho 8'));
      await tester.pumpAndSettle();
      expect(find.text('Bom caminho'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '9x9 at $width');
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('concluir um desenho registra a conquista no progresso', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const QuadraApp());
    await tester.pumpAndSettle();
    final p = puzzles.first;
    for (var i = 0; i < p.solution.length; i++) {
      if (p.solution[i]) {
        await tester.tap(
          find.bySemanticsLabel(
            'Linha ${i ~/ p.n + 1}, coluna ${i % p.n + 1}: vazia',
          ),
        );
        await tester.pumpAndSettle();
      }
    }
    expect(find.text('Você juntou as peças!'), findsOneWidget);
    await tester.tap(find.text('Ficar aqui'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meu progresso'));
    await tester.pumpAndSettle();
    expect(find.text('1/8'), findsOneWidget);
    expect(find.text('De coração'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });
}
