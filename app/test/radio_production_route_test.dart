import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:almomin/app/router.dart';
import 'package:almomin/core/services/settings_service.dart';
import 'package:almomin/features/radio/curated_radio_screen.dart';
import 'package:almomin/features/radio/islamic_radio_screen.dart';
void main(){
 testWidgets('actual production router builds curated screen for saved radio deep link', (t) async {
  SharedPreferences.setMockInitialValues({});
  await SettingsService.instance.init(forceReload:true);
  final route=appRouter.configuration.routes.whereType<GoRoute>().singleWhere((r)=>r.path=='/islamic-radio');
  expect(route.parentNavigatorKey,rootNavigatorKey);
  appRouter.go('/islamic-radio');
  await t.pumpWidget(MaterialApp.router(routerConfig:appRouter));
  await t.pumpAndSettle();
  expect(find.byType(CuratedRadioScreen),findsOneWidget);
  expect(find.byType(IslamicRadioScreen),findsNothing);
  expect(find.text('المفضلة'),findsOneWidget);
  expect(find.byKey(const Key('curated_radio_cat_c2')),findsOneWidget);
  expect(t.takeException(),isNull);
  await t.pumpWidget(const SizedBox());await t.pumpAndSettle();
 });
}
