#SingleInstance Force
SetWorkingDir A_ScriptDir

; ============================================================
; GLOBAL STATE
; ============================================================
global serverPid := 0
global clientPid := 0
global debugLog := A_ScriptDir "\debug_log.txt"

; ============================================================
; LOGGING FUNCTIONS
; ============================================================
; Append a message to the in-memory log buffer
global __logBuffer := ""

Log(msg, level := "INFO", flush := false) {
    global __logBuffer

    __logBuffer .= FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " msg "`n"

    if flush || StrLen(__logBuffer) > 65536
        FlushLogs()
}

FlushLogs() {
    global __logBuffer, debugLog

    if (__logBuffer != "") {
        FileAppend(__logBuffer, debugLog, "UTF-8")
        __logBuffer := ""
    }
}

; ============================================================
; UTIL
; ============================================================
ResolvePath(p) {
    return (p != "" && !InStr(p, ":"))
        ? A_ScriptDir "\" p
        : p
}

Quote(x) => '"' x '"'

AddArg(&args, flag, val) {
    if val
        args .= " " flag " " Quote(val)
}

StrJoin(arr, delim := "") {
    if !arr.Length
        return ""

    out := arr[1]

    Loop arr.Length - 1
        out .= delim arr[A_Index + 1]

    return out
}

BuildEnvironment() {
    global c

    EnvSet("UNITY_FF_FPS_CAP", c["fps_limit"])

    ; Disable Wine FSR for PC emulators to prevent conflicts with other display enhancements.
	EnvSet("WINE_FULLSCREEN_FSR", "0")
	EnvSet("WINE_FULLSCREEN_FSR_MODE", "0")

    if (c["dxvk_hud"] = "true")
        EnvSet("DXVK_HUD", "1")
}

; ============================================================
; SERVER START
; ============================================================

StartServer() {
    global c, serverPid

    Log("Starting server...")
 
	Run(c["server"], c["server_dir"], , &serverPid)

    if !serverPid {
        MsgBox "Server failed to start"
        ExitApp
    }
}

; ============================================================
; CLIENT ARGS (Rust prep_launch equivalent simplified)
; ============================================================
BuildClientArgs() {
    global c

    cache := "file:///" StrReplace(c["cache_dir"],"\","/") "/"
	
    args := ""
	args .= ' -m ' Quote(cache "main.unity3d")
	args .= ' --asseturl ' Quote(cache)
	args .= ' -a ' Quote(c["address"])
	
	AddArg(&args, "--username", c["username"])
	AddArg(&args, "--token", c["token"])
	AddArg(&args, "-l", c["log_file"])
	
	if (c["graphics_api"] = "opengl")
		args .= " --force-opengl"

	if (c["graphics_api"] = "vulkan")
		args .= " --force-vulkan"
		
	if (c["fullscreen"] = "true") {
		AddArg(&args, "--width", A_ScreenWidth)
		AddArg(&args, "--height", A_ScreenHeight)
    }
    
	if c["verbose"] = "true"
        args .= " -v"
		
    return args
}

; ============================================================
; CLIENT MONITOR (Rust: proc.wait())
; THIS IS THE CRITICAL FIX YOU WERE MISSING
; ============================================================
WaitClient() {
    global clientPid, serverPid

    ProcessWaitClose(clientPid)

    if serverPid
        ProcessClose(serverPid)

    ExitApp
}

; ============================================================
; CLIENT LAUNCH (Rust: proc.spawn + wait)
; ============================================================

SpawnClient() {
    global c, clientPid

    args := BuildClientArgs()
    BuildEnvironment()

	Run(c["launcher"] " " args, c["launcher_dir"], ,&clientPid)

    if !clientPid {
        Log("Client spawn FAILED", "ERROR", true)
        MsgBox "Client spawn failed"
        ExitApp
    }

    Log("Client PID: " clientPid, "INFO", true)
}

; ============================================================
; FULLSCREEN
; ============================================================
ApplyFullscreen() {
    global clientPid

    Loop 50 { ; retry for ~5 seconds
        hwnd := WinExist("ahk_pid " clientPid)

        if hwnd {
            WinSetStyle("-0xC40000", hwnd)
            WinSetStyle("-0x40000", hwnd)
            WinMove(0, 0, A_ScreenWidth, A_ScreenHeight, hwnd)
			
			; --- ADDED FOR FOREGROUND/TOPMOST ---
            WinSetAlwaysOnTop(1, hwnd) ; Forces window to stay on top
            WinActivate(hwnd)          ; Activates the window
            ; ------------------------------------
			
            return
        }

        Sleep(100)
    }
}

; ============================================================
; MAIN FLOW (Rust run() equivalent runtime flow)
; ============================================================
Main() {
    global c, serverPid
	
	LoadConfig()

    if (c["mode"] = "offline")
        StartServer()

    SpawnClient()
    
    if (c["fullscreen"] = "true")
		ApplyFullscreen()
	
	WaitClient()
}

LoadIniFile(path) {
    ini := Map()
    section := ""

    for line in StrSplit(FileRead(path), "`n", "`r") {
        line := Trim(line)

        if (line = "" || SubStr(line, 1, 1) = ";")
            continue

        ; [section]
        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            section := SubStr(line, 2, -1)
            ini[section] := Map()
            continue
        }

        ; key=value
        pos := InStr(line, "=")
        if (pos && section) {
            key := Trim(SubStr(line, 1, pos - 1))
            val := Trim(SubStr(line, pos + 1))
            ini[section][key] := val
        }
    }

    return ini
}

; ============================================================
; CONFIG (minimal placeholder)
; ============================================================
LoadConfig() {
    global c

    iniPath := A_ScriptDir "\config.ini"

    if !FileExist(iniPath) {
        MsgBox "Config file not found: " iniPath
        ExitApp
    }

    ini := LoadIniFile(iniPath)

    ; =========================
    ; SELECT SECTION (FAST)
    ; =========================
    selected := ""

    for section, data in ini {
        if InStr(section, "config:")
        && data.Get("default", "") = "true" {
            if selected {
                MsgBox("Multiple sections marked default")
                ExitApp
            }
            selected := section
        }
    }

    if !selected
        selected := "config:local"

    section := ini.Get(selected, Map())

    ; =========================
    ; FAST READER (NO DISK)
    ; =========================
    Read(k, fallback := "") {
        return section.Has(k) ? section[k] : fallback
    }

    ; =========================
    ; BUILD CONFIG
    ; =========================
    c := Map()

    c["mode"] := Read("mode", "offline")

    launcher := Read("client", Read("launcher"))
    server   := Read("server")

    if !FileExist(launcher) {
        MsgBox "Client not found:`n" launcher
        ExitApp
    }

    if !FileExist(server) && (c["mode"] = "offline") {
        MsgBox "Server not found:`n" server
        ExitApp
    }

	; derive directories safely
    c["server"]   := ResolvePath(server)
    c["launcher"] := ResolvePath(launcher)
    c["cache_dir"] := ResolvePath(Read("cache_dir"))

    SplitPath(c["server"], , &serverDir)
    SplitPath(c["launcher"], , &launcherDir)

    c["server_dir"]   := serverDir
    c["launcher_dir"] := launcherDir

	; ============================================================
    ; NETWORK
    ; ============================================================
    c["address"] := Read("address")
    c["username"] := Read("username")
    c["token"] := Read("token")

    ; ============================================================
    ; LOGGING
    ; ============================================================
    c["log_file"] := ResolvePath(Read("log_file"))
	c["verbose"] := Read("verbose")
	
    ; ============================================================
    ; GRAPHICS
    ; ============================================================
    c["dxvk_hud"] := Read("dxvk_hud", "false")
	
	fps := Read("fps_limit")
    c["fps_limit"] := fps ? String(fps) : "60"
	
    c["graphics_api"] := Read("graphics_api")
    
	; ============================================================
    ; WINDOW
    ; ============================================================
    c["fullscreen"] := Read("fullscreen", "true")
}

; Clear old logs
if FileExist(debugLog)
    FileDelete(debugLog)
    
; ============================================================
; ENTRYPOINT
; ============================================================
Main()