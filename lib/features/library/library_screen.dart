import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart';
import '../../domain/channel.dart';
import '../../domain/channel_schedule.dart';
import '../../domain/library_source.dart';
import '../../domain/playlist_source.dart';
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
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          unawaited(controller.refreshActiveSource());
        },
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
                  onRenameSource: (source) => _renameSource(source, controller),
                  onRefreshSource: (source) =>
                      unawaited(controller.refreshSource(source.id)),
                  onDeleteSource: (source) => _deleteSource(source, controller),
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

  Future<void> _renameSource(
    LibrarySource source,
    LibraryController controller,
  ) async {
    final name = await _showRenameSourceDialog(context, source);
    if (name == null || !mounted) return;
    await controller.renameSource(source.id, name);
  }

  Future<void> _deleteSource(
    LibrarySource source,
    LibraryController controller,
  ) async {
    final confirmed = await _showDeleteSourceDialog(context, source);
    if (confirmed != true || !mounted) return;
    final state = ref.read(libraryControllerProvider);
    if (state.selectedChannel?.sourceId == source.id) {
      await _playerController.stop();
    }
    if (!mounted) return;
    await controller.deleteSource(source.id);
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
                    'Your library is encrypted on this desktop. No telemetry is sent.',
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
    required this.onRenameSource,
    required this.onRefreshSource,
    required this.onDeleteSource,
  });

  final LibraryState state;
  final LibraryController controller;
  final FocusNode searchFocus;
  final PlayerPaneController playerController;
  final VoidCallback onReset;
  final ValueChanged<LibrarySource> onRenameSource;
  final ValueChanged<LibrarySource> onRefreshSource;
  final ValueChanged<LibrarySource> onDeleteSource;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final expandedSources = constraints.maxWidth >= 1100;
      final compact = constraints.maxWidth < 980;
      return Row(
        children: [
          _SourceRail(
            state: state,
            controller: controller,
            expanded: expandedSources,
            onReset: onReset,
            onRenameSource: onRenameSource,
            onRefreshSource: onRefreshSource,
            onDeleteSource: onDeleteSource,
          ),
          SizedBox(
            width: compact ? 280 : 340,
            child: _ChannelBrowser(
              state: state,
              controller: controller,
              searchFocus: searchFocus,
              showSourceFilter: !expandedSources,
              onRenameSource: onRenameSource,
              onRefreshSource: onRefreshSource,
              onDeleteSource: onDeleteSource,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: PlayerPane(
              channel: state.selectedChannel,
              resumeChannel: state.resumeChannel,
              onResume: state.resumeChannel == null
                  ? null
                  : () => controller.select(state.resumeChannel!),
              controller: playerController,
            ),
          ),
        ],
      );
    },
  );
}

class _SourceRail extends StatelessWidget {
  const _SourceRail({
    required this.state,
    required this.controller,
    required this.expanded,
    required this.onReset,
    required this.onRenameSource,
    required this.onRefreshSource,
    required this.onDeleteSource,
  });

  final LibraryState state;
  final LibraryController controller;
  final bool expanded;
  final VoidCallback onReset;
  final ValueChanged<LibrarySource> onRenameSource;
  final ValueChanged<LibrarySource> onRefreshSource;
  final ValueChanged<LibrarySource> onDeleteSource;

  @override
  Widget build(BuildContext context) => Container(
    width: expanded ? 236 : 72,
    color: KlipaColors.inkRaised,
    child: expanded ? _expanded(context) : _compact(context),
  );

  Widget _expanded(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 12, 14),
        child: Row(
          children: [
            _BrandMark(size: 34),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Klipa Player',
                maxLines: 1,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      const SizedBox(height: 10),
      _SourceListTile(
        key: const Key('source-all'),
        name: 'All channels',
        count: state.channels.length,
        selected: state.selectedSourceId == null,
        icon: Icons.live_tv_rounded,
        onPressed: () => controller.filterSource(null),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 12, 7),
        child: Text(
          'SOURCES',
          style: TextStyle(
            color: KlipaColors.foregroundDim,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: state.sources.length,
          itemBuilder: (context, index) {
            final source = state.sources[index];
            final channelCount = state.channels
                .where((channel) => channel.sourceId == source.id)
                .length;
            return _SourceListTile(
              key: ValueKey('source-${source.id}'),
              name: source.name,
              count: channelCount,
              selected: state.selectedSourceId == source.id,
              icon: _sourceIcon(source.kind),
              onPressed: () => controller.filterSource(source.id),
              menu: PopupMenuButton<_SourceAction>(
                tooltip: 'Manage ${source.name}',
                enabled: !state.isImporting,
                onSelected: (action) => switch (action) {
                  _SourceAction.refresh => onRefreshSource(source),
                  _SourceAction.rename => onRenameSource(source),
                  _SourceAction.delete => onDeleteSource(source),
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _SourceAction.refresh,
                    child: Text('Refresh'),
                  ),
                  PopupMenuItem(
                    value: _SourceAction.rename,
                    child: Text('Rename'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: _SourceAction.delete,
                    child: Text('Delete'),
                  ),
                ],
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
              ),
            );
          },
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _SmallRailButton(
              tooltip: 'Add local playlist',
              icon: Icons.playlist_add_rounded,
              onPressed: state.isImporting ? null : controller.importFile,
            ),
            _SmallRailButton(
              tooltip: 'Add playlist URL',
              icon: Icons.add_link_rounded,
              onPressed: state.isImporting
                  ? null
                  : () => _showUrlDialog(context, controller),
            ),
            _SmallRailButton(
              tooltip: 'Use Xtream login',
              icon: Icons.key_rounded,
              onPressed: state.isImporting
                  ? null
                  : () => _showXtreamDialog(context, controller),
            ),
            _SmallRailButton(
              tooltip: 'Reset app data',
              icon: Icons.delete_outline_rounded,
              onPressed: state.isImporting ? null : onReset,
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 5, 16, 14),
        child: Row(
          children: [
            Icon(
              Icons.phone_android_rounded,
              size: 16,
              color: KlipaColors.foregroundDim,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Klipa on phone & TV',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: KlipaColors.foregroundDim,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _compact(BuildContext context) => Column(
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
  );
}

enum _SourceAction { refresh, rename, delete }

IconData _sourceIcon(PlaylistSourceKind kind) => switch (kind) {
  PlaylistSourceKind.localFile => Icons.description_outlined,
  PlaylistSourceKind.remoteUrl => Icons.link_rounded,
  PlaylistSourceKind.xtream => Icons.key_rounded,
};

class _SourceListTile extends StatelessWidget {
  const _SourceListTile({
    required this.name,
    required this.count,
    required this.selected,
    required this.icon,
    required this.onPressed,
    this.menu,
    super.key,
  });

  final String name;
  final int count;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;
  final Widget? menu;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: Material(
      color: selected ? KlipaColors.inkHover : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(
                icon,
                size: 18,
                color: selected
                    ? KlipaColors.indigo
                    : KlipaColors.foregroundDim,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? KlipaColors.foreground
                        : KlipaColors.foregroundMuted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  color: KlipaColors.foregroundDim,
                  fontSize: 10,
                ),
              ),
              if (menu case final menu?)
                SizedBox(width: 36, height: 36, child: menu)
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SmallRailButton extends StatelessWidget {
  const _SmallRailButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
    ),
  );
}

class _LibraryDropdown<T> extends StatelessWidget {
  const _LibraryDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: KlipaColors.inkRaised,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: KlipaColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(8),
          dropdownColor: KlipaColors.inkRaised,
          icon: const Icon(Icons.expand_more_rounded, size: 19),
          items: items,
          onChanged: onChanged,
        ),
      ),
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
    required this.showSourceFilter,
    required this.onRenameSource,
    required this.onRefreshSource,
    required this.onDeleteSource,
  });

  final LibraryState state;
  final LibraryController controller;
  final FocusNode searchFocus;
  final bool showSourceFilter;
  final ValueChanged<LibrarySource> onRenameSource;
  final ValueChanged<LibrarySource> onRefreshSource;
  final ValueChanged<LibrarySource> onDeleteSource;

  @override
  Widget build(BuildContext context) {
    final channels = state.visibleChannels;
    final groups = state.availableGroups;
    final filtered =
        state.query.trim().isNotEmpty ||
        state.selectedGroup != null ||
        state.selectedSourceId != null ||
        state.favoritesOnly;
    final managedSource = switch (state.selectedSourceId) {
      final id? => state.sources.where((source) => source.id == id).firstOrNull,
      _ when state.sources.length == 1 => state.sources.single,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Live TV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Text(
                filtered
                    ? '${channels.length}/${state.channels.length}'
                    : '${state.channels.length}',
                style: const TextStyle(color: KlipaColors.foregroundDim),
              ),
              const SizedBox(width: 7),
              IconButton(
                key: const Key('favorites-filter'),
                tooltip: state.favoritesOnly
                    ? 'Show all channels'
                    : 'Show favorites only',
                isSelected: state.favoritesOnly,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    controller.setFavoritesOnly(!state.favoritesOnly),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(36),
                  maximumSize: const Size.square(36),
                  backgroundColor: state.favoritesOnly
                      ? KlipaColors.indigo.withValues(alpha: 0.18)
                      : Colors.transparent,
                  foregroundColor: state.favoritesOnly
                      ? KlipaColors.indigo
                      : KlipaColors.foregroundDim,
                ),
                icon: Icon(
                  state.favoritesOnly
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        if (showSourceFilter && state.sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: _LibraryDropdown<String?>(
                    key: const Key('source-filter'),
                    value: state.selectedSourceId,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All sources'),
                      ),
                      for (final source in state.sources)
                        DropdownMenuItem(
                          value: source.id,
                          child: Text(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: controller.filterSource,
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<_SourceAction>(
                  key: const Key('compact-source-actions'),
                  tooltip: managedSource == null
                      ? 'Select a source to manage'
                      : 'Manage ${managedSource.name}',
                  enabled: managedSource != null && !state.isImporting,
                  onSelected: (action) {
                    final source = managedSource;
                    if (source == null) return;
                    switch (action) {
                      case _SourceAction.refresh:
                        onRefreshSource(source);
                      case _SourceAction.rename:
                        onRenameSource(source);
                      case _SourceAction.delete:
                        onDeleteSource(source);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _SourceAction.refresh,
                      child: Text('Refresh'),
                    ),
                    PopupMenuItem(
                      value: _SourceAction.rename,
                      child: Text('Rename'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _SourceAction.delete,
                      child: Text('Delete'),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded, size: 18),
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
                      schedule: state.scheduleFor(channel),
                      selected:
                          channel.id == state.selectedChannel?.id &&
                          channel.sourceId == state.selectedChannel?.sourceId,
                      favorite: state.isFavorite(channel),
                      onPressed: () => controller.select(channel),
                      onToggleFavorite: () =>
                          unawaited(controller.toggleFavorite(channel)),
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
    required this.schedule,
    required this.selected,
    required this.favorite,
    required this.onPressed,
    required this.onToggleFavorite,
  });

  final Channel channel;
  final ChannelSchedule? schedule;
  final bool selected;
  final bool favorite;
  final VoidCallback onPressed;
  final VoidCallback onToggleFavorite;

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
                    if (schedule?.current?.title ?? channel.group
                        case final subtitle?) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: KlipaColors.foregroundDim,
                          fontSize: 10,
                          letterSpacing: schedule?.current == null ? 0.5 : 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Semantics(
                button: true,
                toggled: favorite,
                label: favorite
                    ? 'Remove ${channel.name} from favorites'
                    : 'Add ${channel.name} to favorites',
                child: IconButton(
                  key: Key('favorite-${channel.sourceId}-${channel.id}'),
                  tooltip: favorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    favorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: favorite
                        ? KlipaColors.indigo
                        : KlipaColors.foregroundDim,
                    size: 19,
                  ),
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

Future<String?> _showRenameSourceDialog(
  BuildContext context,
  LibrarySource source,
) => showDialog<String>(
  context: context,
  builder: (context) => _RenameSourceDialog(source: source),
);

class _RenameSourceDialog extends StatefulWidget {
  const _RenameSourceDialog({required this.source});

  final LibrarySource source;

  @override
  State<_RenameSourceDialog> createState() => _RenameSourceDialogState();
}

class _RenameSourceDialogState extends State<_RenameSourceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.source.name,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename source'),
    content: TextField(
      key: const Key('source-name-field'),
      controller: _controller,
      autofocus: true,
      maxLength: 120,
      textInputAction: TextInputAction.done,
      onSubmitted: _submit,
      decoration: const InputDecoration(labelText: 'Source name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('confirm-rename-source'),
        onPressed: () => _submit(_controller.text),
        child: const Text('Rename'),
      ),
    ],
  );

  void _submit(String value) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) Navigator.pop(context, normalized);
  }
}

Future<bool?> _showDeleteSourceDialog(
  BuildContext context,
  LibrarySource source,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Delete source?'),
    content: Text(
      'Delete “${source.name}” and its cached channels, saved login, '
      'favorites, and guide data from this PC?\n\nThis cannot be undone.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('confirm-delete-source'),
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Delete source'),
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
    guideUrl: request.guideUrl,
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
    this.guideUrl,
  });

  final String url;
  final bool allowPrivateNetwork;
  final String? guideUrl;
}

class _UrlImportDialog extends StatefulWidget {
  const _UrlImportDialog();

  @override
  State<_UrlImportDialog> createState() => _UrlImportDialogState();
}

class _UrlImportDialogState extends State<_UrlImportDialog> {
  final _controller = TextEditingController();
  final _guideController = TextEditingController();
  var _allowPrivateNetwork = false;

  @override
  void dispose() {
    _controller.dispose();
    _guideController.dispose();
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
          TextField(
            key: const Key('guide-url-field'),
            controller: _guideController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'XMLTV guide address (optional)',
              hintText: 'https://provider.example/guide.xml',
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
      _UrlImportRequest(
        url: value,
        guideUrl: _guideController.text.trim().isEmpty
            ? null
            : _guideController.text.trim(),
        allowPrivateNetwork: _allowPrivateNetwork,
      ),
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
