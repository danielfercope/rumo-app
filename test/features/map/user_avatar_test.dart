import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/widgets/user_avatar.dart';

final _onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

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

  group('UserAvatar', () {
    Future<void> pump(WidgetTester tester, {Uint8List? photo}) =>
        tester.pumpWidget(CupertinoApp(
          home: Center(child: UserAvatar(initials: 'DP', photo: photo)),
        ));

    testWidgets('sem foto mostra as iniciais', (tester) async {
      await pump(tester);
      expect(find.text('DP'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('com foto usa os bytes do cache, sem ir à rede',
        (tester) async {
      await pump(tester, photo: _onePixelPng);
      expect(find.byType(Image), findsOneWidget);
      expect(
          tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    });

    testWidgets('bytes que não decodificam caem nas iniciais', (tester) async {
      await pump(tester, photo: Uint8List.fromList([1, 2, 3]));
      // a decodificação roda fora do relógio simulado
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('DP'), findsOneWidget);
    });
  });
}
