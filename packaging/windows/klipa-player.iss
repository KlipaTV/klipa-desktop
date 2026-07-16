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

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Klipa Player"; Filename: "{app}\klipa_player.exe"
Name: "{autodesktop}\Klipa Player"; Filename: "{app}\klipa_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\klipa_player.exe"; Description: "Launch Klipa Player"; Flags: nowait postinstall skipifsilent
