# Duplicate Finder — repo notes

## What this repo is
The original project is a **native macOS SwiftUI app** (`Package.swift`, `Sources/DuplicateFinder/main.swift`, built with `./build.command`). It cannot build or run in the Linux sandbox — it is kept for reference.

A **browser port** was added at the repo root so the app can run in the Base44 preview:
- `src/` — Vite + React app; all duplicate detection runs client-side (File System Access API + Web Crypto SHA-256).
- `src/lib/scan.js` — directory walk, size pre-grouping, SHA-256 hashing, duplicate grouping.
- `src/lib/format.js` — byte formatting and file-type icons.

## Running it
```bash
docker compose -f docker-compose.base44.yml up -d --build
```
- Web entry point: http://localhost:3000 (Vite dev server on 5173 inside the container, bind-mounted source, live reload).
- Node deps install on container start into a named `node_modules` volume.

## Verifying it works
- `curl -s -o /dev/null -w '%{http_code}' http://localhost:3000` → `200`.
- The app is fully client-side: scanning/deleting requires the user to pick a folder in the browser (File System Access API, Chromium only). Deleting files is permanent in the browser — there is no Trash.

## Notes / gotchas
- The dev server must accept the preview host: `allowedHosts: true` in `vite.config.js` plus the platform-provided `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS`.
- Hashing loads whole files into memory (`crypto.subtle` has no streaming API) — fine for typical use, heavy for very large files.
- No backend, no database, no external services or credentials required.
