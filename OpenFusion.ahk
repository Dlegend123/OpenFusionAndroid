#SingleInstance Force
SetWorkingDir A_ScriptDir
DetectHiddenWindows True

; ===========================
; CONFIGURATION
; ===========================
SERVER_DIR := A_ScriptDir "\OpenFusionServer-Academy"
LAUNCHER_DIR := A_ScriptDir "\OpenFusionLauncher"
VERSION_UUID := "6543a2bb-d154-4087-b9ee-3c8aa778580a"
CACHE_DIR := LAUNCHER_DIR "\offline_cache\" VERSION_UUID
MAIN_FILE := CACHE_DIR "\main.unity3d"
ASSET_URL := "file:///" StrReplace(CACHE_DIR, "\", "/") "/"
LOG_FILE := LAUNCHER_DIR "\ffrunner_output.txt"
ADDRESS := "127.0.0.1:23000"

; ===========================
; START SERVER (fully silent)
; ===========================
Run('"' SERVER_DIR '\winfusion.exe"', SERVER_DIR, "Hide")

; Wait a few seconds for the server to initialize
Sleep(3000)

; ===========================
; START GAME (visible window)
; ===========================
ffCmd := 'ffrunner.exe --force-vulkan '
    . '-m "' MAIN_FILE '" '
    . '-a "' ADDRESS '" '
    . '--asseturl "' ASSET_URL '" '
    . '--width 1920 --height 1080 '
    . '-l "' LOG_FILE '" '
    . '-v --offline'

RunWait(ffCmd, LAUNCHER_DIR)

; ===========================
; CLEANUP (close server after game exit)
; ===========================
Run('taskkill /IM winfusion.exe /F >nul 2>&1', , "Hide")

ExitApp
