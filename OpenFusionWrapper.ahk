#SingleInstance Force
SetWorkingDir A_ScriptDir

; ============================================================
; GLOBAL STATE
; ============================================================
global serverPid := 0
global clientPid := 0
global debugLog := A_ScriptDir "\debug_log.txt"
global ctx := Map()

; ============================================================
; LOGGING FUNCTIONS
; ============================================================
; Append a message to the in-memory log buffer
Log(msg, level:="INFO", flush:=false) {
    global __logBuffer
    time := FormatTime(,"yyyy-MM-dd HH:mm:ss")
    line := time " [" level "] " msg "`n"
    __logBuffer .= line

    if (flush)
        FlushLogs()
}

; Flush log buffer to disk
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
ResolvePath(p) => (Trim(p) && SubStr(p,2,1)!=":") ? A_ScriptDir "\" p : p ; Convert relative paths to absolute

Quote(x) => '"' x '"'

; ============================================================
; CLEAN SHUTDOWN (Rust: app_handle.exit + proxy.abort)
; ============================================================
ShutdownWrapper(exitCode := 0) {
    global serverPid
	
    ; kill server if still running
    if serverPid
        CloseProcess(serverPid)

    ExitApp exitCode
}

CloseProcess(pid) {
    try if ProcessExist(pid)
        ProcessClose(pid)
}

; ============================================================
; ENV (Rust: cmd.env(...) section)
; ============================================================
BuildEnvironment() {
    global c

    env := Map()

    if !c["fps_fix"]
		env["UNITY_FF_FPS_CAP"] := "old"
	else if c["fps_limit"]
		env["UNITY_FF_FPS_CAP"] := c["fps_limit"]

    if (c["dxvk_hud"] = "true")
        env["DXVK_HUD"] := "1"

    return env
}

WaitClient() {
    global clientPid, launchBehavior, serverPid

    Log("Waiting for client PID: " clientPid)

	ProcessWaitClose(clientPid)

	if serverPid {
		Log("Closing server PID: " serverPid)
		CloseProcess(serverPid)
	}

    ExitApp 0
}
; ============================================================
; SERVER START
; ============================================================

StartServer() {
    global c, serverPid

    cmd := Quote(c["server"])

	Log("Starting server...")
	Log("Server EXE: " c["server"])
	Log("Server Dir: " c["server_dir"])
	FlushLogs()
    
	spec := {
		exe: c["server"],
		cmdLine: "",
		workDir: c["server_dir"],
		env: Map()  ; or omit entirely
	}
	
	serverPid := Spawn(spec)
	
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

    cache := StrReplace(c["cache_dir"],"\","/")

    args := ""
    args .= ' -m ' Quote("file:///" cache "/main.unity3d")
    args .= ' --asseturl ' Quote("file:///" cache "/")
    args .= ' -a ' Quote(c["address"])

    if c["username"]
        args .= ' --username ' Quote(c["username"])

    if c["token"]
        args .= ' --token ' Quote(c["token"])

    if c["log_file"]
        args .= ' -l ' Quote(c["log_file"])

    if (c["fullscreen"] = "true") {
        args .= " --width " A_ScreenWidth
        args .= " --height " A_ScreenHeight
    }

	if (c["graphics_api"] = "opengl")
		args .= " --force-opengl"

	if (c["graphics_api"] = "vulkan")
		args .= " --force-vulkan"
	
	if c["verbose"] = "true"
        args .= " -v"
		
    return args
}

BuildCommand() {
    global ctx

    cmd := Quote(ctx.launchExe) " " ctx.args

    return cmd
}

; ============================================================
; FULLSCREEN (FIXED — was previously incomplete)
; ============================================================
ApplyFullscreen() {
    global clientPid

    try {
        hwnd := WinExist("ahk_pid " clientPid)
        if hwnd {
            WinSetStyle("-0xC40000", hwnd)
			WinMaximize(hwnd)
			
            SetTimer(ApplyFullscreen, 0)
        }
    }
}


; ============================================================
; CLIENT MONITOR (Rust: proc.wait())
; THIS IS THE CRITICAL FIX YOU WERE MISSING
; ============================================================
MonitorClient() {
    global clientPid, serverPid
	
    if !ProcessExist(clientPid) {
        ShutdownWrapper()
    }
}
; ============================================================
; CLIENT LAUNCH (Rust: proc.spawn + wait)
; ============================================================

PrepLaunch() {
    global ctx, c

    Log("PrepLaunch() start")

    ctx.launchExe := c["launcher"]
    ctx.workDir   := c["launcher_dir"]

    ctx.args := BuildClientArgs()
    ctx.env  := BuildEnvironment()

    ctx.cmd := BuildCommand()

    Log("Launch EXE: " ctx.launchExe)
    Log("Args: " ctx.args)
    Log("WorkDir: " ctx.workDir)
    FlushLogs()
}

SpawnClient() {
    global ctx, clientPid

    Log("Spawning client...")

    spec := {
        exe: ctx.launchExe,
        cmdLine: ctx.args,
        workDir: ctx.workDir,
        env: ctx.env
    }

    clientPid := Spawn(spec)

    if !clientPid {
        Log("Client spawn FAILED", "ERROR", true)
        MsgBox "Client spawn failed"
        ExitApp
    }

    Log("Client PID: " clientPid, "INFO", true)
}

Spawn(spec) {

    siSize := (A_PtrSize = 8 ? 104 : 68)
    si := Buffer(siSize, 0)
    NumPut("UInt", siSize, si, 0)

    pi := Buffer(A_PtrSize * 4, 0)

	envBlock := ""
	envLog := "ENV BLOCK:`n"

	for k, v in spec.env {
		if (v != "") {
			line := k "=" v
			envBlock .= line Chr(0)
			envLog .= "  " line "`n"
		}
	}
	envBlock .= Chr(0)

	Log(envLog, "INFO", true)
	
    envBuf := Buffer(StrPut(envBlock, "UTF-16") * 2, 0)
    StrPut(envBlock, envBuf, "UTF-16")

    exe := spec.exe
    cmdLine := spec.cmdLine

    Log("=== Spawn() WINDOWS ===")
    Log("EXE: " exe)
    Log("CMDLINE: " cmdLine)
	
    ok := DllCall("CreateProcessW",
        "Str", exe,
        "Str", cmdLine,
        "Ptr", 0,
        "Ptr", 0,
        "Int", false,
        "UInt", 0x00000400 | 0x08000000,
        "Ptr", envBuf,
        "Str", spec.workDir,
        "Ptr", si,
        "Ptr", pi
    )

    if (!ok) {
        err := DllCall("GetLastError")
        Log("CreateProcess FAILED: " err, "ERROR", true)
        return 0
    }

    hProcess := NumGet(pi, 0, "Ptr")
    hThread  := NumGet(pi, A_PtrSize, "Ptr")

    pid := DllCall("GetProcessId", "Ptr", hProcess, "UInt")

    DllCall("CloseHandle", "Ptr", hThread)
    DllCall("CloseHandle", "Ptr", hProcess)

    return pid
}

; ============================================================
; MAIN FLOW (Rust run() equivalent runtime flow)
; ============================================================
Main() {
    global c, serverPid

    PrepLaunch()

    if (c["mode"] = "offline")
        StartServer()

    SpawnClient()
    if (c["fullscreen"] = "true")
		SetTimer(ApplyFullscreen, 400)

	WaitClient()
}


; ============================================================
; CONFIG (minimal placeholder)
; ============================================================
LoadConfig() {
    global c

    iniPath := A_ScriptDir "\config.ini"

    if !FileExist(iniPath) {
        MsgBox "Config not found: " iniPath
        ExitApp
    }
	

    ; ============================================================
    ; PICK DEFAULT SECTION (SAFE + RELIABLE)
    ; ============================================================
    sections := ["launcher:local", "launcher:retro"]
    selected := ""

    for _, sec in sections {
        val := IniRead(iniPath, sec, "default", "false")
        if (val = "true") {
            if selected {
                MsgBox "Multiple launchers marked default"
                ExitApp
            }
            selected := sec
        }
    }

    if !selected
        selected := "launcher:local"

    ; ============================================================
    ; SAFE INI READER
    ; ============================================================
    Read(k, fallback := "") {
        return IniRead(iniPath, selected, k, fallback)
    }

    ; ============================================================
    ; CONFIG MAP
    ; ============================================================
    c := Map()

    ; core
    c["mode"] := Read("mode", "offline")

    ; ============================================================
    ; PATH HANDLING (FIXED)
    ; ============================================================
	launcher := Read("launcher")
	server :=  Read("server")
	if !FileExist(launcher) {
		MsgBox "Launcher not found:`n" c["launcher"]
		ExitApp
	}

	if !FileExist(server) && (c["mode"] = "offline") {
		MsgBox "Server not found:`n" c["server"]
		ExitApp
	}
	
    c["server"] := ResolvePath(server)
    c["launcher"] := ResolvePath(launcher)
    c["cache_dir"] := ResolvePath(Read("cache_dir"))

    ; derive directories safely (NO ResolvePath here)
﻿#SingleInstance Force
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

; ============================================================
; ENV (Rust: cmd.env(...) section)
; ============================================================
EnvGetAll() {
    env := Map()

    p := DllCall("GetEnvironmentStringsW", "ptr")
    if !p
        return env

    ptr := p

    while (str := StrGet(ptr, "UTF-16")) {
        pos := InStr(str, "=")

        if (pos > 1) {
            env[SubStr(str, 1, pos - 1)] := SubStr(str, pos + 1)
        }

        ptr += (StrLen(str) + 1) * 2
    }

    DllCall("FreeEnvironmentStringsW", "ptr", p)

    return env
}

BuildEnvironment() {
    global c

    EnvSet("UNITY_FF_FPS_CAP", c["fps_limit"])
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
        args .= " --width " A_ScreenWidth
        args .= " --height " A_ScreenHeight
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
; MAIN FLOW (Rust run() equivalent runtime flow)
; ============================================================
Main() {
    global c, serverPid
	
	LoadConfig()

    if (c["mode"] = "offline")
        StartServer()

    SpawnClient()
    
    if (c["fullscreen"] = "true") {
		if hwnd := WinWait("ahk_pid " clientPid, , 10) {
			WinSetStyle("-0xC40000", hwnd)
			WinMove(0, 0, A_ScreenWidth, A_ScreenHeight, hwnd)
			WinRedraw(hwnd)
		}
	}
	
	if c["verbose"] = "true" {
		env := EnvGetAll()
		envBlock := "ENV DUMP:`n"

		for k, v in env
			envBlock .= "`t" k " = " v "`n"
		
		Log(envBlock, "ENV", true)
	}
	
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
        MsgBox "Config not found: " iniPath
        ExitApp
    }

    ini := LoadIniFile(iniPath)

    ; =========================
    ; SELECT SECTION (FAST)
    ; =========================
    selected := ""

    for section, data in ini {
        if InStr(section, "launcher:")
        && data.Get("default", "") = "true" {
            if selected {
                MsgBox("Multiple launchers marked default")
                ExitApp
            }
            selected := section
        }
    }

    if !selected
        selected := "launcher:local"

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

    launcher := Read("launcher")
    server   := Read("server")

    if !FileExist(launcher) {
        MsgBox "Launcher not found:`n" launcher
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
