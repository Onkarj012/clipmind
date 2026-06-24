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
- XcodeGen for regenerating `ClipMind.xcodeproj`

## Setup

Install dependencies through Swift Package Manager by opening the project in Xcode or running a build:

```sh
xcodebuild -project ClipMind.xcodeproj -scheme ClipMind -configuration Debug -derivedDataPath .build/DerivedData build
```

Regenerate the Xcode project after changing `project.yml`:

```sh
xcodegen generate
```

## Project Structure

- `ClipMind/` contains the app source.
- `ClipMind/Assets.xcassets/` contains the app icon and reusable logo mark.
- `ClipMindTests/` contains unit tests.
- `clipmind.icon/` keeps the source icon package used to generate the app icon assets.
- `project.yml` is the XcodeGen project definition.

## Icon

The source icon image lives at `clipmind.icon/Assets/icon.png`. The app uses generated PNG sizes in `ClipMind/Assets.xcassets/AppIcon.appiconset` so Xcode can compile the macOS `AppIcon.icns`.
