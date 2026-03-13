#SingleInstance Force
SetWorkingDir A_ScriptDir

; ============================================================
; GLOBALS
; ============================================================
global serverPid := 0, clientPid := 0
global __logBuffer := []
global debugLog := A_ScriptDir "\debug_log.txt"
global wrapperStartTime

;Convert relative paths to absolute
resolvePath(p) {
    if !p
        return p
    if SubStr(p,2,1) != ":"
        return A_ScriptDir "\" p
    return p
}

Quote(x) => '"' x '"'

; ============================================================
; LOGGING FUNCTIONS
; ============================================================
; Append a message to the in-memory log buffer
Log(msg, level:="INFO") {
    global __logBuffer
    time := FormatTime(,"yyyy-MM-dd HH:mm:ss")
    __logBuffer.Push(time " [" level "] " msg "`n")
}

; Flush log buffer to disk
FlushLogs() {
    global __logBuffer, debugLog

    if (__logBuffer.Length) {
        FileAppend(StrJoin(__logBuffer), debugLog, "UTF-8")
        __logBuffer := []
    }
}

StrJoin(arr) {
    out := ""
    for v in arr
        out .= v
    return out
}

; ============================================================
; WRAPPER SHUTDOWN
; ============================================================
; Stops all timers, closes resources, and exits the application
ShutdownWrapper() {
    global serverPid

    Log("Shutting down wrapper...")

    FlushLogs()
	Log("Wrapper shutdown complete")
    ExitApp
}

; ============================================================
; PROCESS HELPERS
; ============================================================

; Close a process by PID or name
CloseProcess(pid) {
    try if ProcessExist(pid)
        ProcessClose(pid)
}

; ============================================================
; PROCESS LAUNCHING
; ============================================================
; Wrapper to start a process with optional output capture
RunCMD(cmdLine, workDir := "", hide := false) {

    options := hide ? "Hide" : ""

    try {
        Run(cmdLine, workDir, options, &pid)
    } catch {
        return -1
    }

    return pid
}

; ============================================================
; SERVER FUNCTIONS
; ============================================================
StartServer() {
    global c, serverPid
    exe := c["server"]
    
    serverPid := RunCMD('"' exe '"', c["server_dir"])
    
    if (serverPid <= 0) {
        Log("Failed to start server: " exe,"ERROR")
        return
    }
    
    Log("Started server: " exe " (PID=" serverPid ")")
}

; ============================================================
; CLIENT LAUNCH
; ============================================================
BuildClientArgs() {
    global c
    
    cache := c["cache_dir_url"]
    args := ' -m ' Quote("file:///" cache "/main.unity3d")
    args .= ' --asseturl ' Quote("file:///" cache "/")
    args .= ' -a ' Quote(c["address"])
    
    if c["username"]
        args .= ' --username ' Quote(c["username"])
    if c["token"]
        args .= ' --token ' Quote(c["token"])
    if c["log_file"]
        args .= ' -l ' Quote(c["log_file"])
    if c["force_vulkan"] = "true"
        args .= " --force-vulkan"
    if c["verbose"] = "true"
        args .= " -v"
        
    return args
}

ApplyFullscreen() {
    global clientPid, c
    
    try {
        hwnd := WinExist("ahk_pid " clientPid)
        if !hwnd
            hwnd := WinExist("ahk_exe " c["launcher_exe"])
        if !hwnd && c["window_title"]
            hwnd := WinExist(c["window_title"])

        if hwnd {
            WinSetAlwaysOnTop(true, hwnd)
            WinSetStyle("-0xC40000", hwnd)  ; Removes title bar and borders
            WinMaximize(hwnd)
            Log("Borderless fullscreen applied")

            SetTimer(ApplyFullscreen, 0)
            ShutdownWrapper()
        }
    } catch as e {
        Log("Failed to apply fullscreen: " e.Message, "ERROR")
    }
}

LaunchClient() {
    global c, clientPid

    args := BuildClientArgs()
    exe := c["launcher"]
    
    clientPid := RunCMD('"' exe '" ' args, c["launcher_dir"])

    if (clientPid <= 0) {
        Log("Failed to start client: " exe,"ERROR")
        return
    }

    Log("Started client: " exe " (PID=" clientPid ")")
    
	  if c["fullscreen"] == "true"
	      SetTimer(ApplyFullscreen, 200)
	  else
	      ShutdownWrapper()
}

; ============================================================
; MAIN
; ============================================================
Main() {
    global serverPid, clientPid

    if serverPid && !ProcessExist(serverPid) {
        Log("Server crashed","ERROR")
        ShutdownWrapper()
        return
    }

    if !clientPid
        LaunchClient()
}

LoadIniFile(path) {
    ini := Map()
    section := ""

    for line in StrSplit(FileRead(path), "`n", "`r") {

        line := Trim(line)

        if (line = "" || SubStr(line,1,1) = ";")
            continue

        if RegExMatch(line, "^\[(.+)\]$", &m) {
            section := m[1]
            ini[section] := Map()
            continue
        }

        if RegExMatch(line, "^(.*?)=(.*)$", &m) {
            key := Trim(m[1])
            val := Trim(m[2])
            if section
                ini[section][key] := val
        }
    }

    return ini
}

; ============================================================
; CONFIGURATION
; ============================================================
LoadConfig() {

    global c

    configFile := A_ScriptDir "\config.ini"

    if !FileExist(configFile) {
        MsgBox("Missing config.ini")
        ExitApp
    }

    ini := LoadIniFile(configFile)

    active := ""
    for section,data in ini
        if InStr(section,"launcher:")
        && data.Get("default","")="true" {
            if active {
                MsgBox("Multiple launchers marked default")
                ExitApp
            }
            active := section
        }

    if !active
        active := "launcher:local"

    s := ini[active]

    c := Map(
        "mode", s.Get("mode","offline"),
        "cache_dir", resolvePath(s.Get("cache_dir","")),
        "launcher", resolvePath(s.Get("launcher","")),
        "server", resolvePath(s.Get("server","")),
        "username", s.Get("username",""),
        "token", s.Get("token",""),
        "window_title", s.Get("window_title","FusionFall"),
        "force_vulkan", s.Get("force_vulkan","false"),
        "fullscreen", s.Get("fullscreen","false"),
		"verbose", s.Get("verbose","true"),
        "log_file", resolvePath(s.Get("log_file",""))
    )

    c["cache_dir_url"] := StrReplace(c["cache_dir"],"\","/")

    loginPort := ini["login"].Get("port","8023")

    c["address"] := s.Get("address","127.0.0.1:" loginPort)

    SplitPath(c["server"], &sname, &sdir)
    c["server_dir"] := sdir
    
    SplitPath(c["launcher"], &lname, &ldir)
    c["launcher_dir"] := ldir
    c["launcher_exe"] := lname
}

; ============================================================
; START WRAPPER
; ============================================================
StartWrapper() {
	global wrapperStartTime
	
	wrapperStartTime := A_TickCount
	
    LoadConfig()
	
    if c["mode"]=="offline" {
        StartServer()
    }
	
	Main()
}

; Clear old logs
if FileExist(debugLog)
    FileDelete(debugLog)

; Launch the wrapper
StartWrapper()
