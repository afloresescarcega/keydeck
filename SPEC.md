# KeyDeck — Personal iOS Utility Keyboard

**App Name**: KeyDeck  
**Bundle ID Prefix**: `com.alexfloresescarcega.keydeck`  
**App Group**: `group.com.alexfloresescarcega.keydeck`  
**Shared Keychain Access Group**: `$(AppIdentifierPrefix)com.alexfloresescarcega.keydeck`  
**iCloud Container**: `iCloud.com.alexfloresescarcega.keydeck`  
**URL Scheme**: `keydeck://`  
**Target Platform**: iOS 17.0+ (Swift 6, SwiftUI, UIKit Keyboard Extension, WidgetKit Live Activities)

---

## Product Vision

KeyDeck is a **dedicated utility keyboard** for iOS — switch to it via the globe key whenever you want voice-powered Rambler dictation, Voice Edit, or commands/snippets/workflows, while keeping Apple's native QWERTY keyboard for everyday typing.

### Core Pillars

1. **Voice Dictation — Rambler & Voice Edit**
   - **Persistent Background Audio Session + Fallback** (Wispr Flow style): First tap opens KeyDeck briefly to start a background audio session with a Dynamic Island / Live Activity indicator; once armed, swipe back and record in-place from the keyboard without leaving your app. Automatic fallback if iOS reclaims the session.
   - **Rambler Mode**: Talk freely and messily; AI distills your stream of consciousness into clean sentences, paragraphs, or lists.
   - **Voice Edit**: Speak an instruction to transform selected or surrounding text in the input field (e.g., *"make this shorter"*, *"fix tone"*, *"translate to Spanish"*).
   - **Auto-Insert + Contextual Undo / Tweak Bar**: Output inserts immediately into the active field, paired with one-tap `Undo`, `Shorter`, `Bullets`, `Casual`, and `Raw` chips.
   - **Context & Reliability**:
     - Surrounding text awareness (`documentContextBeforeInput` / `selectedText`) with a quick privacy toggle.
     - Custom Dictionary (names, jargon, acronyms) and Personal Instructions.
     - Local Transcript & Audio Fallback Log in the companion app so no long recording is ever lost on network failure.

2. **BYOK AI Routing (Zero Backend)**
   - **OpenAI** and **Gemini** API keys stored in the Shared Keychain; all requests go directly from device to provider.
   - Default to **Gemini single-pass multimodal audio** (`gemini-2.5-flash`) for Rambler & Voice Edit — one fast call that hears tone, pauses, and self-corrections and returns both clean output and raw transcript.
   - Optional **OpenAI two-pass pipeline** (`gpt-4o-transcribe` / `whisper-1` → OpenAI or Gemini LLM).
   - Per-workflow provider and model overrides.

3. **Command Palette & Composable Workflows**
   - **Two-Mode Keyboard UI**:
     - *Dashboard (default)*: Rambler & Voice Edit triggers, pinned actions/snippets/clips, top search bar, and essential quick-edit bar (Globe, Backspace, Return, Undo).
     - *Expandable Search Palette*: Live fuzzy search + inline utility previews (calculator, conversions, UUID/timestamps, symbols) above a compact built-in mini-QWERTY for typing short queries, math, or arguments.
   - **5 Core Capabilities**:
     1. Dynamic Snippets & Templates (`{{date}}`, `{{time}}`, `{{clipboard}}`, `{{selection}}`, fill-in args)
     2. Custom AI Workflows
     3. External Triggers (Apple Shortcuts `shortcuts://`, custom HTTP webhooks/APIs, URL schemes)
     4. Inline Utilities (calculator, unit/timezone conversion, UUID/timestamp, symbol search)
     5. Clipboard Manager & Pinned Clips
   - **Composable Multi-Step Pipelines**: `[Input] → [Transform: LLM / Regex / Template / HTTP] → [Output: Insert / Copy / Webhook / Apple Shortcut]`.
   - **Authoring & Sync**: Companion app visual builder + JSON import/export syncable via iCloud Drive / Files.

---

## Architecture Overview

| Target | Bundle ID | Responsibility |
| --- | --- | --- |
| `KeyDeckApp` | `com.alexfloresescarcega.keydeck` | Companion app: persistent `AVAudioSession` & recorder, AI processing coordinator, Live Activity lifecycle, transcript/audio fallback log, visual workflow builder, settings & Keychain management. |
| `KeyDeckKeyboard` | `com.alexfloresescarcega.keydeck.keyboard` | Lightweight `UIInputViewController` hosting SwiftUI Dashboard, Undo/Tweak bar, Search Palette + mini-QWERTY, and `textDocumentProxy` text manipulation. |
| `KeyDeckWidgets` | `com.alexfloresescarcega.keydeck.widgets` | WidgetKit extension providing Dynamic Island & Lock Screen Live Activity for active mic session / recording / processing status. |
| `KeyDeckKit` | Local Swift Package | Shared models, App Group store, Shared Keychain, Darwin IPC notifier, AI clients (Gemini & OpenAI), PromptBuilder, Pipeline Engine, Inline Utilities. |

---

## Phased Delivery Plan

- **Phase 1 — Foundation & Voice**: XcodeGen multi-target project, `KeyDeckKit` package, Companion App, Keyboard Extension Dashboard, Persistent Audio Session + Live Activity, Gemini/OpenAI BYOK clients, Rambler & Voice Edit with Auto-Insert + Undo/Tweak bar, Custom Dictionary, Privacy Toggle, Local Transcript & Audio Fallback Log.
- **Phase 2 — Command Palette & Utilities**: Expandable Search Bar, compact built-in mini-QWERTY, Dynamic Snippets (`{{date}}`, `{{time}}`, `{{clipboard}}`, fill-in args), Inline Calculator/Converters/Generators, Clipboard Manager & Pinned Clips.
- **Phase 3 — Composable Workflows & Sync**: Multi-step Pipeline Engine (LLM, regex, template, HTTP fetch/webhook, Apple Shortcuts), Visual Workflow Builder, iCloud Drive JSON Import/Export, final polish.
