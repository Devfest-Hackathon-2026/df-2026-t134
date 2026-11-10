import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/live_check.dart';

/// Opens a web page outside the app (a new browser tab on the web).
typedef LinkOpener = Future<void> Function(Uri uri);

/// Overridden in tests, which must not open real pages.
final linkOpenerProvider = Provider<LinkOpener>(
  (ref) => (uri) async {
    await launchUrl(uri, webOnlyWindowName: '_blank');
  },
);

/// The site of [source] for the learner: its title (Google Search uses the
/// domain, e.g. `wikipedia.org`), or the address's host when there is none.
String sourceSite(WebSource source) {
  if (source.title.trim().isNotEmpty) {
    return source.title.trim();
  }
  return Uri.tryParse(source.uri)?.host ?? source.uri;
}

/// Only web pages are opened (never other schemes from the response).
Uri? _webUri(WebSource source) {
  final uri = Uri.tryParse(source.uri);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
      ? uri
      : null;
}

/// The pages Google Search found, each opening in a new tab.
class WebSourceList extends ConsumerWidget {
  const WebSourceList({
    super.key,
    required this.sources,
    required this.emptyText,
  });

  final List<WebSource> sources;

  /// Shown instead of the list when no page was found.
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (sources.isEmpty) {
      return Text(
        emptyText,
        key: const Key('web-sources-empty'),
        style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
      );
    }
    final open = ref.watch(linkOpenerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, source) in sources.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SourceTile(
              key: Key('web-source-$i'),
              source: source,
              onOpen: switch (_webUri(source)) {
                final uri? => () => open(uri),
                null => null,
              },
            ),
          ),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({super.key, required this.source, required this.onOpen});

  final WebSource source;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final site = sourceSite(source);
    return Semantics(
      link: onOpen != null,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.public_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'ページを開く（新しいタブ）',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.open_in_new_rounded, color: scheme.outline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
