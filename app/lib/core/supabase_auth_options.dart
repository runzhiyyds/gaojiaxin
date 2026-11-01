import 'package:supabase_flutter/supabase_flutter.dart';

/// An API hostname change must not strand the existing persisted session.
FlutterAuthClientOptions supabaseAuthOptions(String storageKey) =>
    FlutterAuthClientOptions(
      localStorage: storageKey.isEmpty
          ? null
          : SharedPreferencesLocalStorage(persistSessionKey: storageKey),
    );
