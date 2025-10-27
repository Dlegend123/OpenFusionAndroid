#SingleInstance Force
SetWorkingDir A_ScriptDir

; read config.ini next to this script
configFile := A_ScriptDir "\config.ini"
if !FileExist(configFile) {
    MsgBox "config.ini not found."
    ExitApp
}

; --- parse config ---
config := Map(), section := ""
for line in StrSplit(FileRead(configFile), "`n", "`r") {
    line := Trim(line)
    if (line = "" || SubStr(line,1,1)="#")
        continue
    if RegExMatch(line, "^\[(.+)\]$", &m) {
        section := m[1], config[section] := Map()
        continue
    }
    if (section != "" && InStr(line,"=")) {
        p := StrSplit(line,"=",,2)
        config[section][Trim(p[1])] := Trim(p[2])
    }
}

; --- values ---
launcher := config["launcher"]
SERVER_DIR   := A_ScriptDir "\" launcher["server_dir"]
LAUNCHER_DIR := A_ScriptDir "\" launcher["launcher_dir"]
CACHE_DIR    := A_ScriptDir "\" launcher["cache_dir"]
VERSION_UUID := launcher["version_uuid"]
LOGIN_PORT   := config["login"]["port"]

USERNAME := launcher.Has("username") ? launcher["username"] : ""
TOKEN    := launcher.Has("token")    ? launcher["token"]    : ""
WIDTH    := launcher.Has("width")    ? launcher["width"]    : ""
HEIGHT   := launcher.Has("height")   ? launcher["height"]   : ""
LOG_FILE := launcher.Has("log_file") ? launcher["log_file"] : ""

; --- start server if not already running ---
if !ProcessExist("winfusion.exe") {
    Run('"' SERVER_DIR '\winfusion.exe"', SERVER_DIR, "Normal")

}

; --- build and detach launcher command ---
VERSION_PATH := CACHE_DIR "\" VERSION_UUID
MAIN_FILE := VERSION_PATH "\main.unity3d"
ASSET_URL := "file:///" StrReplace(VERSION_PATH,"\","/") "/"
ADDRESS := "127.0.0.1:" LOGIN_PORT

cmd := 'ffrunner.exe --force-vulkan '
    . '-m "' MAIN_FILE '" '
    . '-a "' ADDRESS '" '
    . '--asseturl "' ASSET_URL '" '
if (USERNAME && TOKEN)
    cmd .= '--username "' USERNAME '" --token "' TOKEN '" '
if (WIDTH && HEIGHT)
    cmd .= '--width ' WIDTH ' --height ' HEIGHT ' '
if (LOG_FILE)
    cmd .= '-l "' LOG_FILE '" '

Run(cmd, LAUNCHER_DIR)
ExitApp
