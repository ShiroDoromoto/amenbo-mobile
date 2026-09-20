// These run against the package's own in-memory platform, so what they check is this file's
// half of the bargain — that a pairing survives whole, that forgetting leaves nothing behind,
// and that an unpaired phone reads as unpaired rather than as a failure. Whether the entry is
// actually in the keychain is the platform's half and only a device can say.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amenbo_viewer/pairing_store.dart';
import 'package:amenbo_viewer/record_envelope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pairing = Pairing(
    url: Uri.parse('https://amenbo.example.workers.dev'),
    readToken: 'cmVhZC10b2tlbg',
    encryptionKey: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a phone nobody has paired holds nothing', () async {
    // Not an error and not an empty backlog — the state the guide screen exists for.
    expect(await const PairingStore().read(), isNull);
  });

  test('a pairing comes back the way it went in', () async {
    const store = PairingStore();
    await store.save(pairing);

    final stored = await store.read();
    expect(stored?.url, pairing.url);
    expect(stored?.readToken, pairing.readToken);
    expect(stored?.encryptionKey, pairing.encryptionKey);
  });

  test('a phone paired while the code carried a name stays paired', () async {
    // The entry an older build wrote has a name in it. Reading that as a broken entry would
    // unpair a phone that reads perfectly well, over a field nothing looks at any more.
    FlutterSecureStorage.setMockInitialValues({
      'pairing':
          '{"url":"https://amenbo.example.workers.dev","t":"cmVhZC10b2tlbg",'
          '"k":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","l":"iPhone"}',
    });

    final stored = await const PairingStore().read();
    expect(stored?.readToken, 'cmVhZC10b2tlbg');
  });

  test('the stored key opens what the PC sealed with it', () async {
    // The point of keeping the key here at all: it has to come back usable, not merely intact.
    const store = PairingStore();
    await store.save(pairing);

    final cipher = (await store.read())!.cipher();
    final record = SealedRecord.fromJson({
      'k': 'task/2812',
      'op': 'put',
      'n': 'oKGio6SlpqeoqaqrrK2ur7CxsrO0tba3',
      'c':
          'Ps5jeZVnlpRQXQGrBVnXrF6IpQ5JhHU6n_loZUhAfKQyBRPMxdifTxkI7d54tzrN'
          'J4_FemmLUQASHawJq6FQ_j2g4XFN2WvWGVaSToaUs80',
    });

    expect((await cipher.openJson(record))['id'], 2812);
  });

  test('forgetting leaves nothing to read', () async {
    const store = PairingStore();
    await store.save(pairing);
    await store.forget();

    expect(await store.read(), isNull);
  });

  test('an entry that no longer parses reads as unpaired', () async {
    FlutterSecureStorage.setMockInitialValues({'pairing': 'not json'});

    expect(await const PairingStore().read(), isNull);
  });

  group('a pairing does not outlive the app it was made in', () {
    late Directory container;

    setUp(() => container = Directory.systemTemp.createTempSync('container'));
    tearDown(() => container.deleteSync(recursive: true));

    test('a container with no mark in it unpairs the phone', () async {
      // Deleting the app on iOS empties the container and leaves the keychain alone, so this is
      // what the first launch after a reinstall sees: an entry, and nothing that claims it.
      const store = PairingStore();
      await store.save(pairing);

      await store.forgetIfReinstalledAt(container.path);

      expect(await store.read(), isNull);
      expect(
        File('${container.path}/${PairingStore.markName}').existsSync(),
        isTrue,
      );
    });

    test(
      'a later launch in the same container leaves the pairing alone',
      () async {
        // The mark is written once. Every launch after it has to be an ordinary one, or the app
        // would unpair itself on the way in.
        const store = PairingStore();
        await store.forgetIfReinstalledAt(container.path);
        await store.save(pairing);

        await store.forgetIfReinstalledAt(container.path);

        expect((await store.read())?.readToken, pairing.readToken);
      },
    );

    test('a phone that was never paired comes out of it unpaired', () async {
      // The first launch of a first install runs this too, and has to be harmless.
      const store = PairingStore();

      await store.forgetIfReinstalledAt(container.path);

      expect(await store.read(), isNull);
    });
  });
}
