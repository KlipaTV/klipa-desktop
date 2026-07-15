import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../domain/channel.dart';
import '../player/player_pane.dart';
import 'library_controller.dart';
import 'library_state.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchFocus = FocusNode(debugLabel: 'channel-search');
  final _playerController = PlayerPaneController();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final controller = ref.read(libraryControllerProvider.notifier);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
          unawaited(controller.importFile());
        },
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ): () {
          unawaited(_showUrlDialog(context, controller));
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              if (state.isLoading)
                const Center(
                  child: CircularProgressIndicator(
                    key: Key('library-loading'),
                    strokeWidth: 2,
                  ),
                )
              else if (state.channels.isEmpty)
                _Onboarding(
                  controller: controller,
                  isImporting: state.isImporting,
                  recoveryRequired: state.recoveryRequired,
                  onReset: () => _confirmAndReset(controller),
                )
              else
                _DesktopLibrary(
                  state: state,
                  controller: controller,
                  searchFocus: _searchFocus,
                  playerController: _playerController,
                  onReset: () => _confirmAndReset(controller),
                ),
              if (state.isImporting || state.isResetting)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Color(0x45000000)),
                  ),
                ),
              if (state.message != null || state.error != null)
                Positioned(
                  left: 88,
                  right: 16,
                  bottom: 16,
                  child: _Notice(
                    message: state.error ?? state.message!,
                    isError: state.error != null,
                    onDismiss: controller.dismissNotices,
                    actionLabel: state.recoveryRequired
                        ? 'Reset app data'
                        : null,
                    onAction: state.recoveryRequired
                        ? () => _confirmAndReset(controller)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndReset(LibraryController controller) async {
    final confirmed = await _showResetDialog(context);
    if (confirmed != true || !mounted) return;
    await _playerController.stop();
    if (!mounted) return;
    await controller.resetLibrary();
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding({
    required this.controller,
    required this.isImporting,
    required this.recoveryRequired,
    required this.onReset,
  });

  final LibraryController controller;
  final bool isImporting;
  final bool recoveryRequired;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            const _BrandMark(size: 62),
            const SizedBox(height: 24),
            Text(
              'Your channels. Nothing else.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'A lightweight Windows player from Klipa. Add a playlist '
              'you are authorized to use; Klipa does not provide content.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KlipaColors.foregroundDim, height: 1.5),
            ),
            const SizedBox(height: 36),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: FilledButton.icon(
                    key: const Key('add-playlist-url'),
                    onPressed: isImporting
                        ? null
                        : () => _showUrlDialog(context, controller),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Add playlist URL'),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: OutlinedButton.icon(
                    key: const Key('open-local-playlist'),
                    onPressed: isImporting ? null : controller.importFile,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Open local M3U'),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: OutlinedButton.icon(
                    key: const Key('add-xtream-login'),
                    onPressed: isImporting
                        ? null
                        : () => _showXtreamDialog(context, controller),
                    icon: const Icon(Icons.key_rounded),
                    label: const Text('Use Xtream login'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 15,
                  color: KlipaColors.foregroundDim,
                ),
                SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'Your library is encrypted on this PC. No telemetry is sent.',
                    style: TextStyle(
                      color: KlipaColors.foregroundDim,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (recoveryRequired) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('recover-reset-app-data'),
                onPressed: onReset,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Reset app data'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _DesktopLibrary extends StatelessWidget {
  const _DesktopLibrary({
    required this.state,
    required this.controller,
    required this.searchFocus,
    required this.playerController,
    required this.onReset,
  });

  final LibraryState state;
  final LibraryController controller;
  final FocusNode searchFocus;
  final PlayerPaneController playerController;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 980;
      return Row(
        children: [
          _SourceRail(controller: controller, onReset: onReset),
          SizedBox(
            width: compact ? 280 : 340,
            child: _ChannelBrowser(
              state: state,
              controller: controller,
              searchFocus: searchFocus,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: PlayerPane(
              channel: state.selectedChannel,
              controller: playerController,
            ),
          ),
        ],
      );
    },
  );
}

class _SourceRail extends StatelessWidget {
  const _SourceRail({required this.controller, required this.onReset});

  final LibraryController controller;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    color: KlipaColors.inkRaised,
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: _BrandMark(size: 34),
        ),
        const Divider(height: 1),
        const SizedBox(height: 10),
        const _RailButton(
          tooltip: 'Live TV',
          icon: Icons.live_tv_rounded,
          selected: true,
        ),
        const Spacer(),
        _RailButton(
          tooltip: 'Add local playlist',
          icon: Icons.playlist_add_rounded,
          onPressed: controller.importFile,
        ),
        _RailButton(
          tooltip: 'Add playlist URL',
          icon: Icons.add_link_rounded,
          onPressed: () => _showUrlDialog(context, controller),
        ),
        _RailButton(
          tooltip: 'Use Xtream login',
          icon: Icons.key_rounded,
          onPressed: () => _showXtreamDialog(context, controller),
        ),
        _RailButton(
          tooltip: 'Reset app data',
          icon: Icons.delete_outline_rounded,
          onPressed: onReset,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 10, 8, 16),
          child: Tooltip(
            message: 'Klipa for mobile',
            child: Icon(
              Icons.phone_android_rounded,
              size: 19,
              color: KlipaColors.foregroundDim,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tooltip,
    required this.icon,
    this.selected = false,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          backgroundColor: selected ? KlipaColors.inkHover : Colors.transparent,
          foregroundColor: selected
              ? KlipaColors.foreground
              : KlipaColors.foregroundDim,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon, size: 21),
      ),
    ),
  );
}

class _ChannelBrowser extends StatelessWidget {
  const _ChannelBrowser({
    required this.state,
    required this.controller,
    required this.searchFocus,
  });

  final LibraryState state;
  final LibraryController controller;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    final channels = state.visibleChannels;
    final groups = state.groups;
    final filtered =
        state.query.trim().isNotEmpty || state.selectedGroup != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
          child: Row(
            children: [
              Text('Live TV', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              Text(
                filtered
                    ? '${channels.length}/${state.channels.length}'
                    : '${state.channels.length}',
                style: const TextStyle(color: KlipaColors.foregroundDim),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: TextField(
            key: const Key('channel-search'),
            focusNode: searchFocus,
            onChanged: controller.search,
            decoration: const InputDecoration(
              hintText: 'Search channels',
              prefixIcon: Icon(Icons.search_rounded, size: 19),
              isDense: true,
            ),
          ),
        ),
        if (groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: KlipaColors.inkRaised,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KlipaColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    key: const Key('category-filter'),
                    value: state.selectedGroup,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(8),
                    dropdownColor: KlipaColors.inkRaised,
                    icon: const Icon(Icons.expand_more_rounded, size: 19),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All categories'),
                      ),
                      for (final group in groups)
                        DropdownMenuItem<String?>(
                          value: group,
                          child: Text(
                            group,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: controller.filterGroup,
                  ),
                ),
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: channels.isEmpty
              ? const Center(child: Text('No matching channels'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: channels.length,
                  itemExtent: 64,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    return _ChannelTile(
                      channel: channel,
                      selected: channel.id == state.selectedChannel?.id,
                      onPressed: () => controller.select(channel),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.onPressed,
  });

  final Channel channel;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: Material(
      color: selected ? KlipaColors.inkHover : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? KlipaColors.indigo.withValues(alpha: 0.24)
                      : KlipaColors.inkRaised,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: KlipaColors.border),
                ),
                child: Text(
                  channel.name.characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? KlipaColors.foreground
                            : KlipaColors.foregroundMuted,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (channel.group case final group?) ...[
                      const SizedBox(height: 2),
                      Text(
                        group.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KlipaColors.foregroundDim,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.graphic_eq_rounded,
                  color: KlipaColors.indigo,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.isError,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool isError;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    color: isError ? const Color(0xFF3B2024) : KlipaColors.inkHover,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline,
            color: isError
                ? Theme.of(context).colorScheme.error
                : KlipaColors.success,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message, maxLines: 3)),
          if (actionLabel case final label?)
            TextButton(onPressed: onAction, child: Text(label)),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    ),
  );
}

Future<bool?> _showResetDialog(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Reset app data?'),
    content: const Text(
      'This permanently removes all saved playlists and channels, provider '
      'credentials, favorites, guide/cache data, and settings from this PC.\n\n'
      'This cannot be undone.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('confirm-reset-app-data'),
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Reset app data'),
      ),
    ],
  ),
);

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.24),
    child: Image.asset(
      'assets/branding/logo_mark.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    ),
  );
}

Future<void> _showUrlDialog(
  BuildContext context,
  LibraryController controller,
) async {
  final request = await showDialog<_UrlImportRequest>(
    context: context,
    builder: (context) => const _UrlImportDialog(),
  );
  if (request == null) return;
  await controller.importUrl(
    request.url,
    allowPrivateNetwork: request.allowPrivateNetwork,
  );
}

Future<void> _showXtreamDialog(
  BuildContext context,
  LibraryController controller,
) async {
  final request = await showDialog<_XtreamImportRequest>(
    context: context,
    builder: (context) => const _XtreamImportDialog(),
  );
  if (request == null) return;
  await controller.importXtream(
    server: request.server,
    username: request.username,
    password: request.password,
    allowPrivateNetwork: request.allowPrivateNetwork,
  );
}

class _UrlImportRequest {
  const _UrlImportRequest({
    required this.url,
    required this.allowPrivateNetwork,
  });

  final String url;
  final bool allowPrivateNetwork;
}

class _UrlImportDialog extends StatefulWidget {
  const _UrlImportDialog();

  @override
  State<_UrlImportDialog> createState() => _UrlImportDialogState();
}

class _UrlImportDialogState extends State<_UrlImportDialog> {
  final _controller = TextEditingController();
  var _allowPrivateNetwork = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add playlist URL'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The address is fetched directly by this app. HTTPS is recommended.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('playlist-url-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Playlist address',
              hintText: 'https://provider.example/playlist.m3u',
            ),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _allowPrivateNetwork,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Allow local/private network addresses'),
            subtitle: const Text(
              'Only enable this for a trusted provider or a server on your LAN.',
            ),
            onChanged: (value) =>
                setState(() => _allowPrivateNetwork = value ?? false),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Import')),
    ],
  );

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(
      context,
      _UrlImportRequest(url: value, allowPrivateNetwork: _allowPrivateNetwork),
    );
  }
}

class _XtreamImportRequest {
  const _XtreamImportRequest({
    required this.server,
    required this.username,
    required this.password,
    required this.allowPrivateNetwork,
  });

  final String server;
  final String username;
  final String password;
  final bool allowPrivateNetwork;
}

class _XtreamImportDialog extends StatefulWidget {
  const _XtreamImportDialog();

  @override
  State<_XtreamImportDialog> createState() => _XtreamImportDialogState();
}

class _XtreamImportDialogState extends State<_XtreamImportDialog> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  var _allowPrivateNetwork = false;

  @override
  void dispose() {
    _serverController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Use Xtream login'),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the login issued by a provider you are authorized to use.',
            ),
            const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: KlipaColors.warning,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Use HTTPS when available. HTTP exposes the login and '
                    'stream traffic to the network.',
                    style: TextStyle(
                      color: KlipaColors.foregroundDim,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('xtream-server-field'),
              controller: _serverController,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'https://provider.example:443',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('xtream-username-field'),
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('xtream-password-field'),
              controller: _passwordController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _allowPrivateNetwork,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Allow local/private network addresses'),
              subtitle: const Text(
                'Only enable this for a trusted provider or a server on your LAN.',
              ),
              onChanged: (value) =>
                  setState(() => _allowPrivateNetwork = value ?? false),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Import live TV')),
    ],
  );

  void _submit() {
    final server = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (server.isEmpty || username.isEmpty || password.isEmpty) return;
    final request = _XtreamImportRequest(
      server: server,
      username: username,
      password: password,
      allowPrivateNetwork: _allowPrivateNetwork,
    );
    _serverController.clear();
    _usernameController.clear();
    _passwordController.clear();
    Navigator.pop(context, request);
  }
}
