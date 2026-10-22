import 'dart:math';

String newEpcrId(DateTime time, {Random? random}) {
  final rng = random ?? Random.secure();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${time.year.toString().padLeft(4, '0')}${two(time.month)}'
      '${two(time.day)}${two(time.hour)}${two(time.minute)}${two(time.second)}';
  final suffix = List.generate(
    16,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join().toUpperCase();
  return '$stamp-$suffix';
}
