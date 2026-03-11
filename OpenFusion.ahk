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

    ; Close server process if running
    if serverPid {
        CloseProcess(serverPid)
        serverPid := 0
    }

    Log("Wrapper shutdown complete")
    FlushLogs()
    ExitApp
}

; ============================================================
; PROCESS HELPERS
; ============================================================
; Get the PID of a child process for a given parent PID
GetChildProcess(parentPID) {
    TH32CS_SNAPPROCESS := 0x00000002
    PROCESSENTRY32_SIZE := (A_PtrSize = 8) ? 568 : 556

    snapshot := DllCall("CreateToolhelp32Snapshot","UInt",TH32CS_SNAPPROCESS,"UInt",0,"Ptr")
    
	if snapshot = -1
		return 0

    pe := Buffer(PROCESSENTRY32_SIZE,0)
    NumPut("UInt",PROCESSENTRY32_SIZE,pe)

    if !DllCall("Process32First","Ptr",snapshot,"Ptr",pe) {
        DllCall("CloseHandle","Ptr",snapshot)
        return 0
    }

    loop {
        ppid := NumGet(pe, A_PtrSize=8 ? 32 : 24, "UInt")
        if (ppid = parentPID) {
            pid := NumGet(pe,8,"UInt")
            DllCall("CloseHandle","Ptr",snapshot)
            return pid
        }
    } until !DllCall("Process32Next","Ptr",snapshot,"Ptr",pe)

    DllCall("CloseHandle","Ptr",snapshot)
    return 0
}

; Close a process by PID or name
CloseProcess(pid) {
    try if ProcessExist(pid)
        ProcessClose(pid)
}

; Follow a process chain to get the real PID (child process)
ResolvePID(pid) {
    while (child := GetChildProcess(pid)) && child != pid
        pid := child
    return pid
}

; ============================================================
; PROCESS LAUNCHING
; ============================================================
; Prepare STARTUPINFO struct for CreateProcess
PrepareStartupInfo(hide) {
    P8 := (A_PtrSize = 8)
    siSize := P8 ? 104 : 68
    si := Buffer(siSize,0)

    NumPut("UInt", siSize, si, 0)

    if hide {
        STARTF_USESHOWWINDOW := 0x1
        NumPut("UInt", STARTF_USESHOWWINDOW, si, P8?60:44)
        NumPut("UShort", 0, si, P8?64:48) ; SW_HIDE
    }

    return si
}

; Launch a process via CreateProcessW
LaunchProcess(cmdLine, workDir, si, hide) {
    P8 := (A_PtrSize = 8)
    pi := Buffer(P8?24:16,0)
	flags := hide ? 0x08000000 : 0  ; CREATE_NO_WINDOW only when hiding
    cmdBuf := Buffer((StrLen(cmdLine)+1)*2)
    StrPut(cmdLine, cmdBuf, "UTF-16")
    wdPtr := 0
    
    if workDir {
        dirBuf := Buffer((StrLen(workDir)+1)*2)
        StrPut(workDir, dirBuf, "UTF-16")
        wdPtr := dirBuf.Ptr
    }

    success := DllCall("CreateProcessW", "ptr",0, "ptr",cmdBuf, "ptr",0, "ptr",0, "int", 0, "int",flags, "ptr",0, "ptr",wdPtr, "ptr",si, "ptr",pi)
    if !success
        return -1

    ; Close thread/process handles
    if P8 {
        DllCall("CloseHandle","ptr",NumGet(pi,0,"Ptr"))
        DllCall("CloseHandle","ptr",NumGet(pi,8,"Ptr"))
    } else {
        DllCall("CloseHandle","ptr",NumGet(pi,0,"Ptr"))
        DllCall("CloseHandle","ptr",NumGet(pi,4,"Ptr"))
    }

    return P8 ? NumGet(pi,16,"UInt") : NumGet(pi,8,"UInt")
}

; Wrapper to start a process with optional output capture
RunCMD(cmdLine, workDir:="", hide:=false) {
    si := PrepareStartupInfo(hide)
    pid := LaunchProcess(cmdLine, workDir, si, hide)
	
	return pid > 0 ? ResolvePID(pid) : pid
}

; ============================================================
; SERVER FUNCTIONS
; ============================================================
StartServer() {
    global c, serverPid
    exe := c["server"]
    
    serverPid := RunCMD('"' exe '"', c["server_dir"])
    
    if (serverPid <= 0) {
        errCode := DllCall("Kernel32\GetLastError")
        MsgBox("Server failed to start.`nWinErr=" errCode)
        Log("Failed to start server: " exe " WinErr=" errCode,"ERROR")
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
    			WinSetStyle("-0xC40000", hwnd)
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
        errCode := DllCall("Kernel32\GetLastError")
        MsgBox("Client failed to start.`nWinErr=" errCode)
        Log("Failed to start client: " exe " WinErr=" errCode,"ERROR")
        return
    }

    Log("Started client: " exe " (PID=" clientPid ")")

    if (c["fullscreen"] == "true")
        SetTimer(ApplyFullscreen, 100)
		
	;SetTimer(MonitorClient, 200)
}

MonitorClient() {
    global clientPid, c
	
    if !ProcessExist(clientPid) {
        SetTimer(MonitorClient, 0)
        SetTimer(ApplyFullscreen, 0)
        ShutdownWrapper()
    }
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
        "log_file", resolvePath(s.Get("log_file",""))
    )

    c["cache_dir_url"] := StrReplace(c["cache_dir"],"\","/")

    loginPort := ini["login"].Get("port","8023")
    shardPort := ini["shard"].Get("port","8024")

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
