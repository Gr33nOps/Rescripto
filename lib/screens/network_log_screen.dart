import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/network_log_entry.dart';
import '../services/network/network_log.dart';

/// The proof screen: every request `NetworkGuard` has let through, blocked,
/// or logged as cancelled/failed, since the log started keeping rows.
///
/// A `FutureBuilder` with pull-to-refresh, not a `ChangeNotifier` — the log
/// is written by `NetworkGuard`, not read live by anything else, and the
/// per-request cap (`kDefaultNetworkLogMaxRows`) is deliberate: this is an
/// audit trail for a glance, not a metering system.
///
/// Overclaiming here is worse than not shipping it, so the empty state and
/// footer say plainly what this log *cannot* see: native code (`libllama.so`
/// / `libwhisper.so`) makes no network calls of its own today, but nothing
/// here could prove that stays true, and the system speech recognizer's
/// audio path is invisible to this log entirely — see
/// `SpeechCapabilities.auditableEgress`.
class NetworkLogScreen extends StatefulWidget {
  const NetworkLogScreen({super.key});

  @override
  State<NetworkLogScreen> createState() => _NetworkLogScreenState();
}

class _NetworkLogScreenState extends State<NetworkLogScreen> {
  late Future<List<NetworkLogEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _entries = context.read<NetworkLog>().recent(limit: 200);
  }

  Future<void> _refresh() async {
    final future = context.read<NetworkLog>().recent(limit: 200);
    setState(() {
      _entries = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network log')),
      body: SafeArea(
        child: FutureBuilder<List<NetworkLogEntry>>(
          future: _entries,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _Footer(empty: entries.isEmpty),
                  const SizedBox(height: 12),
                  if (entries.isEmpty)
                    const _EmptyState()
                  else
                    for (final entry in entries) ...[
                      _LogTile(entry: entry),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.empty});

  final bool empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This log shows the host and path for network requests made by '
              'Rescripto. It never stores headers, request bodies, query '
              'strings, or credentials.',
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Nothing logged yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Requests will appear here when Rescripto sends or blocks them.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final NetworkLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (entry.outcome) {
      NetworkOutcome.allowed => (Icons.check_circle_outline, scheme.primary),
      NetworkOutcome.blockedByPolicy => (Icons.block_outlined, scheme.error),
      NetworkOutcome.blockedByKillSwitch => (
        Icons.power_settings_new,
        scheme.error,
      ),
      NetworkOutcome.failed => (Icons.error_outline, scheme.error),
      NetworkOutcome.cancelled => (
        Icons.cancel_outlined,
        scheme.onSurfaceVariant,
      ),
    };

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text('${entry.method} ${entry.host}${entry.path}'),
        subtitle: Text(
          [
            entry.purpose ?? _featureLabel(entry.feature.name),
            _outcomeLabel(entry.outcome),
            if (entry.statusCode != null) 'HTTP ${entry.statusCode}',
            if (entry.duration != null) '${entry.duration!.inMilliseconds}ms',
          ].join(' · '),
        ),
        trailing: Text(
          _relativeTime(entry.startedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }

  String _featureLabel(String raw) {
    // 'modelDownload' -> 'Model download'.
    final spaced = raw.replaceAllMapped(
      RegExp('([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]!.toLowerCase()}',
    );
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  String _outcomeLabel(NetworkOutcome outcome) => switch (outcome) {
    NetworkOutcome.allowed => 'Allowed',
    NetworkOutcome.blockedByPolicy => 'Blocked (Privacy setting)',
    NetworkOutcome.blockedByKillSwitch => 'Blocked (kill switch)',
    NetworkOutcome.failed => 'Failed',
    NetworkOutcome.cancelled => 'Cancelled',
  };

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
