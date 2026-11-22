import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../data/source_transfer_service.dart';

typedef SourceTransferImport = ({
  ReceivedSource source,
  bool allowPrivateNetwork,
});

class SourceTransferDialog extends ConsumerStatefulWidget {
  const SourceTransferDialog({super.key});

  @override
  ConsumerState<SourceTransferDialog> createState() =>
      _SourceTransferDialogState();
}

class _SourceTransferDialogState extends ConsumerState<SourceTransferDialog> {
  SourceTransferService? _service;
  String? _code;
  ReceivedSource? _source;
  String? _error;
  bool _allowPrivateNetwork = false;

  Future<void> _generateCode() async {
    if (_service != null) return;
    final service = ref.read(sourceTransferServiceProvider)();
    setState(() {
      _service = service;
      _error = null;
    });
    try {
      final slot = await service.createSlot();
      if (!mounted) return;
      setState(() => _code = slot.code);
      final source = await service.waitForSource(slot);
      if (mounted) setState(() => _source = source);
    } on SourceTransferException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      service.close();
      if (mounted) {
        setState(() {
          _service = null;
          _code = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final code = _code;
    final error = _error;
    return AlertDialog(
      title: Text(
        source == null ? 'Receive from phone' : 'Import received source?',
      ),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (source != null) ...[
              Text(
                source.xtreamLogin == null ? 'M3U playlist' : 'Xtream login',
              ),
              const SizedBox(height: 6),
              Text(
                source.address.host,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 14),
              const ProviderTrustNotice(),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Allow local/private network addresses'),
                subtitle: const Text(
                  'Enable this only for a source you trust on your local network.',
                ),
                value: _allowPrivateNetwork,
                onChanged: (value) =>
                    setState(() => _allowPrivateNetwork = value ?? false),
              ),
            ] else if (code != null) ...[
              const Text(
                'In Klipa on your phone, go to Settings → Send to another device and enter this code.',
              ),
              const SizedBox(height: 14),
              Center(
                child: SelectableText(
                  code,
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(letterSpacing: 5),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Waiting for your phone. The code expires in five minutes.',
              ),
            ] else if (_service != null) ...[
              const Text('Generating a one-time code…'),
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else ...[
              const Text(
                'Send an M3U URL or Xtream login from Klipa on your phone. '
                'The source goes through klipa.tv over HTTPS and is held '
                'in memory for up to 60 seconds after you send it.',
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (source != null)
          FilledButton(
            onPressed: () => Navigator.pop<SourceTransferImport>(context, (
              source: source,
              allowPrivateNetwork: _allowPrivateNetwork,
            )),
            child: const Text('Import'),
          )
        else if (_service == null)
          FilledButton(
            onPressed: _generateCode,
            child: const Text('Generate code'),
          ),
      ],
    );
  }
}

class ProviderTrustNotice extends StatelessWidget {
  const ProviderTrustNotice({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.security_rounded, size: 18, color: KlipaColors.warning),
      SizedBox(width: 8),
      Expanded(
        child: Text(
          'Only continue with a source you trust. HLS/DASH streams can send '
          'the player to additional hosts; Klipa does not proxy or validate '
          'every nested media request.',
          style: TextStyle(color: KlipaColors.foregroundDim, fontSize: 12),
        ),
      ),
    ],
  );
}
