# JARVIS

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://docs.flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.11+-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20Architecture-6A1B9A)](#architecture)
[![State](https://img.shields.io/badge/State%20Management-flutter_bloc-1E88E5)](https://pub.dev/packages/flutter_bloc)
[![Database](https://img.shields.io/badge/Database-Isar-00ACC1)](https://isar.dev/)

JARVIS is a Flutter chat application powered by Gemini streaming responses.  
It follows a clean, feature-first architecture with dependency injection, local persistence, and resilient network handling (timeouts, rate limits, and model failover).

## Highlights

- Real-time streamed AI responses with progressive word reveal.
- Offline-aware message flow with pending/retry behavior.
- Local chat persistence using Isar.
- Optional image input support in chat requests.
- Gemini model failover chain for quota/rate-limit resilience.
- `flutter_bloc`-based state management with explicit UI states.

## Tech Stack

- **Framework:** Flutter (Dart 3.11+)
- **State Management:** `flutter_bloc`
- **Networking:** `dio`
- **Connectivity:** `connectivity_plus`
- **Local Database:** `isar`
- **DI / Service Locator:** `get_it`
- **Env Config:** `flutter_dotenv`
- **Modeling:** `freezed`, `json_serializable`

## Project Structure

```text
lib/
  core/
    error/                 # Exceptions and failures
    network/               # Dio client + connectivity service/cubit
    storage/               # Local image storage helpers
    utils/                 # App constants and env-backed configuration
  di/
    injection.dart         # get_it registrations and app wiring
  features/
    chat/
      data/                # Local/remote datasources + repository impl
      domain/              # Entities, repository contract, use cases
      presentation/        # Bloc, pages, and widgets
  main.dart                # App bootstrap and provider setup
```

## Architecture

This project uses **Clean Architecture** with feature-first organization:

- **Presentation (`features/chat/presentation`)**
  - UI widgets/pages and `ChatBloc`.
  - Emits clear states like loading, streaming, loaded, and error.
  - Handles user actions (send, retry, delete turn, continue response, clear chat).

- **Domain (`features/chat/domain`)**
  - Pure business layer.
  - Defines `ChatMessage` entity, repository contract, and use cases:
    `SendMessage`, `SaveMessage`, `GetChatHistory`, `DeleteMessagesByIds`, `ClearChat`.

- **Data (`features/chat/data`)**
  - `ChatRepositoryImpl` coordinates local and remote data sources.
  - `ChatRemoteDataSource` streams Gemini responses.
  - `ChatLocalDataSource` persists/retrieves conversations via Isar.

- **Core + DI (`core`, `di`)**
  - Shared network/error/storage utilities.
  - Centralized dependency registration in `di/injection.dart`.

### Runtime Flow (Send Message)

1. User sends text (and optional image) from `ChatPage`.
2. `ChatBloc` creates/persists a user message and emits streaming state.
3. Repository requests streaming chunks from Gemini remote datasource.
4. Bloc reveals response incrementally and updates assistant placeholder.
5. Final assistant message is persisted to Isar.
6. Errors are mapped to typed failures and surfaced with retry UX.

## Setup

### 1) Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (compatible with Dart `^3.11.0`)
- A Gemini API key
- Platform tooling for your target (Android Studio/Xcode/etc.)

### 2) Install dependencies

```bash
flutter pub get
```

### 3) Configure environment

Create a `.env` file in the project root:

```env
GEMINI_API_KEY=your_api_key_here
GEMINI_MODEL=gemini-2.5-flash
GEMINI_MODEL_FALLBACKS=gemini-2.5-pro,gemini-2.0-flash-lite
```

Notes:
- `GEMINI_API_KEY` is required.
- `GEMINI_MODEL` and `GEMINI_MODEL_FALLBACKS` are optional; defaults are already defined in `lib/core/utils/constants.dart`.
- Do not commit real secrets.

### API / Model Matrix (Short)

- `GEMINI_API_KEY` — required — authenticates requests to Gemini API.
- `GEMINI_MODEL` — optional — primary model (default: `gemini-2.5-flash`).
- `GEMINI_MODEL_FALLBACKS` — optional — comma-separated failover order (default: `gemini-2.5-pro,gemini-2.0-flash-lite`).
- Endpoint (derived): `https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse`.

### 4) Generate code (first run or after model changes)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 5) Run the app

```bash
flutter run
```

## Development Commands

```bash
# Static analysis
flutter analyze

# Unit/widget tests
flutter test

# Regenerate code continuously while editing models
dart run build_runner watch --delete-conflicting-outputs
```

## Reliability Features

- Rate-limit handling with retry window countdown.
- Streaming stall detection with "continue response" workflow.
- Connectivity-aware pending queue and retry support.
- Centralized failure mapping (`Network`, `Timeout`, `RateLimit`, `Server`, `Streaming`).

## Security and Configuration

- Keep `.env` local and private.
- Rotate API keys if exposed.
- Prefer environment-based configuration over hardcoded secrets.

## License

Add your preferred license (for example, MIT) in a `LICENSE` file.
