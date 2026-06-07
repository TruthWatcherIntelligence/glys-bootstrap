# Glys Bootstrap Changelog

All notable changes to the Glys bootstrap installer.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/).

## [0.1.3] - 2026-06-07

### Fixed
- Removed `#Requires -Version 5.1` from install.ps1; replaced with inline version check. The `#Requires` directive does not work inside `Invoke-Expression`, which broke the canonical `irm | iex` install pattern on stock PowerShell 5.1. Buyer-facing one-liner now works as documented.

### Added
- winget auto-install on Windows when absent (parity with macOS Homebrew auto-install). Downloads ~80 MB of App Installer + dependencies via Microsoft's official MSIX bundle distribution. Falls back to direct downloads for Git and Chrome if auto-install fails (corporate-locked environments).

### Changed
- Distribution URLs pinned to `raw/v0.1.3/` instead of `raw/v0.1.2/`.
- Buyer one-liner (Windows) reverts to the clean `irm | iex` form now that `#Requires` is removed. Includes explicit TLS 1.2 enablement for PowerShell 5.1 compatibility.

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
