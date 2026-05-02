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
    SplitPath(c["server"], , &serverDir)
    SplitPath(c["launcher"], , &launcherDir)

    c["server_dir"] := serverDir
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
	c["fps_limit"] := Read("fps_limit", "")
    c["graphics_api"] := Read("graphics_api", "dx9")
	c["fps_fix"] := Read("fps_fix")
    
	; ============================================================
    ; WINDOW
    ; ============================================================
    c["fullscreen"] := Read("fullscreen", "false")
   
	
}


; ============================================================
; ENTRYPOINT
; ============================================================
StartWrapper() {
    Log("=== WRAPPER START ===", "INFO", true)

    LoadConfig()
    Main()

    Log("=== WRAPPER END ===", "INFO", true)
}
; Clear old logs
if FileExist(debugLog)
    FileDelete(debugLog)

StartWrapper()