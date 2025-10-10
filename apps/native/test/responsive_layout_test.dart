import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manykee_native/src/screens/vault_screen.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'helpers/fake_vault_state.dart';

void main() {
 group('Responsive layout breakpoints', () {
 late FakeVaultState vaultState;

 setUp(() {
 vaultState = FakeVaultState();
 });

 Widget buildApp() {
 return MaterialApp(
 theme: ManyKeeTheme.light(),
 home: NativeVaultScreen(vaultState: vaultState),
 );
 }

 testWidgets('desktop (>900px): three panels, no menu button',
 (tester) async {
 tester.view.physicalSize = const Size(1200, 800);
 tester.view.devicePixelRatio = 1.0;
 addTearDown(() {
 tester.view.resetPhysicalSize();
 tester.view.resetDevicePixelRatio();
 });

 await tester.pumpWidget(buildApp());
 await tester.pumpAndSettle();

 // Desktop: no drawer menu button
 expect(find.byIcon(Icons.menu), findsNothing);

 // All three panels visible: group tree, entry list, entry detail empty
 expect(find.byType(GroupTree), findsOneWidget);
 expect(find.byType(EntryList), findsOneWidget);
 expect(find.byType(EntryDetailEmpty), findsOneWidget);
 });

 testWidgets('tablet (600-900px): two panels, drawer button',
 (tester) async {
 tester.view.physicalSize = const Size(750, 800);
 tester.view.devicePixelRatio = 1.0;
 addTearDown(() {
 tester.view.resetPhysicalSize();
 tester.view.resetDevicePixelRatio();
 });

 await tester.pumpWidget(buildApp());
 await tester.pumpAndSettle();

 // Tablet: drawer menu button present
 expect(find.byIcon(Icons.menu), findsOneWidget);

 // Two panels visible (entry list + detail)
 expect(find.byType(EntryList), findsOneWidget);

 // Open drawer and verify group tree appears
 await tester.tap(find.byIcon(Icons.menu));
 await tester.pumpAndSettle();
 // "General" appears in both drawer GroupTree and EntryList header
 expect(find.text('General'), findsWidgets);
 expect(find.text('Email'), findsOneWidget);
 });

 testWidgets('mobile (<600px): navigation stack, ManyKee title',
 (tester) async {
 tester.view.physicalSize = const Size(400, 800);
 tester.view.devicePixelRatio = 1.0;
 addTearDown(() {
 tester.view.resetPhysicalSize();
 tester.view.resetDevicePixelRatio();
 });

 await tester.pumpWidget(buildApp());
 await tester.pumpAndSettle();

 // Mobile at root: "ManyKee" title, groups visible, no entry list
 expect(find.text('ManyKee'), findsOneWidget);
 expect(find.byType(EntryList), findsNothing);
 expect(find.byIcon(Icons.arrow_back), findsNothing);

 // Tap a group to navigate to entry list
 await tester.tap(find.text('General'));
 await tester.pumpAndSettle();

 // Now entry list should show with back button
 expect(find.byIcon(Icons.arrow_back), findsOneWidget);
 expect(find.text('ManyKee'), findsNothing); // Title changes to search bar
 });
 });
}
