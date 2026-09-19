# CYSTEM

CYSTEM is a private Android AI command center built in Flutter. It keeps conversations and attachments local, stores API credentials in Android secure storage, routes tasks across NVIDIA NIM and Gemini services, and presents the result through a futuristic system-style UI.

## What is included

- NVIDIA NIM OpenAI-compatible chat-completions integration with SSE streaming, reasoning/tool-call accumulation, retries, cancellation and usage metadata.
- Default Nemotron 3 Super brain with optional Nemotron 3 Ultra.
- Nemotron 3 Nano Omni attachment analysis for images and extracted file text.
- Gemini live web research with Google Search grounding and image search with persistent downloaded image attachments; grounded image-search attribution is retained with each saved attachment.
- Typed tool registry with strict JSON argument validation plus a separate Android phone-tool bridge.
- SQLite-backed multi-chat history, message metadata, attachments, tool calls and model/source metadata.
- Secure API-key storage, editable system instructions, memory, generation controls, biometric lock and appearance controls.
- Voice input/output, camera capture, Android share target, export/import backup, slash-command palette and chat search.
- Futuristic glass/HUD visual system, animated boot sequence, staggered messages, shimmer thinking state, glowing streaming cursor, adaptive tablet layout and reduced-motion handling.
- Unit/widget tests for models, parsing, validation, retry, storage and key UI paths.
- GitHub Actions workflow that installs Flutter stable, analyzes, tests and builds a release APK.

## Setup

1. Install Flutter stable and Android Studio/SDK.
2. Clone the repository and run `flutter pub get`.
3. Open the app and go to **Settings → Providers**.
4. Enter your NVIDIA API key and/or Gemini API key. Keys are stored locally with `flutter_secure_storage` and are never committed to the repository.
5. For NVIDIA, the app defaults to `https://integrate.api.nvidia.com/v1`. A self-hosted NIM/OpenAI-compatible endpoint can be configured in the provider settings by changing the base URL.
6. Build with `flutter build apk --release`.

## Provider behavior

The model router selects:

- `nvidia/nemotron-3-super-120b-a12b` for normal conversation, reasoning, coding, planning and final synthesis.
- `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` for private attachment/image analysis.
- `nvidia/nemotron-3-ultra-550b-a55b` only when the user explicitly selects Ultra.
- `gemini-3.8-flash` for grounded web research.
- `gemini-3.1-flash-image` with Google Search image grounding for image-search requests.

The model identifiers are centralized in `lib/core/constants/model_constants.dart` so they are easy to change.

## Adding a tool

Implement `CystemTool` in `lib/tools`, define a JSON-schema-like argument map, register it in `ToolRegistry`, and implement the behavior in `ToolExecutor`. Validation runs before execution. Keep device actions behind `AndroidBridge` so permissions and platform-specific behavior remain isolated.

## Adding a model

Add a `ModelDefinition` in `lib/core/constants/model_constants.dart`, update `ModelRouter`, and route the provider through `NimClient` or `GeminiClient`. Model IDs never need to be scattered through UI code.

## Backup format

Backups are JSON and contain conversations, messages, attachment metadata and memories. API keys are never included in backups. Attachment file bytes remain in the app's private storage unless separately copied/exported by the user.

## Privacy

CYSTEM is designed around local-first storage. Conversations and attachments are stored on-device. Requests only leave the device when the user uses a configured provider. Keys remain in encrypted Android storage. No persistent background service or background execution permission is requested.

## PDF extraction license

PDF text extraction uses `syncfusion_flutter_pdf`. Check Syncfusion's current Community or commercial licensing terms for the project and distribution model you intend to use.

## Build notes

The included CI workflow uses the current Flutter stable channel. This execution environment does not ship with the Flutter SDK, so local APK compilation could not be run here; the repository includes a CI build that performs `flutter analyze`, `flutter test` and `flutter build apk --release` on every push/PR.
