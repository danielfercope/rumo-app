import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/widgets/user_avatar.dart';

void main() {
  group('userInitials', () {
    test('primeira e última inicial', () {
      expect(userInitials('Daniel Pereira'), 'DP');
      expect(userInitials('Maria da Silva Santos'), 'MS');
    });

    test('nome único, vazio e com espaços extras', () {
      expect(userInitials('daniel'), 'D');
      expect(userInitials(''), '?');
      expect(userInitials('   '), '?');
      expect(userInitials('  ana   lima '), 'AL');
    });
  });

  test('fetchUserPhoto devolve null sem URL', () async {
    expect(await fetchUserPhoto(null), isNull);
    expect(await fetchUserPhoto(''), isNull);
  });

  test('renderUserAvatarPng gera um PNG com as iniciais', () async {
    final png = await renderUserAvatarPng(initials: 'DP', size: 64);
    // Assinatura de arquivo PNG.
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('foto inválida cai nas iniciais em vez de falhar', () async {
    final png = await renderUserAvatarPng(
        initials: 'DP', photo: Uint8List.fromList([1, 2, 3]), size: 64);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
