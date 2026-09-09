# PrivateAgent — Android AI Assistant Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build a full-featured Android AI assistant with persistent memory, personality, voice interaction, and automation capabilities.

**Architecture:** Fork-based (AbuZar-Ansarii/PrivateAgent) with bugfixes applied. Features adapted from Kai-custom (Kotlin) to Flutter. Modular design: Memory Store → Auto Learning → Persona → Voice → Skills → Automation.

**Tech Stack:** Flutter/Dart, Kotlin (native Android), SQLite, WorkManager, Gemini/DeepSeek/OpenAI APIs, AccessibilityService.

**Device:** Huawei P30 Pro, Android 10, no root.

---

## Project Status

### ✅ COMPLETED (Phase 0)

| Task | Status | Files Modified |
|------|--------|----------------|
| AccessibilityService memory leak fix | ✅ DONE | `AgentAccessibilityService.kt` |
| Accessibility Config flagDefault | ✅ DONE | `accessibility_service_config.xml` |
| Voice Service from original | ✅ DONE | `voice_service.dart` |
| Home Screen voice integration | ✅ DONE | `home_screen.dart` |
| Theme match original colors | ✅ DONE | `app_theme.dart` |
| Package name alignment | ✅ DONE | `build.gradle.kts`, `AndroidManifest.xml` |
| Dependencies alignment | ✅ DONE | `pubspec.yaml` |
| Research: Kai-custom analysis | ✅ DONE | Documentation complete |

---

## Implementation Plan

### 🔴 PHASE 1: Core Memory & Personality (Week 1-2)

**Priority: CRITICAL** — Foundation for all other features.

#### Task 1.1: Memory Entry Model

**Objective:** Create the data model for memory entries.

**Files:**
- Create: `lib/models/memory_entry.dart`

**Spec:**
```dart
enum MemoryCategory { general, learning, error, preference }

class MemoryEntry {
  final String key;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MemoryCategory category;
  final int hitCount;
  final String? source;
  final bool isProtected;

  // Methods: toMap(), fromMap(), reinforce(), etc.
}
```

**Validation:** Unit tests for serialization, deserialization, reinforce().

---

#### Task 1.2: Memory Store Interface

**Objective:** Define the contract for memory storage operations.

**Files:**
- Create: `lib/services/memory/memory_store.dart`

**Spec:**
```dart
abstract class MemoryStore {
  Future<void> init();
  Future<MemoryEntry> store(String key, String content, MemoryCategory category, {String? source});
  Future<MemoryEntry?> updateContent(String key, String content);
  Future<MemoryEntry?> reinforceMemory(String key);
  Future<bool> forget(String key);
  Future<void> deleteAll({bool force = false});
  Future<MemoryEntry> storeProtected(String key, String content, MemoryCategory category, {String? source});
  List<MemoryEntry> getUserMemories({int max = 1000});
  List<MemoryEntry> getBehaviorMemories();
  bool containsKey(String key);
}
```

**Validation:** Interface compiles, no implementation yet.

---

#### Task 1.3: SQLite Memory Store Implementation

**Objective:** Implement memory store using SQLite for persistence.

**Files:**
- Create: `lib/services/memory/sqlite_memory_store.dart`
- Modify: `pubspec.yaml` (add sqflite, path)

**Spec:**
- Table: `memories` (key, content, created_at, updated_at, category, hit_count, source, protected)
- Auto-create table on init()
- Index on key for O(1) lookup
- Implement all interface methods

**Validation:** Integration tests with real SQLite database.

---

#### Task 1.4: Memory Provider (State Management)

**Objective:** Integrate memory store with app state using ChangeNotifier.

**Files:**
- Create: `lib/providers/memory_provider.dart`

**Spec:**
```dart
class MemoryProvider extends ChangeNotifier {
  final MemoryStore _store;
  List<MemoryEntry> _userMemories = [];
  List<MemoryEntry> _behaviorMemories = [];

  // Methods: loadMemories(), storeMemory(), reinforceMemory(), etc.
  // Auto-notifyListeners() on changes
}
```

**Validation:** Unit tests for state changes, widget tests for UI integration.

---

#### Task 1.5: Auto Memory Learner

**Objective:** Implement automatic fact extraction from conversations.

**Files:**
- Create: `lib/services/memory/auto_memory_learner.dart`

**Spec:**
```dart
class AutoMemoryLearner {
  final MemoryStore _memoryStore;
  final AiService _aiService;
  int _exchangeCount = 0;
  static const int EXTRACTION_INTERVAL = 5;

  void onExchangeComplete() {
    _exchangeCount++;
    if (_exchangeCount >= EXTRACTION_INTERVAL) {
      _exchangeCount = 0;
      _triggerExtraction();
    }
  }

  Future<void> _triggerExtraction() async {
    final recentHistory = await _getRecentExchanges(10);
    final prompt = _buildExtractionPrompt(recentHistory);
    final response = await _aiService.askSilently(prompt);
    final extracted = _parseExtraction(response);
    for (final item in extracted) {
      if (!_memoryStore.containsKey(item.key)) {
        await _memoryStore.store(item.key, item.content, item.category, source: 'auto_learner');
      }
    }
  }

  String _buildExtractionPrompt(String history) {
    return '''
Extract user facts and preferences from this conversation. Return ONLY a JSON array.
Each element: {"key": "short_unique_key", "content": "value", "category": "GENERAL|PREFERENCE|LEARNING|ERROR"}

Only extract:
- Named entities (name, job, location, etc.)
- Explicit preferences stated by user
- Facts the user shared about themselves
- Errors/resolutions mentioned

Do NOT extract:
- Transient chat topics
- General knowledge
- Already-known information

Conversation:
$history

JSON:
    ''';
  }
}
```

**Validation:** Unit tests for extraction logic, mock AI service tests.

---

#### Task 1.6: Persona Config Model

**Objective:** Create the data model for AI personality configuration.

**Files:**
- Create: `lib/models/persona_config.dart`

**Spec:**
```dart
enum BehaviorStyle { assistant, operator, custom }
enum LanguageStyle { none, formal, casual, technical, creative, minimal }
enum CharacterType { none, helper, expert, companion, critic, creator }

class PersonaConfig {
  final String id;
  final String name;
  final String description;
  final BehaviorStyle behaviorStyle;
  final LanguageStyle languageStyle;
  final CharacterType characterType;
  final List<String> skills;
  final bool isBuiltIn;
  final String defaultSoul; // ← System prompt / personality

  // Methods: toMap(), fromMap(), generateSystemPrompt(), etc.
}
```

**Validation:** Unit tests for serialization, system prompt generation.

---

#### Task 1.7: Persona Manager

**Objective:** Implement CRUD operations for personas with persistence.

**Files:**
- Create: `lib/services/persona/persona_manager.dart`

**Spec:**
- Load/save from SharedPreferences or SQLite
- Built-in personas: Assistant, Operator, Custom
- CRUD: getAllPersonas(), getPersona(id), savePersona(), deletePersona()
- Merged built-in + custom personas

**Validation:** Unit tests for CRUD operations, persistence tests.

---

#### Task 1.8: Persona UI (Settings Screen)

**Objective:** Create UI for selecting and editing personas.

**Files:**
- Create: `lib/screens/settings/persona_settings_screen.dart`
- Create: `lib/screens/settings/persona_editor_screen.dart`

**Spec:**
- List of personas with selection
- Edit persona: name, description, behavior style, language style, character type
- Soul editor (textarea for system prompt)
- Save/delete buttons

**Validation:** Widget tests for UI interactions, screenshot tests.

---

### 🟡 PHASE 2: Voice & Communication (Week 3-4)

**Priority: HIGH** — Voice is core to assistant experience.

#### Task 2.1: TTS Provider Interface

**Objective:** Define the contract for text-to-speech providers.

**Files:**
- Create: `lib/services/tts/tts_provider.dart`

**Spec:**
```dart
abstract class TTSProvider {
  String get name;
  Future<List<String>> getAvailableVoices();
  Future<Uint8List> synthesize(String text, String voice);
  Future<bool> isAvailable();
}
```

**Validation:** Interface compiles.

---

#### Task 2.2: ChatGPT TTS Provider (Client2API)

**Objective:** Implement TTS using ChatGPT's web API with manual cookie input.

**Files:**
- Create: `lib/services/tts/chatgpt_tts_provider.dart`
- Create: `lib/screens/settings/tts_cookie_settings_screen.dart`

**Spec:**
- Endpoint: `https://chatgpt.com/backend-api/synthesize`
- Voices: orbit, breeze, cove (default), ember, fathom
- Manual cookie input in settings (like client2api)
- Cookie storage in SharedPreferences
- HTTP POST with cookie header

**Validation:** Manual testing with real ChatGPT account.

---

#### Task 2.3: Grok TTS Provider

**Objective:** Implement TTS using Grok's web API.

**Files:**
- Create: `lib/services/tts/grok_tts_provider.dart`

**Spec:**
- Endpoint: `https://grok.com/api/v1/audio/speech`
- Voice: supportedXVoiceId
- Cookie + xAiApiKey from settings

**Validation:** Manual testing.

---

#### Task 2.4: Qwen TTS Provider

**Objective:** Implement TTS using Qwen's web API.

**Files:**
- Create: `lib/services/tts/qwen_tts_provider.dart`

**Spec:**
- Endpoint: `https://chat.qwen.ai/api/v2/tts/completions`
- Voices: Eric, Ryan, Lenny, Ethan, Pip, Moon
- Cookie from settings

**Validation:** Manual testing.

---

#### Task 2.5: TTS Manager (Multi-Provider)

**Objective:** Manage multiple TTS providers with fallback logic.

**Files:**
- Create: `lib/services/tts/tts_manager.dart`

**Spec:**
```dart
class TTSManager {
  final List<TTSProvider> _providers;
  TTSProvider? _primaryProvider;

  Future<Uint8List> synthesize(String text) async {
    // 1. Try primary provider
    // 2. If fails, try next provider
    // 3. If all fail, fallback to system TTS
  }
}
```

**Validation:** Unit tests for fallback logic.

---

#### Task 2.6: Audio Player with Queue

**Objective:** Implement audio playback with sentence-level streaming.

**Files:**
- Create: `lib/services/tts/audio_player_service.dart`

**Spec:**
- Queue-based playback (just_audio)
- Sentence-level streaming (first sound ~300ms)
- Barge-in support (user can interrupt)
- Pause/resume/stop controls

**Validation:** Manual testing with real TTS responses.

---

#### Task 2.7: Port Original Services

**Objective:** Port alarm, contacts, communication, notification services from original repo.

**Files:**
- Create: `lib/services/alarm_service.dart` (from original: 51 LOC)
- Create: `lib/services/contacts_service.dart` (from original: 57 LOC)
- Create: `lib/services/communication_service.dart` (from original: 94 LOC)
- Create: `lib/services/notification_service.dart` (from original: 65 LOC)

**Spec:**
- Copy from `private-agent-original/lib/services/`
- Adapt to fork's ChangeNotifier pattern
- Integrate with TaskExecutor

**Validation:** Manual testing on device.

---

### 🟡 PHASE 3: Automation & Scheduling (Week 5-6)

**Priority: HIGH** — Enables autonomous assistant behavior.

#### Task 3.1: Cron Expression Parser

**Objective:** Parse cron expressions for task scheduling.

**Files:**
- Create: `lib/services/scheduling/cron_expression.dart`

**Spec:**
- Parse standard 5-field cron: minute hour day-of-month month day-of-week
- Calculate next execution time
- Handle edge cases (month end, leap year)

**Validation:** Unit tests with various cron expressions.

---

#### Task 3.2: Task Store (SQLite)

**Objective:** Store scheduled tasks persistently.

**Files:**
- Create: `lib/services/scheduling/task_store.dart`
- Create: `lib/models/scheduled_task.dart`

**Spec:**
```dart
class ScheduledTask {
  final String id;
  final String name;
  final String cronExpression;
  final String command;
  final bool isEnabled;
  final DateTime? lastExecuted;
  final DateTime? nextExecution;
}
```

**Validation:** Integration tests with SQLite.

---

#### Task 3.3: Task Scheduler (WorkManager)

**Objective:** Schedule and execute tasks using Android WorkManager.

**Files:**
- Create: `lib/services/scheduling/task_scheduler.dart`
- Modify: `android/app/build.gradle.kts` (add WorkManager)

**Spec:**
- Register periodic work with WorkManager
- Execute task command via TaskExecutor
- Update lastExecuted and nextExecution
- Handle task failures with retry logic

**Validation:** Manual testing on device (set alarm for 1 minute, verify execution).

---

#### Task 3.4: Heartbeat Manager

**Objective:** Implement autonomous self-checks (like Kai's heartbeat).

**Files:**
- Create: `lib/services/scheduling/heartbeat_manager.dart`

**Spec:**
```dart
class HeartbeatManager {
  static const int HEARTBEAT_INTERVAL_MINUTES = 30;
  static const int ACTIVE_HOURS_START = 8; // 8am
  static const int ACTIVE_HOURS_END = 22; // 10pm

  Future<void> heartbeat() async {
    // 1. Check if within active hours
    // 2. Review memories for patterns
    // 3. Check scheduled tasks
    // 4. If needs action → notify user
    // 5. If all good → stay silent
  }
}
```

**Validation:** Manual testing with debug logs.

---

### 🟢 PHASE 4: Advanced Features (Week 7-8)

**Priority: MEDIUM** — Enhances functionality.

#### Task 4.1: Skills System (Basic)

**Objective:** Implement skill management with slash commands.

**Files:**
- Create: `lib/services/skills/skill_manager.dart`
- Create: `lib/services/skills/skill_parser.dart`
- Create: `lib/models/skill.dart`

**Spec:**
- SKILL.md format parsing (frontmatter + body)
- Install/uninstall skills from GitHub
- Slash command detection in chat input
- System prompt injection for active skill

**Validation:** Unit tests for parser, manual testing with sample skill.

---

#### Task 4.2: Default Assistant (VoiceInteractionService)

**Objective:** Register as default Android assistant.

**Files:**
- Create: `android/app/src/main/kotlin/.../VoiceInteractionService.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Spec:**
- Implement VoiceInteractionService
- Handle voice queries when set as default
- Show overlay UI for responses

**Validation:** Manual testing in Android settings.

---

#### Task 4.3: Tools / Function Calling

**Objective:** Enable AI to use tools (web search, notifications, etc.).

**Files:**
- Create: `lib/services/tools/tool_executor.dart`
- Create: `lib/services/tools/web_search_tool.dart`
- Create: `lib/services/tools/notification_tool.dart`

**Spec:**
- Gemini function calling integration
- Tool definitions in system prompt
- Execute tool calls and return results
- Safety guards for dangerous actions

**Validation:** Manual testing with Gemini.

---

#### Task 4.4: Background Service (Foreground)

**Objective:** Run assistant in background with notification.

**Files:**
- Create: `android/app/src/main/kotlin/.../AssistantForegroundService.kt`
- Modify: `lib/services/background_service.dart`

**Spec:**
- Foreground service with persistent notification
- Listen for voice commands
- Execute tasks in background
- Battery optimization bypass prompt

**Validation:** Manual testing (lock screen, verify service running).

---

### 🔵 PHASE 5: UI & Polish (Week 9-10)

**Priority: LOW** — Final touches.

#### Task 5.1: Home Screen Widget

**Objective:** Add Android home screen widget for quick access.

**Files:**
- Create: `lib/screens/widgets/home_widget.dart`
- Modify: `android/app/build.gradle.kts` (add home_widget)

**Spec:**
- Quick voice command button
- Recent messages display
- Tap to open full app

**Validation:** Manual testing on device.

---

#### Task 5.2: Polish UI Translation

**Objective:** Translate all UI strings to Polish.

**Files:**
- Create: `lib/l10n/app_pl.arb`
- Modify: All screen files with hardcoded strings

**Spec:**
- Extract all hardcoded strings
- Translate to Polish
- Test with locale switching

**Validation:** Manual testing with Polish locale.

---

### ⚪ PHASE 6: Advanced Integration (Week 11-12)

**Priority: LOW** — Future enhancements.

#### Task 6.1: Alt-Memory (Vector Brain)

**Objective:** Implement semantic search with embeddings.

**Files:**
- Create: `lib/services/memory/vector_memory_store.dart`
- Modify: `pubspec.yaml` (add vector_db package)

**Spec:**
- Store embeddings for memories
- Semantic search for relevant memories
- Knowledge graph relationships
- Personal AI diary

**Validation:** Manual testing with sample data.

---

#### Task 6.2: Client2API (Web Chat to API)

**Objective:** Convert web chat sessions to API endpoints.

**Files:**
- Create: `lib/services/client2api/client2api_service.dart`

**Spec:**
- Session management
- Cookie extraction
- API proxy for chat completions

**Validation:** Manual testing with ChatGPT.

---

#### Task 6.3: Clipboard Integration

**Objective:** Copy/paste text between apps.

**Files:**
- Create: `lib/services/clipboard_service.dart`

**Spec:**
- Clipboard monitoring (with battery optimization)
- Long-press menu integration
- Paste to active input field

**Validation:** Manual testing.

---

## Summary Table

| Phase | Tasks | Hours (est.) | Week |
|-------|-------|--------------|------|
| **Phase 1: Memory & Personality** | 8 tasks | 30-40h | 1-2 |
| **Phase 2: Voice & Communication** | 7 tasks | 25-35h | 3-4 |
| **Phase 3: Automation & Scheduling** | 4 tasks | 20-28h | 5-6 |
| **Phase 4: Advanced Features** | 4 tasks | 20-28h | 7-8 |
| **Phase 5: UI & Polish** | 2 tasks | 8-12h | 9-10 |
| **Phase 6: Advanced Integration** | 3 tasks | 18-26h | 11-12 |
| **TOTAL** | **28 tasks** | **121-169h** | **12 weeks** |

---

## Dependencies

```
Phase 1 (Memory) → Phase 2 (Voice uses memory for context)
Phase 1 (Memory) → Phase 3 (Scheduling uses memory for patterns)
Phase 2 (Voice) → Phase 4 (Tools use voice for output)
Phase 3 (Scheduling) → Phase 4 (Background service uses scheduling)
Phase 4 (Advanced) → Phase 5 (UI polish)
Phase 5 (UI) → Phase 6 (Integration)
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Huawei EMUI kills background services | Foreground service + battery optimization bypass |
| TTS cookies expire | Auto-refresh notification + manual re-enter |
| Wake word battery drain | Configurable detection interval |
| SQLite performance with large memory | Index optimization + memory pruning |
| Gemini function calling limitations | Fallback to manual tool execution |

---

## Open Questions

1. **TTS Priority:** ChatGPT vs Grok vs Qwen — which should be default?
2. **Wake Word Phrase:** "Hey [assistant name]" — what name?
3. **Memory Limit:** Max memories before pruning?
4. **Skills Marketplace:** Which repos to include initially?

---

## Next Steps

1. **Review this plan** — Any changes needed?
2. **Answer open questions** — Finalize design decisions
3. **Start Phase 1** — Memory Store implementation
4. **Weekly check-ins** — Progress review and adjustments

---

*Plan created: 2026-09-09*
*Last updated: 2026-09-09*
