# Glys Bootstrap Changelog

All notable changes to the Glys bootstrap installer.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/).

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
- Scripts are unsigned. Code signing planned for v0.1.2.
- Linux not supported.
- Distribution URLs pinned to v0.1.1 release tag for supply-chain integrity. Verify the URL matches the release tag you expect.
