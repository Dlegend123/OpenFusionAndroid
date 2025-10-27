# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),  
and this project adheres to [Semantic Versioning](https://semver.org/).

**Project:** OpenFusion AutoHotkey Launcher  
**Author:** Mark Morrison  
**Language:** AutoHotkey v2  
**Last Updated:** 2025-10-27  
___

### [1.9.0] - 2025-10-27]
- Simplified process handling to improve stability on Winlator and GameHub.
- Server (`winfusion.exe`) now starts only if not already running.
- Removed forced server shutdown after game exit to avoid premature termination.
- Changed process launch behavior:
  - Replaced `RunWait` with detached `Run` to prevent AutoHotkey from freezing the game.
  - Added short delay and graceful `ExitApp` to ensure proper release of input focus under Wine.
- Removed unnecessary port checks and startup delays.
- A config file is now expected in the same directory as the OpenFusion executable.
- All paths in the config file can be **relative** to the OpenFusion executable directory.
- Username, token, width, and height are now optional and read from `[launcher]` section if present.
- File verification restored for critical folders and assets (server, launcher, cache, main.unity3d).

---

## [1.8.0] - 2025-10-27
### Added
- Automatic port detection by parsing the `[login]` section of `config.ini`.

### Changed
- Verified full compatibility with AutoHotkey v2.
- Removed unnecessary sleeps and debug file output.
- Retained directory and file validation for reliability.
- Simplified command building and improved code readability.
- Confirmed successful communication between `ffrunner` and `winfusion`.
- Ensured server process closes automatically when the game exits.
- Marked as the latest working and verified version.

---

## [1.7.0] - 2025-10-26
### Changed
- Refactored repetitive logic into concise expressions.
- Removed unused variables and redundant conditions.
- Combined command-line parameters into a single `Format()` call.
- Eliminated experimental waits and tooltips.
- Enhanced formatting and section comments for maintainability.

---

## [1.6.0] - 2025-10-26
### Added
- Parser for `OpenFusionServer/config.ini` to extract login port dynamically.

### Changed
- Replaced static port `23000` with dynamic detection.
- Fallback to default if no valid port found.
- Initially wrote detected port to a log file for debugging (later removed).

---

## [1.5.0] - 2025-10-25
### Added
- Pipe reading to capture `winfusion.exe` output.
- Detection of `"Starting shard server at"` readiness message.

### Changed
- Continued automatically once server startup was detected.
- Later reverted due to unreliability in Wine environments.

---

## [1.4.0] - 2025-10-25
### Changed
- Consolidated multiple file-missing alerts into one message box.
- Enhanced cleanup using `ProcessClose()` with `taskkill` fallback.
- Improved user-facing error formatting.
- Ensured consistent exit behavior.

---

## [1.3.0] - 2025-10-24
### Changed
- Removed unnecessary startup delays.
- Confirmed hidden server startup works reliably.
- Simplified script structure for clarity.

---

## [1.2.0] - 2025-10-24
### Added
- Automatic detection of screen resolution for launcher window.

### Removed
- Width/height arguments later removed due to graphical glitches.

---

## [1.1.0] - 2025-10-24
### Added
- File and directory integrity checks for:
  - `OpenFusionServer`
  - `winfusion.exe`
  - `OpenFusionLauncher`
  - `offline_cache`
  - `main.unity3d`
- Displayed missing files via formatted message box.

---

## [1.0.0] - 2025-10-23
### Added
- Initial launcher functionality:
  - Start `OpenFusionServer`.
  - Launch `ffrunner` in Vulkan mode.
  - Terminate server on exit.
- Established base structure for future updates.
