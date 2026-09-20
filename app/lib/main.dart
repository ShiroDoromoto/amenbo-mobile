/// Amenbo Viewer — the backlog, on the phone, while you are away from the PC.
///
/// The app reads an encrypted snapshot out of a place its owner holds — their own Cloudflare
/// Worker — decrypts it here, and shows it. It never writes back.
///
/// **The app has to be complete on its own.** Store review takes as long as it takes, so there
/// will be users running this build against an Amenbo and a plugin that know nothing about it.
/// Nothing here may depend on either one being present, and no state that follows from their
/// absence is an error: an app nobody has paired yet is working correctly.
///
/// What it shows is decided in [ViewerHome]: the setup instructions on a phone with no way in,
/// and the backlog on one that has.
library;

import 'package:flutter/material.dart';

import 'home.dart';
import 'l10n/language.dart';
import 'l10n/words.dart';
import 'pairing_store.dart';
import 'settings.dart';
import 'store/backlog_store.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await openViewer());
}

/// The app, assembled the one way it is assembled.
///
/// The probe build starts from here too, so what it dumps on a real phone is this app rather than
/// a second assembly of it that could drift.
Future<AmenboViewerApp> openViewer() async {
  // Before anything reads a pairing: one that outlived the container it was made in belongs to
  // an app the person deleted, and this is the launch that notices.
  await const PairingStore().forgetIfReinstalled();
  final store = await BacklogStore.open();
  return AmenboViewerApp(
    store: store,
    settings: SettingsController(StoredSettings(store)),
  );
}

class AmenboViewerApp extends StatelessWidget {
  const AmenboViewerApp({
    super.key,
    required this.store,
    required this.settings,
  });

  /// The phone's copy of the backlog. Opened before the first frame — it is a file on the device,
  /// and drawing the app in the wrong brightness and correcting it a moment later is a flash the
  /// person did not ask for.
  final BacklogStore store;

  /// Held here rather than looked up, because the one setting the app itself obeys — how dark it
  /// is — is decided at this level and nowhere else.
  final SettingsController settings;

  /// The name the stores show, in every language — it reads the same in each, so it is the one
  /// piece of text on these screens that is not on a sheet.
  static const title = 'Amenbo Viewer';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: title,
        // The app's own words and Material's — the licence page, the text field's menu, the
        // scroll bar's labels — come out of the same choice of language.
        localizationsDelegates: Words.localizationsDelegates,
        supportedLocales: Words.supportedLocales,
        // Which of them, decided here rather than left to Flutter's own matching: Chinese and
        // Portuguese need an answer the phone's tags do not spell out.
        localeListResolutionCallback: languageFor,
        theme: viewerTheme(Brightness.light),
        darkTheme: viewerTheme(Brightness.dark),
        themeMode: settings.value.appearance.themeMode,
        home: ViewerHome(store: store, settings: settings, appName: title),
      ),
    );
  }
}
