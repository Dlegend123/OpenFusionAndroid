#SingleInstance Force
SetWorkingDir A_ScriptDir
DetectHiddenWindows True

; ===========================
; CONFIGURATION
; ===========================
SERVER_DIR   := A_ScriptDir "\OpenFusionServer"
LAUNCHER_DIR := A_ScriptDir "\OpenFusionLauncher"
VERSION_UUID := "6543a2bb-d154-4087-b9ee-3c8aa778580a"
CACHE_DIR    := LAUNCHER_DIR "\offline_cache\" VERSION_UUID
MAIN_FILE    := CACHE_DIR "\main.unity3d"
ASSET_URL    := "file:///" StrReplace(CACHE_DIR, "\", "/") "/"
LOG_FILE     := LAUNCHER_DIR "\ffrunner_output.txt"
ADDRESS      := "127.0.0.1:23000"

; ===========================
; VERIFY FILES
; ===========================
missing := ""
if !DirExist(SERVER_DIR)
    missing .= "- Missing server folder:`n" SERVER_DIR "`n`n"
if !FileExist(SERVER_DIR "\winfusion.exe")
    missing .= "- Missing winfusion.exe in server folder.`n`n"
if !DirExist(LAUNCHER_DIR)
    missing .= "- Missing launcher folder:`n" LAUNCHER_DIR "`n`n"
if !DirExist(CACHE_DIR)
    missing .= "- Missing cache directory:`n" CACHE_DIR "`n`n"
if !FileExist(MAIN_FILE)
    missing .= "- Missing main.unity3d:`n" MAIN_FILE "`n`n"

if (missing) {
    MsgBox("The following required items were not found:`n`n" missing, "Missing Files", "Icon! 4096")
    ExitApp
}

; ===========================
; START SERVER (hidden)
; ===========================
Run('"' SERVER_DIR '\winfusion.exe"', SERVER_DIR, "Hide")

; ===========================
; RUN GAME (wait until exit)
; ===========================
ffCmd := 'ffrunner.exe --force-vulkan '
    . '-m "' MAIN_FILE '" '
    . '-a "' ADDRESS '" '
    . '--asseturl "' ASSET_URL '" '
    . '-l "' LOG_FILE '" '

RunWait(ffCmd, LAUNCHER_DIR)

; ===========================
; CLEANUP (force close server)
; ===========================
RunWait('taskkill /IM winfusion.exe /F >nul 2>&1', , "Hide")

ExitApp
