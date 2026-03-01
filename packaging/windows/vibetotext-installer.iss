; VibeToText Windows Installer - Inno Setup Script
; Requires Inno Setup 6.x: https://jrsoftware.org/isinfo.php
;
; Build with:
;   iscc packaging\windows\vibetotext-installer.iss
;
; Expects PyInstaller output in dist\ folder:
;   dist\vibetotext-engine.exe
;   dist\vibetotext-ui.exe

#define MyAppName "VibeToText"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "VibeToText"
#define MyAppURL "https://github.com/dyoburon/vibetotext"
#define MyAppExeName "vibetotext-engine.exe"

[Setup]
; App identity
AppId={{8E4F5C2A-3B7D-4A1E-9F6C-2D8E1A5B3C7F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Install location
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; Output (two levels up to project root dist/)
OutputDir=..\..\dist
OutputBaseFilename=VibeToText-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes

; Appearance
WizardStyle=modern

; Privileges - install per-user by default (no admin needed)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Uninstall
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; Misc
AllowNoIcons=yes
LicenseFile=..\..\LICENSE
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupentry"; Description: "Start VibeToText when Windows starts"; GroupDescription: "Windows Startup:"; Flags: unchecked

[Files]
; Main engine executable
Source: "..\..\dist\vibetotext-engine.exe"; DestDir: "{app}"; Flags: ignoreversion

; Waveform overlay UI executable
Source: "..\..\dist\vibetotext-ui.exe"; DestDir: "{app}"; Flags: ignoreversion

; License
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Start Menu
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

; Desktop (optional)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Auto-start on login (optional task)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: startupentry

[Run]
; Option to launch after install
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// Create .vibetotext config directory in user profile on install
procedure CurStepChanged(CurStep: TSetupStep);
var
  ConfigDir: String;
begin
  if CurStep = ssPostInstall then
  begin
    ConfigDir := ExpandConstant('{userprofile}\.vibetotext');
    if not DirExists(ConfigDir) then
      CreateDir(ConfigDir);
  end;
end;
