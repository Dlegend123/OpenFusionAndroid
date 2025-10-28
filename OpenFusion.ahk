#SingleInstance Force
SetWorkingDir A_ScriptDir
DetectHiddenWindows True

; ===========================
; CONFIGURATION
; ===========================
configFile := A_ScriptDir "\config.ini"

if !FileExist(configFile) {
    MsgBox "Error: config.ini not found in " A_ScriptDir
    ExitApp
}

config := Map()
section := ""

; --- Parse config.ini into nested maps ---
For line in StrSplit(FileRead(configFile), "`n", "`r") {
    line := Trim(line)
    if (line = "" || SubStr(line, 1, 1) = "#")
        continue
    if RegExMatch(line, "^\[(.+)\]$", &m) {
        section := m[1]
        config[section] := Map()
        continue
    }
    if (section != "" && InStr(line, "=")) {
        parts := StrSplit(line, "=", , 2)
        key := Trim(parts[1])
        value := Trim(parts[2])
        config[section][key] := value
    }
}

; ===========================
; LOAD CONFIG VALUES
; ===========================
try {
    LAUNCHER_DIR := config["launcher"]["launcher_dir"]
    CACHE_DIR := config["launcher"]["cache_dir"]
    VERSION_UUID := config["launcher"]["version_uuid"]
    LOGIN_PORT := config["login"]["port"]
    SERVER_DIR := config["launcher"]["server_dir"]
} catch {
    MsgBox "Error: Missing one or more required config values in config.ini."
    ExitApp
}

; resolve relative paths
if (SubStr(SERVER_DIR, 2, 1) != ":")
	SERVER_DIR := A_ScriptDir "\" SERVER_DIR
if (SubStr(LAUNCHER_DIR, 2, 1) != ":")
	LAUNCHER_DIR := A_ScriptDir "\" LAUNCHER_DIR
if (SubStr(CACHE_DIR, 2, 1) != ":")
	CACHE_DIR := A_ScriptDir "\" CACHE_DIR

; ===========================
; BUILD PATHS
; ===========================
VERSION_PATH := CACHE_DIR "\" VERSION_UUID
MAIN_FILE := VERSION_PATH "\main.unity3d"
ASSET_URL := "file:///" StrReplace(VERSION_PATH, "\", "/") "/"
ADDRESS := "127.0.0.1:" LOGIN_PORT

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
if !DirExist(VERSION_PATH)
    missing .= "- Missing cache directory:`n" VERSION_PATH "`n`n"
if !FileExist(MAIN_FILE)
    missing .= "- Missing main.unity3d:`n" MAIN_FILE "`n`n"

if (missing != "") {
    MsgBox "The following required items were not found:`n`n" missing, "Missing Files", "Icon! 4096"
    ExitApp
}

; ===========================
; START SERVER IF NOT RUNNING
; ===========================
if !ProcessExist("winfusion.exe") {
    Run('*RunAs "' SERVER_DIR '\winfusion.exe"', SERVER_DIR, "Hide UseErrorLevel")
    Sleep 4000 ; allow minimal startup
}

; ===========================
; LAUNCH FFRUNNER
; ===========================
USERNAME := config.Has("launcher") && config["launcher"].Has("username") ? config["launcher"]["username"] : ""
TOKEN    := config.Has("launcher") && config["launcher"].Has("token") ? config["launcher"]["token"] : ""
WIDTH    := config.Has("launcher") && config["launcher"].Has("width") ? config["launcher"]["width"] : ""
HEIGHT   := config.Has("launcher") && config["launcher"].Has("height") ? config["launcher"]["height"] : ""
LOG_FILE := config.Has("launcher") && config["launcher"].Has("log_file") ? config["launcher"]["log_file"] : ""

ffCmd := 'ffrunner.exe -m "' MAIN_FILE '" -a "' ADDRESS '" --asseturl "' ASSET_URL '" '
if (USERNAME != "" && TOKEN != "")
    ffCmd .= '--username "' USERNAME '" --token "' TOKEN '" '
if (WIDTH != "" && HEIGHT != "")
    ffCmd .= '--width ' WIDTH ' --height ' HEIGHT ' '
if (LOG_FILE != "")
    ffCmd .= '-l "' LOG_FILE '" '

; --- Detach ffrunner process to avoid "Not Responding" in Android/Emulated environments ---
Run('cmd.exe /C start "" ' ffCmd, LAUNCHER_DIR, "UseErrorLevel")

ExitApp