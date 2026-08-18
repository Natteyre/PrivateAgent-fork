import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interaction mode of the home screen.
///
/// - [genie]: agent mode — tasks are executed on the device via the
///   observe → think → act loop (accessibility service required).
/// - [chat]: plain chatbot mode — messages get a conversational LLM reply,
///   no screen reading and no device actions.
enum AppMode { genie, chat }

/// Central, observable store for all user-configurable settings.
///
/// Backed by SharedPreferences. Access via [SettingsService.instance] after
/// calling [init] once at app start.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;

  bool get isReady => _prefs != null;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ------------------------------------------------------------------
  // AI provider
  // ------------------------------------------------------------------

  /// Well-known OpenAI-compatible providers.
  static const Map<String, ({String label, String baseUrl, String model})>
  providers = {
    'deepseek': (
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
    ),
    'openai': (
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
    ),
    'gemini': (
      label: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-2.0-flash',
    ),
    'openrouter': (
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openai/gpt-4o-mini',
    ),
    'nvidia': (
      label: 'NVIDIA NIM',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'meta/llama-3.3-70b-instruct',
    ),
    'ollama': (
      label: 'Ollama (local)',
      baseUrl: 'http://127.0.0.1:11434/v1',
      model: 'llama3.2',
    ),
    'custom': (label: 'Custom (OpenAI-compatible)', baseUrl: '', model: ''),
  };

  String get provider => _prefs?.getString('ai_provider') ?? 'deepseek';
  Future<void> setProvider(String value) async {
    await _prefs?.setString('ai_provider', value);
    final preset = providers[value];
    if (preset != null && preset.baseUrl.isNotEmpty) {
      await _prefs?.setString('ai_base_url', preset.baseUrl);
      await _prefs?.setString('ai_model', preset.model);
    }
    notifyListeners();
  }

  String get baseUrl =>
      _prefs?.getString('ai_base_url') ??
      providers[provider]?.baseUrl ??
      providers['deepseek']!.baseUrl;
  Future<void> setBaseUrl(String value) async {
    await _prefs?.setString('ai_base_url', value.trim());
    notifyListeners();
  }

  String get apiKey => _prefs?.getString('ai_api_key') ?? '';
  Future<void> setApiKey(String value) async {
    await _prefs?.setString('ai_api_key', value.trim());
    notifyListeners();
  }

  String get model =>
      _prefs?.getString('ai_model') ??
      providers[provider]?.model ??
      'deepseek-chat';
  Future<void> setModel(String value) async {
    await _prefs?.setString('ai_model', value.trim());
    notifyListeners();
  }

  /// Defaults to 2048 so reasoning models (which burn completion tokens on
  /// hidden thinking before answering) still have budget left for the reply.
  int get maxTokens => _prefs?.getInt('ai_max_tokens') ?? 2048;
  Future<void> setMaxTokens(int value) async {
    await _prefs?.setInt('ai_max_tokens', value.clamp(128, 16384));
    notifyListeners();
  }

  double get temperature => _prefs?.getDouble('ai_temperature') ?? 0.2;
  Future<void> setTemperature(double value) async {
    await _prefs?.setDouble('ai_temperature', value.clamp(0.0, 2.0));
    notifyListeners();
  }

  bool get useSystemPrompt => _prefs?.getBool('ai_use_system_prompt') ?? true;
  Future<void> setUseSystemPrompt(bool value) async {
    await _prefs?.setBool('ai_use_system_prompt', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Agent loop
  // ------------------------------------------------------------------

  int get maxSteps => _prefs?.getInt('agent_max_steps') ?? 15;
  Future<void> setMaxSteps(int value) async {
    await _prefs?.setInt('agent_max_steps', value.clamp(3, 40));
    notifyListeners();
  }

  /// Delay between loop iterations, lets the UI settle after each action.
  int get stepDelayMs => _prefs?.getInt('agent_step_delay_ms') ?? 1200;
  Future<void> setStepDelayMs(int value) async {
    await _prefs?.setInt('agent_step_delay_ms', value.clamp(200, 10000));
    notifyListeners();
  }

  bool get skillsEnabled => _prefs?.getBool('agent_skills_enabled') ?? true;
  Future<void> setSkillsEnabled(bool value) async {
    await _prefs?.setBool('agent_skills_enabled', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Telegram
  // ------------------------------------------------------------------

  bool get telegramEnabled => _prefs?.getBool('telegram_enabled') ?? false;
  Future<void> setTelegramEnabled(bool value) async {
    await _prefs?.setBool('telegram_enabled', value);
    notifyListeners();
  }

  String get telegramToken => _prefs?.getString('telegram_token') ?? '';
  Future<void> setTelegramToken(String value) async {
    await _prefs?.setString('telegram_token', value.trim());
    notifyListeners();
  }

  /// Chat ids allowed to control the device. Empty = the first chat that
  /// messages the bot becomes the owner (and is remembered).
  List<String> get telegramAllowedChats =>
      _prefs?.getStringList('telegram_allowed_chats') ?? const [];
  Future<void> setTelegramAllowedChats(List<String> value) async {
    await _prefs?.setStringList('telegram_allowed_chats', value);
    notifyListeners();
  }

  String get telegramOwnerChatId =>
      _prefs?.getString('telegram_owner_chat') ?? '';
  Future<void> setTelegramOwnerChatId(String value) async {
    await _prefs?.setString('telegram_owner_chat', value.trim());
    notifyListeners();
  }

  int get telegramUpdateOffset => _prefs?.getInt('telegram_offset') ?? 0;
  Future<void> setTelegramUpdateOffset(int value) async {
    await _prefs?.setInt('telegram_offset', value);
  }

  // ------------------------------------------------------------------
  // ------------------------------------------------------------------
  // Interaction mode
  // ------------------------------------------------------------------

  /// Whether the home screen sends messages to the agent loop
  /// ([AppMode.genie]) or treats them as plain conversation
  /// ([AppMode.chat]).
  AppMode get appMode {
    final raw = _prefs?.getString('ui_app_mode') ?? 'genie';
    return AppMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => AppMode.genie,
    );
  }

  Future<void> setAppMode(AppMode mode) async {
    await _prefs?.setString('ui_app_mode', mode.name);
    notifyListeners();
  }

  // Appearance, voice & onboarding
  // ------------------------------------------------------------------

  ThemeMode get themeMode {
    final raw = _prefs?.getString('ui_theme_mode') ?? 'system';
    return ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString('ui_theme_mode', mode.name);
    notifyListeners();
  }

  bool get onboardingComplete =>
      _prefs?.getBool('onboarding_complete') ?? false;
  Future<void> setOnboardingComplete(bool value) async {
    await _prefs?.setBool('onboarding_complete', value);
    notifyListeners();
  }

  /// Whether the assistant should speak results aloud via TTS.
  bool get voiceFeedback => _prefs?.getBool('voice_feedback') ?? false;
  Future<void> setVoiceFeedback(bool value) async {
    await _prefs?.setBool('voice_feedback', value);
    notifyListeners();
  }
}
