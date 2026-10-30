; KilosGrammar beta Windows EXE installer. Built ONLY from a validated offline
; release folder. This installs files, NOT PostgreSQL/Python services silently.
; A teacher must run the bundled installers and Setup Offline.cmd afterwards.
#define AppVersion "0.3.0-beta.1"
#ifdef QAInstall
  #define AppIdText "{{F4CE5467-8A7C-4656-9D4D-85B191767CAC}"
  #define OutputName "KilosGrammar-v0.3.0-beta.1-OFFLINE-INSTALLER-QA-NOT-FOR-RELEASE"
#else
  #define AppIdText "{{8EFAEB6F-439A-451C-8261-BBF40A3B9DC0}"
  #define OutputName "KilosGrammar-v0.3.0-beta.1-OFFLINE-CANDIDATE-NOT-CLEAN-PC-TESTED-Setup"
#endif

[Setup]
AppId={#AppIdText}
AppName=KilosGrammar
AppVersion={#AppVersion}
AppVerName=KilosGrammar {#AppVersion} (Offline Candidate)
AppPublisher=Kyu's Studio
AppPublisherURL=https://github.com/Yuezhiui/KilosGrammar
AppSupportURL=https://github.com/Yuezhiui/KilosGrammar
DefaultDirName={localappdata}\Programs\KilosGrammar
DefaultGroupName=KilosGrammar
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
MinVersion=10.0.19041
OutputDir=out
OutputBaseFilename={#OutputName}
SetupIconFile=branding\KILOSGRAMMAR.ico
UninstallDisplayIcon={app}\KilosGrammar.exe
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
SetupLogging=yes
AllowNoIcons=yes
UsePreviousAppDir=no
CloseApplications=no

[Files]
Source: "out\KilosGrammar-win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\KilosGrammar"; Filename: "{app}\Play KilosGrammar.cmd"; WorkingDir: "{app}"
Name: "{group}\KilosGrammar Offline Setup"; Filename: "{app}\Setup Offline.cmd"; WorkingDir: "{app}"

[Run]
Filename: "{sys}\notepad.exe"; Parameters: """{app}\RELEASE-INSTRUCTIONS.md"""; Description: "Read the required offline setup instructions"; Flags: postinstall skipifsilent
