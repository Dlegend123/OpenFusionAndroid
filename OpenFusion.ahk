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

; ================================
; FUNCTIONS
; ================================

; Waits for a specific line to appear in a file, with timeout in seconds
WaitForServerLogLine(logFile, text, timeout := 15) {
    start := A_TickCount
    loop {
        Sleep(500)
        if FileExist(logFile) {
            data := FileRead(logFile)
            if InStr(data, text) {
                return true
            }
        }
        if (A_TickCount - start >= timeout*1000)
            return false
    }
}

; Run an executable with optional admin privileges and hidden window
RunExeAsAdmin(exePath, params := "", workingDir := "", hide := false) {
    if (exePath = "")
        return false

    opts := ""
    if (hide)
        opts := "Hide RunAs"
    else
        opts := "RunAs"

    ; Determine working directory
    if (workingDir = "")
        SplitPath(exePath, , &workingDir)
    if (workingDir = "")
        workingDir := A_ScriptDir

    Run('"' . exePath . '" ' . params, workingDir, opts)
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
mainFile := (rawCachePath != "") ? "file:///" StrReplace(rawCachePath, "\", "/") "/main.unity3d" : ""
assetUrl := (rawCachePath != "") ? "file:///" StrReplace(rawCachePath, "\", "/") "/" : ""
username    := cfg.Has("username") ? cfg["username"] : ""
token       := cfg.Has("token") ? cfg["token"] : ""
logFile     := cfg.Has("log_file") ? ResolvePath(cfg["log_file"]) : ""
loginPort   := (config.Has("login") && config["login"].Has("port")) ? config["login"]["port"] : "23000"
windowTitle := cfg.Has("window_title") ? cfg["window_title"] : "FusionFall"
launcherLog := A_ScriptDir "\launcher_log.txt"
timeoutSec := 15

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

if (mainFile = "") {
    MsgBox "Missing required file (main.unity3d):`n" mainFile
    ExitApp
}

; ===========================================================
; START SERVER (OFFLINE MODE)
; ===========================================================
if (mode = "offline") {
    SplitPath(serverExe, , &serverDir, , &serverName)
    if (serverName != "") {
        ; Run server hidden
        serverLog := A_ScriptDir "\server_output.txt"

        ; Launch the server hidden and redirect output to a file
        Run(
            'cmd.exe /c start "" /b "' serverExe '" > "' serverLog '" 2>&1',
            serverDir,
            "Hide",
            &pid
        )

    }
}

; ================================
; WAIT FOR SERVER READY LINE
; ================================
FileAppend(A_Now " - Waiting for server to start..." "`n", launcherLog)
if (!WaitForServerLogLine(serverLog, "Starting shard server at", timeoutSec)) {
    FileAppend(A_Now " - ERROR: Server did not start within timeout." "`n", launcherLog)
    MsgBox("Server failed to start within " timeoutSec " seconds. See log.")
}
else{
    FileAppend(A_Now " - Server is ready!" "`n", launcherLog)
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
FileAppend(A_Now " - Launcher Command: " ffCmd "`n", launcherLog)

; ===========================================================
; RUN LAUNCHER (detached, works better under Wine/GameHub)
; ===========================================================
if (launchDir = "")
    launchDir := A_ScriptDir

RunExeAsAdmin(launcherExe, Join(" ", ffArgs), launchDir)
FileAppend(A_Now . " - Launched (detached) " . launcherExe . "`n", launcherLog)

; ===========================================================
; FULLSCREEN HANDLING
; ===========================================================
try {
    if fullscreen {
        ; Wait for the launcher window to appear
        if WinWait(windowTitle, , 15) { ; wait up to 15 sec
            WinActivate(windowTitle)
            WinWaitActive(windowTitle, , 5) ; wait up to 5 sec for it to be active

            ; Remove window styles and resize
            WS_REMOVE := 0xC00000 | 0x00040000 | 0x20000000 | 0x01000000 | 0x00080000
            WinSetStyle(-WS_REMOVE, windowTitle)
            WinMove(0, 0, A_ScreenWidth, A_ScreenHeight, windowTitle)
        } else {
            FileAppend(A_Now " - ERROR: Launcher window did not appear in time." "`n", launcherLog)
        }
    }
} catch as e {
    FileAppend(A_Now . " - Fullscreen error: " . e.Message . "`n", launcherLog)
}

ExitApp