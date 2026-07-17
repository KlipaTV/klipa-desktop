#ifndef BundleDir
  #error BundleDir must point to the release bundle
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{27ECA15D-0CA8-4EAF-A03D-5BA3B5C2CE11}
AppName=Klipa Player
AppVersion={#AppVersion}
AppPublisher=Klipa Project
DefaultDirName={localappdata}\Programs\Klipa Player
DefaultGroupName=Klipa Player
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=KlipaPlayer-Setup-x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\klipa_player.exe
CloseApplications=yes
RestartApplications=no
ChangesEnvironment=no
; Signing is only defined for the local thumbprint-based packaging path.
; The CI/SignPath release flow signs the finished installer after compilation,
; so its generated uninstaller (unins000.exe) remains unsigned.
#ifdef Signing
SignTool=klipa
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[InstallDelete]
; Remove files from previous versions so upgrades cannot load stale plugins
; or Flutter assets. User data lives outside {app} and is unaffected.
Type: files; Name: "{app}\*.dll"
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\NOTICE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Klipa Player"; Filename: "{app}\klipa_player.exe"
Name: "{autodesktop}\Klipa Player"; Filename: "{app}\klipa_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\klipa_player.exe"; Description: "Launch Klipa Player"; Flags: nowait postinstall skipifsilent
