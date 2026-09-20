/// Where the pairing lives on the phone.
///
/// The decrypted backlog is kept in the clear locally and protected by the OS the way the
/// desktop store is — so the one thing worth guarding is the key, and it is kept apart from the
/// rows it opens. The keychain on iOS and the keystore on Android are that separate place.
///
/// The read token rides along with it. A pairing is one act and one thing to revoke: the URL to
/// read from, the token that gets in, and the key that opens what comes back. Splitting the three
/// across two homes would only invent a way for a phone to hold half a pairing.
///
/// Neither place is emptied by deleting the app on iOS, so the pairing is tied to the app's
/// container by hand — [PairingStore.forgetIfReinstalled].
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'record_envelope.dart';

/// Everything a QR code hands the phone, and everything it needs afterwards.
class Pairing {
  const Pairing({
    required this.url,
    required this.readToken,
    required this.encryptionKey,
  });

  /// The owner's own Worker.
  final Uri url;

  /// This device's read token, base64url as issued. One per device, so losing one phone costs
  /// only that phone its pairing.
  final String readToken;

  /// The key, base64url as issued. Shared by every device the owner pairs.
  final String encryptionKey;

  /// Builds the cipher this pairing's records open with.
  ///
  /// Throws [EnvelopeException] if the stored key is not a 256-bit key.
  RecordCipher cipher() => RecordCipher.fromBase64Key(encryptionKey);

  Map<String, Object?> toJson() => {
    'url': url.toString(),
    't': readToken,
    'k': encryptionKey,
  };

  static Pairing? _fromJson(Object? decoded) {
    if (decoded is! Map<String, Object?>) return null;
    final url = Uri.tryParse(decoded['url'] as String? ?? '');
    final readToken = decoded['t'];
    final encryptionKey = decoded['k'];
    if (url == null || readToken is! String || encryptionKey is! String) {
      return null;
    }
    // An entry an older build wrote carries a name as well. It is read past rather than refused:
    // a name is not one of the three things a pairing is, and unpairing a phone that reads
    // perfectly well would be the cost of a field nothing looks at any more.
    return Pairing(
      url: url,
      readToken: readToken,
      encryptionKey: encryptionKey,
    );
  }
}

/// Reads and writes the pairing in the keychain / keystore.
class PairingStore {
  const PairingStore({FlutterSecureStorage? storage})
    : _storage = storage ?? _protected;

  /// One entry, written and dropped whole, because a pairing is all three fields or none.
  static const _entry = 'pairing';

  /// The file in application support that says the entry belongs to this container.
  ///
  /// Application support is wiped when the app is deleted; the keychain is not. The mark is how
  /// the two are told apart — see [forgetIfReinstalled].
  static const markName = 'pairing.mark';

  /// `first_unlock_this_device` on the Apple side: after-first-unlock so a refresh that runs
  /// while the phone is in a pocket can still reach the key, and this-device-only so a backup
  /// restored onto a new phone arrives unpaired rather than quietly carrying the old phone's
  /// token — revoking a device has to mean something. The Android defaults are already a
  /// keystore-wrapped AES-GCM entry, which is the same bargain.
  static const _protected = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final FlutterSecureStorage _storage;

  /// The pairing, or null when this device has none.
  ///
  /// An entry that no longer parses reads as null — the same as never having paired, which is
  /// the state the app already knows how to explain.
  Future<Pairing?> read() async {
    final stored = await _storage.read(key: _entry);
    if (stored == null) return null;
    try {
      return Pairing._fromJson(jsonDecode(stored));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(Pairing pairing) =>
      _storage.write(key: _entry, value: jsonEncode(pairing.toJson()));

  /// Unpairs this device. What was already decrypted is not this store's to remove.
  Future<void> forget() => _storage.delete(key: _entry);

  /// Unpairs a phone whose app was deleted and installed again.
  ///
  /// Deleting the app takes its container with it and leaves the keychain alone, so on iOS the
  /// next install comes up still paired — holding the token and the key the person meant to
  /// remove. Android's keystore entry goes with the app's data, so that half already behaves this
  /// way; running on both keeps one path rather than two, and makes "delete it and start over"
  /// mean the same thing on each. It is the first repair anyone tries, and the last one a person
  /// handing the phone on relies upon.
  ///
  /// Called before the first read, from `openViewer`.
  Future<void> forgetIfReinstalled() async =>
      forgetIfReinstalledAt((await getApplicationSupportDirectory()).path);

  /// [forgetIfReinstalled] against a named directory, for tests and for anything that wants a
  /// container it can throw away.
  Future<void> forgetIfReinstalledAt(String container) async {
    final mark = File('$container/$markName');
    if (mark.existsSync()) return;
    // Forget first: a mark written before the entry is gone would call the next launch settled
    // and leave the old pairing standing for good.
    await forget();
    mark.createSync(recursive: true);
  }
}
