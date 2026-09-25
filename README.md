# Duplicate Finder

Native macOS app for finding exact duplicate files locally.

## Features

- Images, videos, music, documents, archives and any other regular files
- Groups files by exact SHA-256 content hash
- First groups by file size before hashing, reducing unnecessary work
- Shows duplicate count and recoverable disk space
- Preview file names, locations, sizes and native file icons
- Select individual files or keep the first file in each group
- Moves selected files to the macOS Trash instead of deleting permanently
- No cloud upload and no background service
- Works on Apple Silicon and Intel when built on macOS

## Requirements

- macOS 13 Ventura or newer
- Xcode Command Line Tools

## Build locally

Open Terminal in this folder and run:

```bash
./build.command
```

The finished files are in `dist/`.

## Important

The app scans only inside the folder you choose. Hidden files and package descendants are skipped by default. Files are moved to the Trash, not permanently erased.


### App Icon
The project includes the custom **Duplicate Finder** app icon in `Resources/AppIcon.png`. `build.command` automatically creates `AppIcon.icns` with macOS `sips`/`iconutil` and attaches it to the `.app`.
