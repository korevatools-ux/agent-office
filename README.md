# Agent Office

A Flutter app for creating tasks, reviewing an AI-generated plan, approving it, and running the plan step by step with a local Ollama model. Tasks and settings are saved on-device. No API key or cloud account is required.

## Requirements

- Flutter 3.19+ (Dart 3)
- [Ollama](https://ollama.com/) running on a computer reachable from the device
- A model downloaded in Ollama, for example `qwen2.5:3b`

```bash
ollama pull qwen2.5:3b
ollama serve
```

## Run the app

```bash
flutter pub get
flutter create --platforms=android,ios .
flutter run
```

If `flutter create` says the project already exists, accept its platform scaffolding or run it with `--overwrite` only if you do not need to preserve existing platform files. The repository contains the Flutter app source and package manifest; Flutter generates the native platform runner files.

### Ollama address

Set the address from the app's settings:

- Android emulator: `http://10.0.2.2:11434`
- iOS simulator: `http://localhost:11434`
- Physical device: `http://<computer-LAN-IP>:11434` (both devices must be on the same trusted network)
- Desktop: `http://localhost:11434`

For Android local HTTP development, add the Internet permission to `android/app/src/main/AndroidManifest.xml` and enable cleartext traffic on the `<application>` element. Use HTTPS or an appropriately secured setup outside local development. Do not expose Ollama directly to an untrusted network.

## What the app does

1. Sends a task description to Ollama and requests a short JSON plan.
2. Shows the plan for explicit approval.
3. Runs one step at a time when you tap **Run next step**.
4. Displays results and saves them locally.

The agent only works with the text you provide and its model's built-in knowledge. It does not browse the web, modify project files, or control other apps. Add explicitly scoped integrations before granting it those capabilities.
