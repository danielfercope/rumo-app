import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/carteira/models/crm_models.dart';
import 'package:rumo_app/features/carteira/presentation/import_progress.dart';

SyncLog log(
        {int processadas = 0,
        int? estimado,
        DateTime? inicio,
        int falhas = 0}) =>
    SyncLog(
      tipo: 'carga_inicial',
      situacao: 'em_andamento',
      lidas: 0,
      novas: processadas,
      atualizadas: 0,
      falhas: falhas,
      iniciadaEm: inicio ?? DateTime(2026, 11, 13, 10),
      processadas: processadas,
      estimado: estimado,
    );

void main() {
  final inicio = DateTime(2026, 11, 13, 10);

  test('SyncLog lê o progresso do servidor', () {
    final l = SyncLog.fromJson({
      'tipo': 'carga_inicial',
      'situacao': 'em_andamento',
      'iniciada_em': '2026-11-13T10:00:00Z',
      'total_processadas': 230,
      'total_estimado': 502,
    });
    expect((l.processadas, l.estimado, l.emAndamento), (230, 502, true));
    expect(l.progresso, closeTo(0.458, 0.001));
  });

  test('sem estimativa (ou log antigo) não há percentual', () {
    final l = SyncLog.fromJson({
      'tipo': 'carga_inicial',
      'situacao': 'em_andamento',
      'iniciada_em': '2026-11-13T10:00:00Z',
    });
    expect((l.processadas, l.estimado, l.progresso), (0, null, null));
  });

  test('progresso nunca passa de 100%', () {
    expect(log(processadas: 600, estimado: 502).progresso, 1.0);
  });

  test('tempo restante projeta pelo ritmo da própria carga', () {
    // 100 empresas em 100 s → 1/s; faltam 402 → ~402 s
    final l = log(processadas: 100, estimado: 502, inicio: inicio);
    final restante = l.tempoRestante(inicio.add(const Duration(seconds: 100)));
    expect(restante!.inSeconds, closeTo(402, 1));
  });

  test('sem dados suficientes não chuta tempo', () {
    expect(
        log(processadas: 2, estimado: 500, inicio: inicio)
            .tempoRestante(inicio.add(const Duration(minutes: 1))),
        isNull);
    expect(
        log(processadas: 50, estimado: 500, inicio: inicio)
            .tempoRestante(inicio.add(const Duration(seconds: 2))),
        isNull);
    expect(
        log(processadas: 500, estimado: 500, inicio: inicio)
            .tempoRestante(inicio.add(const Duration(minutes: 9))),
        isNull);
  });

  test('linha de andamento em cada fase', () {
    final now = inicio.add(const Duration(seconds: 100));
    expect(importProgressLine(null, now), 'Preparando a importação…');
    expect(importProgressLine(log(), now), 'Preparando a importação…');
    expect(importProgressLine(log(estimado: 502, inicio: inicio), now),
        '0 de 502 empresas · iniciando…');
    expect(
        importProgressLine(
            log(processadas: 100, estimado: 502, inicio: inicio), now),
        '100 de 502 empresas · faltam ~6 min 42 s'
            .replaceAll(' 42 s', '')
            .replaceAll('~6 min', '~6 min'));
    expect(importProgressLine(log(processadas: 40, inicio: inicio), now),
        '40 empresas processadas');
  });

  testWidgets('mostra percentual, barra e aviso de falhas', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: ImportProgress(
          log: log(processadas: 251, estimado: 502, inicio: inicio, falhas: 3),
          now: inicio.add(const Duration(minutes: 4)),
        ),
      ),
    ));

    expect(find.text('Importando sua carteira'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('251 de 502 empresas'), findsOneWidget);
    expect(find.textContaining('3 com falha'), findsOneWidget);
    expect(find.textContaining('continua no servidor'), findsOneWidget);
  });

  testWidgets('sem estimativa: sem percentual, só a contagem', (tester) async {
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: ImportProgress(
            log: log(processadas: 40, inicio: inicio), now: inicio),
      ),
    ));
    expect(find.byKey(const ValueKey('import-percent')), findsNothing);
    expect(find.text('40 empresas processadas'), findsOneWidget);
  });
}
