import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/core/format/br_format.dart';

void main() {
  final d = DateTime(2026, 11, 10, 9, 5);

  test('data e hora no padrão brasileiro', () {
    expect(formatDateBr(d), '10/11/2026');
    expect(formatTimeBr(d), '09:05');
    expect(formatDateTimeBr(d), '10/11/2026 às 09:05');
    expect(formatDateLongBr(d), 'terça-feira, 10 de novembro de 2026');
    expect(
        formatDateLongBr(DateTime(2026, 3, 1)), 'domingo, 1 de março de 2026');
  });

  test('rótulo do dia: hoje, ontem ou a data', () {
    final now = DateTime(2026, 11, 12, 15);
    expect(formatDayLabelBr(DateTime(2026, 11, 12), now: now), 'Hoje');
    expect(formatDayLabelBr(DateTime(2026, 11, 11), now: now), 'Ontem');
    expect(formatDayLabelBr(DateTime(2026, 11, 10), now: now), '10/11/2026');
  });

  test('"visto há": relativo perto, data completa longe', () {
    final now = DateTime(2026, 11, 12, 15, 0);
    expect(formatSinceBr(DateTime(2026, 11, 12, 14, 59, 40), now: now),
        'agora há pouco');
    expect(
        formatSinceBr(DateTime(2026, 11, 12, 14, 30), now: now), 'há 30 min');
    expect(formatSinceBr(DateTime(2026, 11, 12, 11, 0), now: now), 'há 4 h');
    expect(formatSinceBr(DateTime(2026, 11, 12, 6, 15), now: now),
        'hoje às 06:15');
    expect(formatSinceBr(DateTime(2026, 11, 11, 18, 30), now: now),
        'ontem às 18:30');
    expect(formatSinceBr(DateTime(2026, 11, 8, 9, 5), now: now),
        '08/11/2026 às 09:05');
  });

  test('duração e distância', () {
    expect(formatDurationBr(const Duration(seconds: 20)), 'menos de 1 min');
    expect(formatDurationBr(const Duration(minutes: 45)), '45 min');
    expect(formatDurationBr(const Duration(minutes: 60)), '1 h');
    expect(formatDurationBr(const Duration(minutes: 95)), '1 h 35 min');
    expect(formatDistanceBr(350.4), '350 m');
    expect(formatDistanceBr(1234), '1,2 km');
    expect(formatDistanceBr(12400), '12 km');
  });

  test('números e dinheiro', () {
    expect(formatThousandsBr(203204), '203.204');
    expect(formatThousandsBr(999), '999');
    expect(formatThousandsBr(-1234567), '-1.234.567');
    expect(formatMoneyBr(260300), 'R\$ 260.300,00');
    expect(formatMoneyBr(1187084.745), 'R\$ 1.187.084,75');
    expect(formatCompactBr(9360000000), 'R\$ 9,4 bi');
    expect(formatCompactBr(1187084), 'R\$ 1,2 mi');
    expect(formatCompactBr(260300), 'R\$ 260 mil');
    expect(formatCompactBr(950), 'R\$ 950');
    expect(formatCompactBr(976239354, prefix: 'US\$'), 'US\$ 976 mi');
    expect(formatCompactBr(2000000), 'R\$ 2 mi');
  });

  test('anos completos', () {
    final now = DateTime(2026, 11, 12);
    expect(yearsBetween(DateTime(2004, 10, 25), now: now), 22);
    expect(yearsBetween(DateTime(2004, 12, 25), now: now), 21);
    expect(yearsBetween(DateTime(2027, 1, 1), now: now), 0);
  });
}
