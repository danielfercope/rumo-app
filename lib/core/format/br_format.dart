/// Formatação de datas, horas, durações e distâncias no padrão brasileiro,
/// sem depender do `intl` (nem de inicializar locale).
library;

String _two(int n) => n.toString().padLeft(2, '0');

const _weekdays = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sábado',
  'domingo',
];

const _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// `10/11/2026`
String formatDateBr(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// `09:05`
String formatTimeBr(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// `10/11/2026 às 09:05`
String formatDateTimeBr(DateTime d) =>
    '${formatDateBr(d)} às ${formatTimeBr(d)}';

/// `terça-feira, 10 de novembro de 2026`
String formatDateLongBr(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} de ${_months[d.month - 1]} de ${d.year}';

/// Rótulo curto de um dia: `Hoje`, `Ontem` ou `10/11/2026`.
String formatDayLabelBr(DateTime d, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(today.year, today.month, today.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Ontem';
  return formatDateBr(d);
}

/// Quando algo aconteceu, em linguagem natural: `agora há pouco`, `há 5 min`,
/// `há 3 h`, `ontem às 18:30` ou `10/11/2026 às 09:05`.
String formatSinceBr(DateTime d, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(d);
  if (diff.isNegative || diff.inMinutes < 1) return 'agora há pouco';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 6) return 'há ${diff.inHours} h';
  final days = DateTime(ref.year, ref.month, ref.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (days == 0) return 'hoje às ${formatTimeBr(d)}';
  if (days == 1) return 'ontem às ${formatTimeBr(d)}';
  return formatDateTimeBr(d);
}

/// `45 min`, `1 h`, `1 h 35 min`.
String formatDurationBr(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 1) return 'menos de 1 min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}

/// `350 m`, `1,2 km`, `12 km` (vírgula decimal).
String formatDistanceBr(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  if (km >= 10) return '${km.round()} km';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// `203.204` (ponto de milhar).
String formatThousandsBr(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buf';
}

/// `R$ 260.300,00`.
String formatMoneyBr(num value, {String prefix = 'R\$'}) {
  final cents = (value.abs() * 100).round();
  final reais = formatThousandsBr(cents ~/ 100);
  return '${value < 0 ? '-' : ''}$prefix $reais,${_two(cents % 100)}';
}

/// Valor resumido: `R$ 9,4 bi`, `R$ 1,2 mi`, `R$ 260 mil`, `R$ 950`.
/// `prefix` troca a moeda (ex.: `US$`).
String formatCompactBr(num value, {String prefix = 'R\$'}) {
  final v = value.abs();
  String one(double x) {
    final text = x >= 100 ? x.round().toString() : x.toStringAsFixed(1);
    return text.replaceAll('.', ',').replaceFirst(RegExp(r',0$'), '');
  }

  final sign = value < 0 ? '-' : '';
  final String body;
  if (v >= 1e9) {
    body = '${one(v / 1e9)} bi';
  } else if (v >= 1e6) {
    body = '${one(v / 1e6)} mi';
  } else if (v >= 1e3) {
    body = '${(v / 1e3).round()} mil';
  } else {
    body = v.round().toString();
  }
  return '$sign$prefix $body';
}

/// Anos completos entre [from] e [now]: `0`, `21`.
int yearsBetween(DateTime from, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  var years = ref.year - from.year;
  if (ref.month < from.month ||
      (ref.month == from.month && ref.day < from.day)) {
    years--;
  }
  return years < 0 ? 0 : years;
}
