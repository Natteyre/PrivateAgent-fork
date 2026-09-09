import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:intl/intl.dart';

import '../../models/task_history_entry.dart';
import '../../services/screen_automation_service.dart';
import '../../services/settings_service.dart';
import '../../services/task_executor.dart';
import '../../services/voice_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/status_chip.dart';
import '../history/task_history_screen.dart';
import '../sessions/session_detail_screen.dart';
import '../settings/settings_screen.dart';

/// Main screen: live task transcript, task input with voice, overlay toggle.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _executor = TaskExecutor.instance;
  final _automation = ScreenAutomationService.instance;
  final _voice = VoiceService.instance;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  bool _serviceEnabled = false;
  bool _overlayActive = false;
  bool _listening = false;
  AppMode _mode = AppMode.genie;

  /// True while either an agent task or a chat reply is in flight.
  bool get _busy => _executor.isBusy || _executor.isChatBusy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _executor.addListener(_onExecutorUpdate);
    _mode = SettingsService.instance.appMode;
    _refreshStates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _executor.removeListener(_onExecutorUpdate);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStates();
  }

  Future<void> _refreshStates() async {
    final enabled = await _automation.isServiceEnabled();
    var overlay = false;
    try {
      overlay = await FlutterOverlayWindow.isActive();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _serviceEnabled = enabled;
        _overlayActive = overlay;
      });
    }
  }

  void _onExecutorUpdate() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _submit(String text) {
    final goal = text.trim();
    if (goal.isEmpty || _busy) return;
    _inputController.clear();
    if (_mode == AppMode.genie) {
      _executor.executeTask(goal);
    } else {
      _executor.sendChatMessage(goal);
    }
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _voice.stopListening();
      setState(() => _listening = false);
      return;
    }
    await _voice.startListening(
      onResult: (String text) {
        if (!mounted) return;
        setState(() {
          _inputController.text = text;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _listening = false);
      },
    );
    setState(() => _listening = true);
  }

  Future<void> _toggleOverlay() async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      } else {
        final granted = await FlutterOverlayWindow.isPermissionGranted();
        if (!granted) {
          final ok = await FlutterOverlayWindow.requestPermission() ?? false;
          if (!ok) return;
        }
        await FlutterOverlayWindow.showOverlay(
          height: 120,
          width: 120,
          alignment: OverlayAlignment.centerRight,
          flag: OverlayFlag.defaultFlag,
          overlayTitle: 'PrivateAgent',
          overlayContent: 'Agent bubble active',
          enableDrag: true,
          positionGravity: PositionGravity.auto,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Overlay error: $e')));
      }
    }
    await _refreshStates();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      drawer: _sessionsDrawer(theme),
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 20,
              color: theme.brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF1E293B),
            ),
            children: [
              TextSpan(
                text: 'Private',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                  letterSpacing: -0.5,
                ),
              ),
              const TextSpan(
                text: 'Agent',
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _overlayActive
                ? 'Hide floating bubble'
                : 'Show floating bubble',
            onPressed: _toggleOverlay,
            icon: Icon(
              _overlayActive ? Icons.bubble_chart : Icons.bubble_chart_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Task history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TaskHistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_serviceEnabled && _mode == AppMode.genie)
            _serviceWarning(theme),
          if (_executor.isBusy) _activeTaskBar(theme),
          Expanded(child: _transcript(theme)),
          _modeSwitcher(theme),
          _inputBar(theme),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Sessions sidebar (navigation drawer)
  // ------------------------------------------------------------------

  Widget _sessionsDrawer(ThemeData theme) {
    final entries = _executor.historyEntries;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/icon/genie_logo.png',
                        width: 26,
                        height: 26,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'PrivateAgent',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chat sessions',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_executor.isBusy)
              ListTile(
                dense: true,
                leading: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                title: Text(
                  _executor.currentGoal ?? 'Running task…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Live session in progress',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text(
                'New chat',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Clear the live transcript',
                style: TextStyle(fontSize: 11),
              ),
              enabled: !_executor.isBusy,
              onTap: () {
                Navigator.of(context).pop();
                _executor.clearTranscript();
              },
            ),
            const Divider(indent: 12, endIndent: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                'RECENT SESSIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Text(
                  'No saved sessions yet.\nRun a task and it will appear here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            for (final entry in entries) _sessionTile(theme, entry),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sessionTile(ThemeData theme, TaskHistoryEntry entry) {
    final (icon, color) = switch (entry.status) {
      TaskStatus.success => (Icons.check_circle_outline, Colors.green),
      TaskStatus.failed => (Icons.error_outline, AppTheme.danger),
      TaskStatus.cancelled => (
        Icons.stop_circle_outlined,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, color: color, size: 22),
      title: Text(
        entry.goal,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        DateFormat.MMMd().add_Hm().format(entry.startedAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        tooltip: 'Delete session',
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () => _executor.deleteHistoryEntry(entry.id),
      ),
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(entryId: entry.id),
          ),
        );
      },
    );
  }

  Widget _serviceWarning(ThemeData theme) {
    return Material(
      color: AppTheme.danger.withValues(alpha: 0.12),
      child: ListTile(
        dense: true,
        leading: const Icon(
          Icons.warning_amber_rounded,
          color: AppTheme.danger,
        ),
        title: const Text(
          'Accessibility service is off',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: const Text(
          'Tap to open settings and enable it',
          style: TextStyle(fontSize: 12),
        ),
        onTap: () => _automation.openAccessibilitySettings(),
      ),
    );
  }

  Widget _activeTaskBar(ThemeData theme) {
    final maxSteps = SettingsService.instance.maxSteps;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  strokeWidth: 3,
                  value: maxSteps == 0 ? null : _executor.step / maxSteps,
                ),
                Text(
                  '${_executor.step}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _executor.isPaused ? 'Paused' : 'Running task',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  _executor.currentGoal ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _executor.isPaused ? 'Resume' : 'Pause',
            icon: Icon(
              _executor.isPaused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
            ),
            onPressed: () =>
                _executor.isPaused ? _executor.resume() : _executor.pause(),
          ),
          IconButton(
            tooltip: 'Cancel task',
            icon: const Icon(Icons.stop_rounded, color: AppTheme.danger),
            onPressed: _executor.cancel,
          ),
        ],
      ),
    );
  }

  Widget _transcript(ThemeData theme) {
    if (_executor.logs.isEmpty) {
      final isGenie = _mode == AppMode.genie;
      final isDark = theme.brightness == Brightness.dark;
      return _buildEmptyState(isDark, isGenie, theme);
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _executor.logs.length,
      itemBuilder: (_, i) => ChatBubble(message: _executor.logs[i]),
    );
  }

  Widget _buildEmptyState(bool isDark, bool isGenie, ThemeData theme) {
    final time = DateTime.now();
    String timeGreeting = 'Hello';
    if (time.hour >= 5 && time.hour < 12) {
      timeGreeting = 'Hello, good morning.';
    } else if (time.hour >= 12 && time.hour < 17) {
      timeGreeting = 'Hello, good afternoon.';
    } else if (time.hour >= 17 && time.hour < 22) {
      timeGreeting = 'Hello, good evening.';
    } else {
      timeGreeting = 'Hello.';
    }

    final suggestions = isGenie
        ? [
            'Open YouTube and search for cats',
            'Call Mom',
            'Set volume to 80%',
            "What's on my screen?",
          ]
        : [
            'Write a professional email',
            'Explain quantum computing simply',
            'Brainstorm mobile app ideas',
            'Write a poem about robots',
          ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeGreeting,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w300,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                      letterSpacing: -1.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'How can I help you?',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                      letterSpacing: -1.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SUGGESTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF475569),
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return ActionChip(
                    label: Text(
                      suggestions[index],
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF475569),
                      ),
                    ),
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                    onPressed: () {
                      _inputController.text = suggestions[index];
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar(ThemeData theme) {
    final isGenie = _mode == AppMode.genie;
    final isDark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withOpacity(0.08),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        enabled: !_busy,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _submit,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _busy
                              ? (isGenie ? 'Genie is working…' : 'Thinking…')
                              : (isGenie
                                    ? 'Describe a task…'
                                    : 'Message…'),
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    // Voice input button
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        tooltip: 'Voice input',
                        onPressed: _busy ? null : _toggleListening,
                        icon: Icon(
                          _listening ? Icons.mic : Icons.mic_none,
                          color: _listening ? AppTheme.danger : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Solid Send button
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
              child: IconButton(
                tooltip: isGenie ? 'Run task' : 'Send',
                onPressed: _busy ? null : () => _submit(_inputController.text),
                icon: const Icon(
                  Icons.send_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Genie (agent) / Chat mode switcher shown above the input bar.
  Widget _modeSwitcher(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildModeButton(
            AppMode.genie,
            'Genie',
            Icons.auto_awesome,
            isDark,
            theme,
          ),
          const SizedBox(width: 12),
          _buildModeButton(
            AppMode.chat,
            'Chat',
            Icons.chat_bubble_outline,
            isDark,
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
    AppMode modeId,
    String label,
    IconData icon,
    bool isDark,
    ThemeData theme,
  ) {
    final isSelected = _mode == modeId;

    return GestureDetector(
      onTap: _busy
          ? null
          : () {
              setState(() => _mode = modeId);
              SettingsService.instance.setAppMode(modeId);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: isSelected
              ? theme.colorScheme.primary
              : Colors.transparent,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? Colors.white
                  : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF475569)),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF475569)),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
