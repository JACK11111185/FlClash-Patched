import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:tray/tray.dart';

import 'app_localizations.dart';
import 'l10n_labels.dart';
import 'app_ports.dart';
import 'compute.dart';
import 'constant.dart';
import 'keyboard.dart';
import 'provider_reader.dart';
import 'string.dart';
import 'system.dart';
import 'window.dart';

typedef TrayMenuShortcut = ({
  String keyEquivalent,
  Set<TrayMenuItemModifier> modifiers,
});

final Map<PhysicalKeyboardKey, String> _macOSSpecialKeyEquivalents = {
  PhysicalKeyboardKey.enter: '\r',
  PhysicalKeyboardKey.escape: '\u001B',
  PhysicalKeyboardKey.backspace: '\u0008',
  PhysicalKeyboardKey.tab: '\t',
  PhysicalKeyboardKey.space: ' ',
  PhysicalKeyboardKey.quote: '\'',
  PhysicalKeyboardKey.arrowUp: '\uF700',
  PhysicalKeyboardKey.arrowDown: '\uF701',
  PhysicalKeyboardKey.arrowLeft: '\uF702',
  PhysicalKeyboardKey.arrowRight: '\uF703',
  PhysicalKeyboardKey.f1: '\uF704',
  PhysicalKeyboardKey.f2: '\uF705',
  PhysicalKeyboardKey.f3: '\uF706',
  PhysicalKeyboardKey.f4: '\uF707',
  PhysicalKeyboardKey.f5: '\uF708',
  PhysicalKeyboardKey.f6: '\uF709',
  PhysicalKeyboardKey.f7: '\uF70A',
  PhysicalKeyboardKey.f8: '\uF70B',
  PhysicalKeyboardKey.f9: '\uF70C',
  PhysicalKeyboardKey.f10: '\uF70D',
  PhysicalKeyboardKey.f11: '\uF70E',
  PhysicalKeyboardKey.f12: '\uF70F',
  PhysicalKeyboardKey.insert: '\uF727',
  PhysicalKeyboardKey.delete: '\uF728',
  PhysicalKeyboardKey.home: '\uF729',
  PhysicalKeyboardKey.end: '\uF72B',
  PhysicalKeyboardKey.pageUp: '\uF72C',
  PhysicalKeyboardKey.pageDown: '\uF72D',
};

@visibleForTesting
TrayMenuShortcut? getTrayMenuShortcut(HotKeyAction hotKeyAction) {
  final key = hotKeyAction.key;
  if (key == null || hotKeyAction.modifiers.isEmpty) {
    return null;
  }
  final physicalKey = PhysicalKeyboardKey(key);
  final label = physicalKey.label;
  final keyEquivalent =
      _macOSSpecialKeyEquivalents[physicalKey] ??
      (label.length == 1 ? label.toLowerCase() : null);
  if (keyEquivalent == null) {
    return null;
  }
  final modifiers = hotKeyAction.modifiers.map((modifier) {
    return switch (modifier) {
      KeyboardModifier.alt => TrayMenuItemModifier.option,
      KeyboardModifier.capsLock => TrayMenuItemModifier.capsLock,
      KeyboardModifier.control => TrayMenuItemModifier.control,
      KeyboardModifier.fn => TrayMenuItemModifier.function,
      KeyboardModifier.meta => TrayMenuItemModifier.command,
      KeyboardModifier.shift => TrayMenuItemModifier.shift,
    };
  }).toSet();
  return (keyEquivalent: keyEquivalent, modifiers: modifiers);
}

@visibleForTesting
({String? label, TrayMenuItemSublabelStyle style}) getTrayDelayPresentation(
  int? delay, {
  required String loadingLabel,
  required String timeoutLabel,
}) {
  if (delay == null) {
    return (label: null, style: TrayMenuItemSublabelStyle.badge);
  }
  if (delay == 0) {
    return (label: loadingLabel, style: TrayMenuItemSublabelStyle.muted);
  }
  if (delay < 0) {
    return (label: timeoutLabel, style: TrayMenuItemSublabelStyle.destructive);
  }
  return (
    label: '$delay ms',
    style: delay < 600
        ? TrayMenuItemSublabelStyle.badge
        : TrayMenuItemSublabelStyle.warning,
  );
}

@visibleForTesting
String? getTrayGroupSelectionLabel(
  Group group,
  Map<String, String> selectedMap,
) {
  final label = group.getCurrentSelectedName(selectedMap[group.name] ?? '');
  return label.isEmpty ? null : label;
}

String _trayDelayTestKey(String groupName) {
  return 'delay-test:${Uri.encodeComponent(groupName)}';
}

String _trayProxyDelayKey(String groupName, String proxyName) {
  return 'delay:${Uri.encodeComponent(groupName)}:'
      '${Uri.encodeComponent(proxyName)}';
}

class _TrayDelaySnapshot {
  final List<Group> _groups;
  final Map<String, String> _selectedMap;
  final DelayMap _delays;
  final Set<String> _pending;
  final String _defaultTestUrl;
  final Map<String, SelectedProxyState> _selections = {};

  _TrayDelaySnapshot(ProviderReader read)
    : _groups = read(groupsProvider),
      _selectedMap = read(selectedMapProvider),
      _delays = read(delayDataSourceProvider),
      _pending = read(pendingDelayTestsProvider),
      _defaultTestUrl = read(appSettingProvider).testUrl;

  int? delayFor(String proxyName, String? testUrl) {
    final selected = _selections.putIfAbsent(
      proxyName,
      () => computeRealSelectedProxyState(
        proxyName,
        groups: _groups,
        selectedMap: _selectedMap,
      ),
    );
    final effectiveUrl = selected.testUrl.takeFirstValid([
      testUrl,
      _defaultTestUrl,
    ]);
    if (_pending.contains(delayTestKey(effectiveUrl, selected.proxyName))) {
      return 0;
    }
    return _delays[effectiveUrl]?[selected.proxyName];
  }
}

class AppTray implements TrayPort {
  static AppTray? _instance;

  final bool isMacOS;
  final bool isWindows;

  bool _isShutDown = false;
  final Set<String> _testingGroups = {};

  AppTray._internal({required this.isMacOS, required this.isWindows});

  factory AppTray() {
    _instance ??= AppTray._internal(
      isMacOS: system.isMacOS,
      isWindows: system.isWindows,
    );
    return _instance!;
  }

  @visibleForTesting
  factory AppTray.forPlatform({
    required bool isMacOS,
    required bool isWindows,
  }) {
    return AppTray._internal(isMacOS: isMacOS, isWindows: isWindows);
  }

  String get _trayIconSuffix {
    return isWindows ? 'ico' : 'png';
  }

  String getTrayIcon({
    required bool isStart,
    required bool tunEnable,
    bool monochrome = false,
  }) {
    final useSymbolicIcon = isMacOS || (monochrome && !isWindows);
    if (useSymbolicIcon) {
      return isStart
          ? 'assets/images/icon/flclash-symbolic.svg'
          : 'assets/images/icon/flclash-disabled-symbolic.svg';
    }
    if (!isStart) {
      return '${isWindows ? 'assets/images/tray/windows' : 'assets/images/tray/unix'}/status_1.$_trayIconSuffix';
    }
    if (!tunEnable) {
      return '${isWindows ? 'assets/images/tray/windows' : 'assets/images/tray/unix'}/status_2.$_trayIconSuffix';
    }
    return '${isWindows ? 'assets/images/tray/windows' : 'assets/images/tray/unix'}/status_3.$_trayIconSuffix';
  }

  @override
  Future<void> shutdown() async {
    _isShutDown = true;
    await Tray.instance.hide();
  }

  @override
  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  }) async {
    if (_isShutDown) {
      return;
    }
    await Tray.instance.show(
      TraySpec(
        icon: TrayIcon.asset(
          getTrayIcon(
            isStart: trayState.isStart,
            tunEnable: trayState.tunEnable,
            monochrome: trayState.monochromeTrayIcon,
          ),
          isTemplate: isMacOS,
          size: 18,
        ),
        toolTip: appName,
        menu: _buildMenu(trayState: trayState, read: read),
        brightness: read(currentBrightnessProvider),
      ),
    );
    await updateTitle(
      showNetworkSpeed: trayState.showNetworkSpeed,
      isStart: trayState.isStart,
      traffic: traffic,
    );
  }

  Future<void> updateTitle({
    required bool showNetworkSpeed,
    required bool isStart,
    required Traffic traffic,
  }) async {
    if (_isShutDown || !isMacOS) {
      return;
    }
    await Tray.instance.setTitle(showNetworkSpeed ? traffic.trayTitle : '');
  }

  List<TrayMenuItem> _buildMenu({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    final commonAction = read(commonActionProvider.notifier);
    final systemAction = read(systemActionProvider.notifier);
    final setupAction = read(setupActionProvider.notifier);
    final appLocalizations = currentAppLocalizations;

    TrayMenuShortcut? shortcutFor(HotAction action) {
      if (!isMacOS) {
        return null;
      }
      return getTrayMenuShortcut(read(getHotKeyActionProvider(action)));
    }

    final viewShortcut = shortcutFor(HotAction.view);
    final startShortcut = shortcutFor(HotAction.start);
    final nextMode =
        Mode.values[(trayState.mode.index + 1) % Mode.values.length];

    return [
      TrayMenuAction(
        label: appLocalizations.show,
        keyEquivalent: viewShortcut?.keyEquivalent,
        keyEquivalentModifiers: viewShortcut?.modifiers ?? const {},
        onSelectedWithDetails: (details) {
          window?.show(
            activationTimestamp: details.activationTimestamp,
            activationToken: details.activationToken,
          );
        },
      ),
      TrayMenuCheckbox(
        label: trayState.isStart
            ? appLocalizations.stop
            : appLocalizations.start,
        checked: false,
        keyEquivalent: startShortcut?.keyEquivalent,
        keyEquivalentModifiers: startShortcut?.modifiers ?? const {},
        onSelected: commonAction.toggleRunning,
      ),
      const TrayMenuSeparator(),
      for (final mode in Mode.values)
        TrayMenuCheckbox(
          label: mode.label,
          checked: mode == trayState.mode,
          keyEquivalent: mode == nextMode
              ? shortcutFor(HotAction.mode)?.keyEquivalent
              : null,
          keyEquivalentModifiers: mode == nextMode
              ? shortcutFor(HotAction.mode)?.modifiers ?? const {}
              : const {},
          onSelected: () {
            setupAction.changeMode(mode);
          },
        ),
      const TrayMenuSeparator(),
      _buildProfileMenu(read),
      const TrayMenuSeparator(),
      ..._buildGroupMenu(trayState: trayState, read: read),
      TrayMenuCheckbox(
        label: appLocalizations.tun,
        checked: trayState.tunEnable,
        keyEquivalent: shortcutFor(HotAction.tun)?.keyEquivalent,
        keyEquivalentModifiers:
            shortcutFor(HotAction.tun)?.modifiers ?? const {},
        onSelected: systemAction.updateTun,
      ),
      TrayMenuCheckbox(
        label: appLocalizations.systemProxy,
        checked: trayState.systemProxy,
        keyEquivalent: shortcutFor(HotAction.proxy)?.keyEquivalent,
        keyEquivalentModifiers:
            shortcutFor(HotAction.proxy)?.modifiers ?? const {},
        onSelected: systemAction.updateSystemProxy,
      ),
      const TrayMenuSeparator(),
      TrayMenuCheckbox(
        label: appLocalizations.autoLaunch,
        checked: trayState.autoLaunch,
        onSelected: systemAction.updateAutoLaunch,
      ),
      TrayMenuAction(
        label: appLocalizations.copyEnvVar,
        onSelected: () {
          _copyEnv(trayState.port);
        },
      ),
      const TrayMenuSeparator(),
      TrayMenuAction(
        label: appLocalizations.exit,
        onSelected: () {
          systemAction.handleExit();
        },
      ),
    ];
  }

  TrayMenuSubmenu _buildProfileMenu(ProviderReader read) {
    final profiles = read(profilesProvider);
    final currentProfile = read(currentProfileProvider);
    return TrayMenuSubmenu(
      label: currentAppLocalizations.profile,
      sublabel: currentProfile?.realLabel,
      usesCustomView: isMacOS,
      items: [
        for (final profile in profiles)
          TrayMenuCheckbox(
            label: profile.realLabel,
            checked: profile.id == currentProfile?.id,
            onSelected: () {
              if (read(profilesProvider).any((item) => item.id == profile.id)) {
                read(currentProfileIdProvider.notifier).value = profile.id;
              }
            },
          ),
        if (profiles.isNotEmpty) const TrayMenuSeparator(),
        TrayMenuAction(
          label: currentAppLocalizations.sync,
          enabled:
              currentProfile != null &&
              currentProfile.type != ProfileType.file &&
              !read(isUpdatingProvider(currentProfile.updatingKey)),
          onSelected: () async {
            final profile = read(currentProfileProvider);
            if (profile == null ||
                profile.type == ProfileType.file ||
                read(isUpdatingProvider(profile.updatingKey))) {
              return;
            }
            await globalState.safeRun(() async {
              await read(
                profilesActionProvider.notifier,
              ).updateProfile(profile, showLoading: true);
            });
          },
        ),
      ],
    );
  }

  List<TrayMenuItem> _buildGroupMenu({
    required TrayState trayState,
    required ProviderReader read,
  }) {
    if (trayState.groups.isEmpty) {
      return const [];
    }
    final delays = _TrayDelaySnapshot(read);
    return [
      for (final group in trayState.groups)
        _buildGroupMenuItem(
          group: group,
          selectedMap: trayState.selectedMap,
          delays: delays,
          read: read,
        ),
      const TrayMenuSeparator(),
    ];
  }

  TrayMenuSubmenu _buildGroupMenuItem({
    required Group group,
    required Map<String, String> selectedMap,
    required _TrayDelaySnapshot delays,
    required ProviderReader read,
  }) {
    final selectedProxyName = group.getCurrentSelectedName(
      selectedMap[group.name] ?? '',
    );
    return TrayMenuSubmenu(
      key: 'group:${Uri.encodeComponent(group.name)}',
      label: group.name,
      sublabel: getTrayGroupSelectionLabel(group, selectedMap),
      usesCustomView: isMacOS,
      items: [
        TrayMenuAction(
          key: _trayDelayTestKey(group.name),
          label: currentAppLocalizations.delayTest,
          enabled: !_testingGroups.contains(group.name),
          keepsMenuOpen: true,
          onSelected: () {
            unawaited(_testGroupDelay(group, read));
          },
        ),
        const TrayMenuSeparator(),
        for (final proxy in group.all)
          _buildProxyMenuItem(
            group: group,
            proxy: proxy,
            selectedProxyName: selectedProxyName,
            delays: delays,
            read: read,
          ),
      ],
    );
  }

  TrayMenuCheckbox _buildProxyMenuItem({
    required Group group,
    required Proxy proxy,
    required String? selectedProxyName,
    required _TrayDelaySnapshot delays,
    required ProviderReader read,
  }) {
    final presentation = getTrayDelayPresentation(
      delays.delayFor(proxy.name, group.testUrl),
      loadingLabel: '...',
      timeoutLabel: currentAppLocalizations.timeout,
    );
    return TrayMenuCheckbox(
      key: _trayProxyDelayKey(group.name, proxy.name),
      label: proxy.name,
      sublabel: presentation.label,
      sublabelStyle: presentation.style,
      usesCustomView: isMacOS,
      checked: selectedProxyName == proxy.name,
      onSelected: () {
        read(
          proxiesActionProvider.notifier,
        ).changeProxy(groupName: group.name, proxyName: proxy.name);
      },
    );
  }

  Future<void> _testGroupDelay(Group group, ProviderReader read) async {
    if (!_testingGroups.add(group.name)) {
      return;
    }
    await Tray.instance.updateMenuItems([
      TrayMenuItemUpdate(key: _trayDelayTestKey(group.name), enabled: false),
    ]);
    try {
      await read(proxiesActionProvider.notifier).delayTest(
        group.all,
        group.testUrl,
        const Duration(seconds: 1),
        (proxyNames) => _updateGroupDelays(group, read, proxyNames),
      );
    } finally {
      _testingGroups.remove(group.name);
      await Tray.instance.updateMenuItems([
        TrayMenuItemUpdate(key: _trayDelayTestKey(group.name), enabled: true),
      ]);
    }
  }

  Future<void> _updateGroupDelays(
    Group group,
    ProviderReader read,
    Set<String> proxyNames,
  ) async {
    final updates = <TrayMenuItemUpdate>[];
    final delays = _TrayDelaySnapshot(read);
    for (final proxy in group.all.where(
      (proxy) => proxyNames.contains(proxy.name),
    )) {
      final presentation = getTrayDelayPresentation(
        delays.delayFor(proxy.name, group.testUrl),
        loadingLabel: '...',
        timeoutLabel: currentAppLocalizations.timeout,
      );
      final label = presentation.label;
      if (label == null) {
        continue;
      }
      updates.add(
        TrayMenuItemUpdate(
          key: _trayProxyDelayKey(group.name, proxy.name),
          sublabel: label,
          sublabelStyle: presentation.style,
        ),
      );
    }
    await Tray.instance.updateMenuItems(updates);
  }

  Future<void> _copyEnv(int port) async {
    final url = 'http://127.0.0.1:$port';

    final cmdline = isWindows
        ? '\$env:http_proxy="$url"; \$env:https_proxy="$url"; '
              '\$env:all_proxy="$url"; '
              '\$env:no_proxy="localhost,::1,127.0.0.1"'
        : 'export http_proxy="$url"; export https_proxy="$url"; '
              'export all_proxy="$url"; '
              'export no_proxy="localhost,::1,127.0.0.1"';

    await Clipboard.setData(ClipboardData(text: cmdline));
  }
}

final appTray = system.isDesktop ? AppTray() : null;
