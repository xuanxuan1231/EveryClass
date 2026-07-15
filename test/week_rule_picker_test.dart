import 'package:everyclass/models/week_rule.dart';
import 'package:everyclass/ui/schedule/week_rule_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WeekRule? result;

  Future<void> open(WidgetTester tester, WeekRule initial) async {
    result = null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                result = await showWeekRulePicker(context, initial: initial);
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
  }

  testWidgets('每周规则默认逐周网格；勾选结果规约成轮换', (tester) async {
    await open(tester, WeekRule.every);

    // 逐周网格可见（20 格），且全部选中。
    expect(find.widgetWithText(FilterChip, '20'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump();
    for (final w in ['1', '3', '5']) {
      await tester.tap(find.widgetWithText(FilterChip, w));
      await tester.pump();
    }
    await confirm(tester);

    expect(result, isNotNull);
    expect(result!.interval, 2);
    expect(result!.offsets, [0]);
    expect(result!.fromWeek, 1);
    expect(result!.toWeek, 5);
  });

  testWidgets('范围轮换：每 3 周中的第 1、2 周，不限结束周', (tester) async {
    await open(tester, WeekRule.every);

    await tester.tap(find.text('范围轮换'));
    await tester.pumpAndSettle();

    // 「每 N 周轮换」是最后一个步进器：+ 两次 → 每 3 周。
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();

    // 周期内默认第 1 周已选，补选第 2 周。
    await tester.tap(find.widgetWithText(FilterChip, '第 2 周'));
    await tester.pumpAndSettle();
    expect(find.textContaining('每 3 周中的第 1、2 周'), findsOneWidget);

    await confirm(tester);

    expect(result, isNotNull);
    expect(result!.interval, 3);
    expect(result!.offsets, [0, 1]);
    expect(result!.fromWeek, 1);
    expect(result!.toWeek, 0); // 未设结束周 → 不限
    expect(result!.matches(1), isTrue);
    expect(result!.matches(2), isTrue);
    expect(result!.matches(3), isFalse);
    expect(result!.matches(4), isTrue);
  });

  testWidgets('已有轮换规则默认范围模式并按周期序数回显', (tester) async {
    // 从第 2 周起每 3 周中的第 2、3 周（相位 2、0）。
    await open(
      tester,
      const WeekRule(interval: 3, offsets: [0, 2], fromWeek: 2, toWeek: 14),
    );

    // 默认落在范围模式：周期序数芯片可见，第 2、3 周选中。
    bool chipSelected(String label) => tester
        .widget<FilterChip>(find.widgetWithText(FilterChip, label))
        .selected;
    expect(chipSelected('第 1 周'), isFalse);
    expect(chipSelected('第 2 周'), isTrue);
    expect(chipSelected('第 3 周'), isTrue);

    // 原样确定：规则无损往返。
    await confirm(tester);
    expect(result!.interval, 3);
    expect(result!.offsets, [0, 2]);
    expect(result!.fromWeek, 2);
    expect(result!.toWeek, 14);
  });

  testWidgets('逐周编辑切到范围模式会携带当前选择', (tester) async {
    await open(tester, WeekRule.every);

    await tester.tap(find.text('清空'));
    await tester.pump();
    for (final w in ['1', '2', '3', '4']) {
      await tester.tap(find.widgetWithText(FilterChip, w));
      await tester.pump();
    }
    await tester.tap(find.text('范围轮换'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 1-4 周'), findsOneWidget);
    await confirm(tester);
    expect(result!.fromWeek, 1);
    expect(result!.toWeek, 4);
    expect(result!.interval, 1);
  });

  testWidgets('范围编辑切到逐周网格会展开命中周', (tester) async {
    await open(tester, WeekRule.every);

    await tester.tap(find.text('范围轮换'));
    await tester.pumpAndSettle();
    // 每 2 周轮换（默认第 1 周生效 → 单周）。
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('逐周选择'));
    await tester.pumpAndSettle();

    bool weekSelected(String label) => tester
        .widget<FilterChip>(find.widgetWithText(FilterChip, label))
        .selected;
    expect(weekSelected('1'), isTrue);
    expect(weekSelected('2'), isFalse);
    expect(weekSelected('19'), isTrue);
    expect(weekSelected('20'), isFalse);
  });

  testWidgets('逐周模式清空后不能确定', (tester) async {
    await open(tester, WeekRule.every);
    await tester.tap(find.text('清空'));
    await tester.pump();

    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确定'));
    expect(button.onPressed, isNull);
  });
}
