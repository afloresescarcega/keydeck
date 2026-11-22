# Security Policy

KeyDeck is designed as a **zero-backend, bring-your-own-key (BYOK)** iOS keyboard and companion app. Because keyboard extensions operate across every app on your phone, security and data isolation are treated as first-class invariants.

## Security Architecture

- **Zero Developer Backend**: KeyDeck never phones home, runs no analytics or telemetry SDKs, and sends no user data to any server owned by the author.
- **Direct Device-to-Provider TLS**: All AI calls go straight from your iPhone to Google Gemini (`generativelanguage.googleapis.com`) or OpenAI (`api.openai.com`) over strict HTTPS (`NSAllowsArbitraryLoads = false`).
- **Ephemeral Zero-Cache Networking**: `GeminiClient` and `OpenAIClient` use `URLSessionConfiguration.ephemeral` with `urlCache = nil`, `httpCookieStorage = nil`, and `.reloadIgnoringLocalAndRemoteCacheData` so audio payloads, transcripts, and API keys are never persisted in URL caches.
- **Header-Only API Credentials**: Gemini keys are transmitted in the `x-goog-api-key` HTTP header (never in URL query strings); OpenAI keys use `Authorization: Bearer`.
- **Device-Bound Keychain Storage**: API keys are stored in the iOS Shared Keychain using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so keys never leave the device in unencrypted backups or cross-device migrations.
- **Password / Secure Field Guard**: `KeyboardViewController` checks `textDocumentProxy.isSecureTextEntry == true` and refuses to capture or transmit text from password, PIN, or secure entry fields.
- **Encrypted On-Device Storage**: App Group files (settings, clipboard history, transcript log) are written atomically with iOS Data Protection (`completeFileProtectionUntilFirstUserAuthentication`), and audio filenames are sanitized against path traversal.
- **Explicit Microphone Control**: The background audio session can be killed in one tap directly from the keyboard (`Kill Mic`), Dynamic Island / Lock Screen Live Activity, companion app, idle timeout (default 5 minutes), or immediately after every dictation (`Auto-Kill Mic After Each Dictation`).

## Reporting a Vulnerability

If you discover a security vulnerability in KeyDeck:

1. **Do not** open a public GitHub issue with exploit details.
2. Use GitHub's **Private Vulnerability Reporting** (Security tab → *Report a vulnerability*) or contact the repository owner directly via GitHub (`@afloresescarcega`).
3. Include a clear description, reproduction steps, and affected files/targets.

We aim to acknowledge reports within 72 hours and ship a fix promptly.
