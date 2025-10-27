#SingleInstance Force
SetWorkingDir A_ScriptDir
DetectHiddenWindows True

; ===========================
; CONFIGURATION
; ===========================
serverDir  := A_ScriptDir "\OpenFusionServer"
launcherDir := A_ScriptDir "\OpenFusionLauncher"
uuid       := "6543a2bb-d154-4087-b9ee-3c8aa778580a"
cacheDir   := launcherDir "\offline_cache\" uuid
mainFile   := cacheDir "\main.unity3d"
logFile    := launcherDir "\ffrunner_output.txt"
configFile := serverDir "\config.ini"
address    := "127.0.0.1:23000"  ; default / fallback
assetUrl   := "file:///" StrReplace(cacheDir, "\", "/") "/"

; ===========================
; VERIFY FILES & FOLDERS
; ===========================
missing := ""
if !DirExist(serverDir)
    missing .= "- Missing server folder:`n" serverDir "`n`n"
if !FileExist(serverDir "\winfusion.exe")
    missing .= "- Missing winfusion.exe in server folder.`n`n"
if !DirExist(launcherDir)
    missing .= "- Missing launcher folder:`n" launcherDir "`n`n"
if !DirExist(cacheDir)
    missing .= "- Missing cache directory:`n" cacheDir "`n`n"
if !FileExist(mainFile)
    missing .= "- Missing main.unity3d:`n" mainFile "`n`n"

if (missing) {
    MsgBox("The following required items were not found:`n`n" missing, "Missing Files", "Icon! 4096")
    ExitApp
}

; ===========================
; READ PORT FROM CONFIG
; ===========================
if FileExist(configFile) {
    text := FileRead(configFile)
    if RegExMatch(text, "\[login\][^\[]*?port\s*=\s*(\d+)", &m)
        address := "127.0.0.1:" m[1]
}

; ===========================
; START SERVER (hidden)
; ===========================
Run('"' serverDir '\winfusion.exe"', serverDir, "Hide")

; ===========================
; RUN GAME
; ===========================
ffCmd := Format(
    'ffrunner.exe --force-vulkan -m "{}" -a "{}" --asseturl "{}" -l "{}"',
    mainFile,
    address,
    assetUrl,
    logFile
)
RunWait(ffCmd, launcherDir)

; ===========================
; CLEANUP (force close server)
; ===========================
RunWait('taskkill /IM winfusion.exe /F >nul 2>&1', , "Hide")

ExitApp
