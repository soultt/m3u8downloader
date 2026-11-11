; NSIS Installer Script for M3U8 Downloader
!include "MUI2.nsh"
!include "LogicLib.nsh"

; =====================
; General Settings
; =====================
Name "M3U8 Downloader"
OutFile "F:\App\M3u8Download\build\windows\x64\dist\M3U8Downloader_Setup.exe"
InstallDir "$PROGRAMFILES64\M3U8Downloader"
RequestExecutionLevel admin

CRCCheck on
AutoCloseWindow false
ShowInstDetails show
Caption "M3U8 Downloader Installation"

; =====================
; UI Customization
; =====================
!define MUI_ABORTWARNING
!define MUI_WELCOMEFINISH_TITLE "欢迎使用 M3U8 Downloader"
!define MUI_FINISHPAGE_RUN "$INSTDIR\m3u8_down.exe"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "启动 M3U8 Downloader"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION LaunchApp

; =====================
; Pages
; =====================
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

; =====================
; Sections
; =====================
Section "Main Application" SecMain
    SetOutPath "$INSTDIR"
    
    ; Main executable
    File "F:\App\M3u8Download\build\windows\x64\dist\m3u8_down.exe"
    
    ; Flutter runtime files
    File "F:\App\M3u8Download\build\windows\x64\dist\flutter_windows.dll"
    File "F:\App\M3u8Download\build\windows\x64\dist\icudtl.dat"
    
    ; All DLL files from dist (recursive)
    File /r "F:\App\M3u8Download\build\windows\x64\dist\*.dll"
    
    ; Data directory (Flutter assets) - copy without recursion for better control
    SetOutPath "$INSTDIR\data"
    CopyFiles /SILENT "F:\App\M3u8Download\build\windows\x64\dist\data\*.*" "$INSTDIR\data\"
    CopyFiles /SILENT "F:\App\M3u8Download\build\windows\x64\dist\data\flutter_assets\*" "$INSTDIR\data\flutter_assets\"
    CopyFiles /SILENT "F:\App\M3u8Download\build\windows\x64\dist\data\flutter_assets\assets\*" "$INSTDIR\data\flutter_assets\assets\"
    CopyFiles /SILENT "F:\App\M3u8Download\build\windows\x64\dist\data\flutter_assets\fonts\*" "$INSTDIR\data\flutter_assets\fonts\"
    CopyFiles /SILENT "F:\App\M3u8Download\build\windows\x64\dist\data\flutter_assets\packages\*" "$INSTDIR\data\flutter_assets\packages\"
    CopyFiles /SILENT "F:\App\M3u8Download\build\windows\x64\dist\data\flutter_assets\shaders\*" "$INSTDIR\data\flutter_assets\shaders\"
    
    ; Create Start Menu Shortcut
    CreateShortCut "$DESKTOP\m3u8_down.lnk" "$INSTDIR\m3u8_down.exe"
    CreateShortCut "$SMPROGRAMS\M3U8 Downloader\m3u8_down.lnk" "$INSTDIR\m3u8_down.exe"
    
    ; Write Uninstaller
    WriteUninstaller "$INSTDIR\uninst.exe"
    
    ; Register in Add/Remove Programs
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\M3U8Downloader" "DisplayName" "M3U8 Downloader"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\M3U8Downloader" "UninstallString" "$INSTDIR\uninst.exe"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\M3U8Downloader" "DisplayIcon" "$INSTDIR\m3u8_down.exe"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\M3U8Downloader" "Publisher" "soultt"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\M3U8Downloader" "DisplayVersion" "1.0.0"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\M3U8Downloader" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\M3U8Downloader" "HelpLink" "https://github.com/soultt/m3u8downloader"
SectionEnd

; =====================
; Uninstall Section
; =====================
Section "Uninstall"
    Delete "$INSTDIR\uninst.exe"
    RMDir /r "$INSTDIR\data"
    RMDir "$INSTDIR"
    
    Delete "$DESKTOP\m3u8_down.lnk"
    RMDir /r "$SMPROGRAMS\M3U8 Downloader"
    
    DeleteRegKey HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\M3U8Downloader"
SectionEnd

; =====================
; Functions
; =====================
Function LaunchApp
    ExecShell "open" "$INSTDIR\m3u8_down.exe"
FunctionEnd
