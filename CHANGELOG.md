# Glys Bootstrap Changelog

All notable changes to the Glys bootstrap installer.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/).

## [0.1.2] - 2026-06-05

### Changed
- Python is now installed directly from python.org (no longer via winget). Removes the winget abstraction layer for Python only; Git and Chrome continue to use winget primary with direct-download fallback. Eliminates any chance of buyer confusion with the Microsoft Store Python package (which lacks FTS5 and breaks `/user-osint`) and works on corporate machines where winget is restricted.
- Distribution URLs now pinned to `raw/v0.1.2/` instead of `raw/v0.1.1/`.

## [0.1.1] - 2026-06-05

### Added
- Windows PowerShell installer (`install.ps1`) and double-click shim (`glys-bootstrap.bat`)
- macOS Bash installer (`install.sh`)
- Detects and installs Python 3.12, Claude Code, Git, Chrome
- winget primary path with direct-download fallback (Windows)
- Homebrew primary path with auto-install if absent (macOS)
- Idempotent: re-running with all prerequisites present exits 0 immediately
- Smoke test scripts for post-install verification

### Notes
- Scripts are unsigned. Code signing planned for a future release.
- Linux not supported.
- Distribution URLs pinned to release tag for supply-chain integrity. Verify the URL matches the release tag you expect.
