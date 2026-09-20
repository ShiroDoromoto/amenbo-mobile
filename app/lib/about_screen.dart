/// What this build is — the answers worth having when something is not behaving, and the way to
/// the privacy policy.
///
/// The app's own version, where the copy came from, the contract version it reads, and the
/// licences of what it is built out of. Nothing is fetched: the origin is read off the phone and
/// the licences are the ones Flutter collected at build time, so this screen works with the phone
/// in a tunnel like every other one.
///
/// The policy is the exception, and it is a link because it has to be one: both stores ask that
/// somebody who has the app can reach it from inside the app, and a page carried in the build
/// would be a second copy to keep level with the one the stores were given.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'build_origin.dart';
import 'cloudflare_intake.dart';
import 'l10n/words.dart';
import 'ui/measure.dart';
import 'ui/tokens.dart';

/// This build's version, as the stores show it.
///
/// It is written here as well as in `pubspec.yaml` because reading it back at runtime would mean
/// carrying a plugin to do it, for one line of text. A test holds the two together.
const appVersion = '1.2.7';

/// The number the stores count with, which is the other half of `pubspec.yaml`'s `version:`.
///
/// A copy handed out for testing keeps the same version for build after build, so the version
/// alone cannot tell somebody which one they are holding — and a tester who cannot say that is a
/// tester whose report cannot be placed. Held to the pubspec by the same test as [appVersion].
const appBuild = '13';

/// The two together, the way both stores write them.
const appVersionShown = '$appVersion ($appBuild)';

/// Where the privacy policy is, written once.
///
/// The same address in all nineteen languages: the site answers in the reader's own, and a link
/// per language would be nineteen things to keep alive. It is what both stores were handed, so a
/// second address written anywhere here would be the one that goes stale.
const privacyPolicyUrl = 'https://amenbo.work/privacy/';

/// Hands a web address to whatever the phone opens links with, and says whether it went.
typedef OpenALink = Future<bool> Function(Uri where);

/// The browser, as this app asks for it: outside, and left standing when the app is closed.
Future<bool> openInTheBrowser(Uri where) =>
    launchUrl(where, mode: LaunchMode.externalApplication);

class AboutScreen extends StatefulWidget {
  const AboutScreen({
    super.key,
    required this.appName,
    this.readOrigin = BuildOrigin.read,
    this.openLink = openInTheBrowser,
  });

  final String appName;

  /// How the origin is asked for. The phone answers by default; a test hands its own answer in,
  /// the same way it would on a machine where there is no phone to ask.
  final Future<BuildOrigin> Function() readOrigin;

  /// How a link is opened. The phone's browser by default — handed in so a test can watch what
  /// was asked for, and so a refusal can be made to happen rather than waited for.
  final OpenALink openLink;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  /// Null until the phone has answered. The line is left out rather than filled with a guess —
  /// the answer arrives in the time it takes to look at a file name, and a screen that said
  /// "not known" first and corrected itself would be reporting the wait, not the build.
  BuildOrigin? _origin;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final origin = await widget.readOrigin();
    if (!mounted) return;
    setState(() => _origin = origin);
  }

  /// Opens the policy, and says the address out loud when the phone cannot.
  ///
  /// **A link that quietly does nothing is worse than no link.** There are phones with no browser
  /// to hand it to, and a locked-down one where the call is refused outright — and somebody
  /// looking for the policy is looking for something they were told they could read, so what they
  /// get instead has to be the address itself, to be read or typed somewhere else.
  Future<void> _openThePolicy() async {
    final words = Words.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await widget.openLink(Uri.parse(privacyPolicyUrl));
    } catch (_) {
      // Whatever came back from the platform, the person's next move is the same one.
      opened = false;
    }
    if (opened || !mounted) return;
    messenger?.showSnackBar(
      SnackBar(content: Text(words.privacyPolicyUnopened(privacyPolicyUrl))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = Words.of(context);
    final origin = _origin;

    return Scaffold(
      appBar: AppBar(title: Text(words.aboutTitle)),
      body: Measured.prose(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Space.s7),
          children: [
            ListTile(
              title: Text(widget.appName),
              subtitle: Text(words.appVersion(appVersionShown)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.s3,
                Space.gutter,
                Space.s5,
              ),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.s3,
                  children: [
                    if (origin != null) Text(buildOriginWords(words, origin)),
                    Text(words.contractLine(contractVersion)),
                  ],
                ),
              ),
            ),
            const Divider(height: Stroke.rule),
            // Above the licences, and marked as leaving the app: it is the row somebody came
            // looking for, and the one that puts a browser in front of them.
            ListTile(
              title: Text(words.privacyPolicy),
              trailing: const Icon(Icons.open_in_new),
              onTap: _openThePolicy,
            ),
            ListTile(
              title: Text(words.licences),
              onTap: () => showLicensePage(
                context: context,
                applicationName: widget.appName,
                applicationVersion: appVersionShown,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
