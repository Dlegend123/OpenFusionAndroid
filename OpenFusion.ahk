#SingleInstance Force
SetWorkingDir A_ScriptDir
DetectHiddenWindows True

; ===========================================================
; SAFETY: initialize globals
; ===========================================================
windowTitle := "FusionFall"
launchDir := ""
serverDir := ""
serverName := ""
launcherExe := ""

; ===========================================================
; UTILS
; ===========================================================
ResolvePath(path) {
    return (path != "" && SubStr(path,2,1) != ":") ? A_ScriptDir "\" path : path
}

Join(sep, arr) {
    out := ""
    for i, val in arr
        out .= (i>1 ? sep : "") val
    return out
}

; ===========================================================
; CONFIGURATION (read INI)
; ===========================================================
configFile := A_ScriptDir "\config.ini"
if !FileExist(configFile) {
    MsgBox "Error: config.ini not found in " A_ScriptDir
    ExitApp
}

config := Map(), section := ""
for line in StrSplit(FileRead(configFile), "`n", "`r") {
    line := Trim(line)
    if (line = "" || SubStr(line,1,1) = "#" || SubStr(line,1,1) = ";")
        continue
    if RegExMatch(line, "^\[(.+)\]$", &m) {
        section := m[1]
        config[section] := Map()
        continue
    }
    if (section && InStr(line, "=")) {
        parts := StrSplit(line, "=", , 2)
        config[section][Trim(parts[1])] := Trim(parts[2])
    }
}

; ===========================================================
; SELECT ACTIVE SECTION
; ===========================================================
activeSection := ""
for k, v in config {
    if InStr(k, "launcher:") && v.Has("default") && v["default"] = "true" {
        activeSection := k
        break
    }
}
if (activeSection = "")
    activeSection := "launcher:local"

cfg := config[activeSection]
mode := cfg.Has("mode") ? cfg["mode"] : "offline"
forceVulkan := (cfg.Has("force_vulkan") && cfg["force_vulkan"] = "true")
fullscreen := (cfg.Has("fullscreen") && cfg["fullscreen"] = "true")

; ===========================================================
; PATHS & VARS
; ===========================================================
launcherExe := cfg.Has("launcher") ? ResolvePath(cfg["launcher"])  : ""
serverExe   := cfg.Has("server") ? ResolvePath(cfg["server"]) : ""
; rawCachePath is the local filesystem path (not file://)
rawCachePath := cfg.Has("cache_dir") ? ResolvePath(cfg["cache_dir"]) : ""
mainFile := (rawCachePath != "") ? rawCachePath "\main.unity3d" : ""
; assetUrl is the file:// URL form we pass to the launcher
assetUrl := (rawCachePath != "") ? "file:///" StrReplace(rawCachePath, "\", "/") "/" : ""

username    := cfg.Has("username") ? cfg["username"] : ""
token       := cfg.Has("token") ? cfg["token"] : ""
logFile     := cfg.Has("log_file") ? ResolvePath(cfg["log_file"]) : ""
loginPort   := (config.Has("login") && config["login"].Has("port")) ? config["login"]["port"] : "23000"
windowTitle := cfg.Has("window_title") ? cfg["window_title"] : "FusionFall"

; derive launcher executable name for monitoring
SplitPath(launcherExe, , &launchDir, &launcherName)

; ===========================================================
; VERIFY ESSENTIAL FILES
; ===========================================================
if (mode = "offline" && serverExe = "") {
    MsgBox "Missing server path in config (server=...)."
    ExitApp
}
if (mode = "offline" && !FileExist(serverExe)) {
    MsgBox "Missing server executable:`n" serverExe
    ExitApp
}
if (mainFile = "" || !FileExist(mainFile)) {
    MsgBox "Missing required file (main.unity3d):`n" mainFile
    ExitApp
}

; ===========================================================
; START SERVER (OFFLINE MODE)
; ===========================================================
if (mode = "offline") { 
    SplitPath(serverExe, , &serverDir, , &serverName) 
    if (serverName != "" && !ProcessExist(serverName)) { 
       Run('"' serverExe '"', serverDir, "Hide")
    } 
}

; ===========================================================
; BUILD LAUNCHER COMMAND
; ===========================================================
address := ""
endpoint := ""
if (mode = "offline")
    address := "127.0.0.1:" loginPort
else if (mode = "online") {
    if (cfg.Has("address"))
        address := cfg["address"]
    if (cfg.Has("endpoint"))
        endpoint := cfg["endpoint"]
}

ffArgs := []
ffArgs.Push('-m "' mainFile '"')
if (address != "")
    ffArgs.Push('-a "' address '"')

if (assetUrl != "")
    ffArgs.Push('--asseturl "' assetUrl '"')

if (endpoint != "")
    ffArgs.Push('--endpoint "' endpoint '"')
if (username != "" && token != "")
    ffArgs.Push('--username "' username '" --token "' token '"')
if (logFile != "")
    ffArgs.Push('-l "' logFile '"')
if (forceVulkan)
    ffArgs.Push('--force-vulkan')

ffCmd := '"' launcherExe '" ' Join(" ", ffArgs)
FileAppend(A_Now " - Launcher Command: " ffCmd "`n", A_ScriptDir "\launcher_log.txt")

; ===========================================================
; RUN LAUNCHER (detached, works better under Wine/GameHub)
; ===========================================================
if (launchDir = "")
    launchDir := A_ScriptDir

; Use start to fully detach; cmd start doesn't return PID so we will monitor by executable name.
Run('cmd /c start "" "' launcherExe '" ' Join(" ", ffArgs), launchDir, "Hide")
FileAppend(A_Now " - Launched (detached) " launcherExe "`n", A_ScriptDir "\launcher_log.txt")

; ===========================================================
; FULLSCREEN HANDLING (safe timing)
; ===========================================================
try {
    if fullscreen {
        screenW := A_ScreenWidth
        screenH := A_ScreenHeight
        WS_REMOVE := 0xC00000 | 0x00040000 | 0x20000000 | 0x01000000 | 0x00080000
        target := windowTitle
        if WinWait(target,, 12) {
            loop 4 {
                WinActivate(target)
                WinWaitActive(target,, 2)
                WinSetStyle(-WS_REMOVE, target)
                if WinMove(0, 0, screenW, screenH, target)
                    break
                Sleep 100
            }
        }
    }
} catch Error as err {
    FileAppend(A_Now " - Fullscreen error: " err.Message "`n", A_ScriptDir "\launcher_log.txt")
}

ExitApp
