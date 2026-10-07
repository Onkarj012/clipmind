# ClipMind

ClipMind is a native macOS menu bar clipboard manager with AI-assisted organization. It keeps a searchable clipboard history for text, files, and images, then layers on features like OCR, metadata extraction, tagging, summaries, and semantic search.

## Features

- Menu bar access to recent clipboard items
- Command palette and library window for fast search
- Clipboard capture for text, files, and images
- OCR indexing for screenshots and copied images
- AI metadata, tagging, and summary actions
- Semantic search backed by embeddings
- Local settings for retention, OCR, and AI providers

## Requirements

- macOS 15.0 or newer
- Xcode with the macOS SDK
- XcodeGen for regenerating `apple/ClipMind.xcodeproj`

## Setup

Install dependencies through Swift Package Manager by opening the project in Xcode or running a build:

```sh
xcodebuild -project apple/ClipMind.xcodeproj -scheme ClipMind -configuration Debug -derivedDataPath .build/DerivedData build
```

Regenerate the Xcode project after changing `apple/project.yml`:

```sh
cd apple && xcodegen generate
```

## Project Structure

- `apple/` contains the macOS app:
  - `apple/ClipMind/` is the app source.
  - `apple/ClipMind/Assets.xcassets/` holds the app icon and reusable logo mark.
  - `apple/ClipMindTests/` contains unit tests.
  - `apple/clipmind.icon/` keeps the source icon package used to generate the app icon assets.
  - `apple/project.yml` is the XcodeGen project definition.
- `plans/` holds design plans, including the [cross-platform sync plan](plans/cross-platform-sync.md).
- `issues/` holds implementation slices.

## Icon

The source icon image lives at `apple/clipmind.icon/Assets/icon.png`. The app uses generated PNG sizes in `apple/ClipMind/Assets.xcassets/AppIcon.appiconset` so Xcode can compile the macOS `AppIcon.icns`.
