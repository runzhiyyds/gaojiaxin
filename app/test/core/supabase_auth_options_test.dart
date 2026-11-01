import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_story/core/supabase_auth_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gateway storage reads and updates the original session namespace', () async {
    const original = 'sb-uebeyflmmpesjolcrhnp-auth-token';
    const alias = 'sb-gaojiaxin-check-auth-token';
    SharedPreferences.setMockInitialValues({
      original: 'existing-session-fixture',
      alias: 'unrelated-session-fixture',
    });
    final storage = supabaseAuthOptions(original).localStorage!;
    await storage.initialize();
    expect(await storage.accessToken(), 'existing-session-fixture');
    await storage.persistSession('refreshed-session-fixture');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(original), 'refreshed-session-fixture');
    expect(prefs.getString(alias), 'unrelated-session-fixture');
    await storage.removePersistedSession();
    expect(prefs.containsKey(original), false);
    expect(prefs.getString(alias), 'unrelated-session-fixture');
  });

  test('other projects retain SDK default storage behavior', () {
    expect(supabaseAuthOptions('').localStorage, isNull);
  });
}
