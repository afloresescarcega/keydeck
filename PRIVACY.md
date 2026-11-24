# Privacy Policy — KeyDeck

**Effective Date**: November 23, 2026  
**Author**: Alex Flores Escarcega  
**License**: MIT (Open Source)

The developer of KeyDeck collects **no** personal data, analytics, crash telemetry, or advertising identifiers, and KeyDeck does not track you. There is no KeyDeck server or account. The only data that leaves your device is what you choose to send to a third-party AI provider (section 2).

## 1. Data Stored On Your Device
KeyDeck stores the following data strictly on your iPhone inside your private App Group container and iOS Keychain:
- **API Keys**: Your Google Gemini and/or OpenAI API keys are stored in the iOS Keychain (`ThisDeviceOnly`) and are never sent anywhere except directly to their respective provider.
- **Local History & Recordings**: Voice recordings and transcripts are saved locally on your device so you can retry failed network requests or copy past rambles. You can swipe to delete any entry (including its audio file) at any time.
- **Snippets, Settings & Clipboard History**: Stored locally in your private App Group container.

## 2. Third-Party AI Providers (BYOK)
When you explicitly trigger **Rambler**, **Voice Edit**, or a **Quick Tweak**:
- Audio or text you choose to process is sent **directly from your device** to Google Gemini (`generativelanguage.googleapis.com`) or OpenAI (`api.openai.com`) using your own API key.
- **Explicit permission first**: KeyDeck shows a disclosure naming Google and OpenAI and asks for your permission before any data is sent. You can withdraw it anytime in *KeyDeck → Settings → AI Data Sharing*; while off, KeyDeck makes no AI requests.
- **What is sent**: your voice recording, the text you ask KeyDeck to edit, your custom dictionary and style instructions, and (only if enabled) surrounding field text.
- If **Send Surrounding Field Context** is enabled (off by default; you can toggle it in one tap from the keyboard top bar), text near your cursor may be included to improve dictation accuracy or apply Voice Edit. KeyDeck **never** reads text from secure password fields (`isSecureTextEntry == true`).
- Your data sent to Google or OpenAI is governed by your own API agreement and privacy policy with those providers, which may include temporary retention for abuse monitoring ([Gemini API terms](https://ai.google.dev/gemini-api/terms), [OpenAI privacy policy](https://openai.com/policies/privacy-policy)).

## 3. Why "Allow Full Access" Is Required
iOS requires Custom Keyboard Extensions to request **Allow Full Access** in order to:
1. Communicate with the KeyDeck companion app via the shared App Group container (for microphone capture, snippets, and clipboard clips).
2. Read your API keys from the Shared Keychain and send direct HTTPS requests for Quick Tweaks.

KeyDeck **never** logs keystrokes in the background and does not transmit anything unless you explicitly tap a voice or AI action.

## 4. App Store Privacy Manifests
All targets (`KeyDeckApp`, `KeyDeckKeyboard`, and `KeyDeckWidgets`) ship with Apple `PrivacyInfo.xcprivacy` manifests declaring:
- `NSPrivacyTracking`: `false`
- `NSPrivacyCollectedDataTypes`: Audio Data and Other User Content (app and keyboard), not linked to identity, not used for tracking, purpose App Functionality — declared because user-initiated requests are processed by Google/OpenAI.

## 5. Deleting Your Data
Swipe to delete history entries, clear API keys in Settings, or delete the app to remove all KeyDeck data from your device.

## 6. Contact
For privacy questions or requests, open an issue or reach out at [github.com/afloresescarcega/keydeck](https://github.com/afloresescarcega/keydeck).
