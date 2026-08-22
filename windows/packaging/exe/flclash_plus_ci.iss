#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef SetupIconFile
  #error SetupIconFile is required
#endif
#ifndef ChineseMessagesFile
  #error ChineseMessagesFile is required
#endif

[Setup]
AppId={{2DD55137-C734-446E-B1DC-3FCB5445025D}
AppVersion={#AppVersion}
AppName=FlClash Plus
AppPublisher=AI68
AppPublisherURL=https://mingjie-panel.ai68ai.cn
AppSupportURL=https://mingjie-panel.ai68ai.cn
AppUpdatesURL=https://mingjie-panel.ai68ai.cn
DefaultDirName={autopf64}\FlClash Plus
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=FlClashPlus-{#AppVersion}-Setup
Compression=lzma
SolidCompression=yes
SetupIconFile={#SetupIconFile}
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Code]
procedure KillProcesses;
var
  Processes: TArrayOfString;
  i: Integer;
  ResultCode: Integer;
begin
  Processes := ['FlClashPlus.exe', 'FlClashPlusHelperService.exe'];

  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec('taskkill', '/f /im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

procedure UnregisterHelperService;
var
  HelperPath: String;
  ResultCode: Integer;
begin
  HelperPath := ExpandConstant('{app}\FlClashPlusHelperService.exe');
  if FileExists(HelperPath) then
  begin
    Exec(HelperPath, 'uninstall', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  UnregisterHelperService;
  KillProcesses;
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  UnregisterHelperService;
  KillProcesses;
  Result := True;
end;

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chineseSimplified"; MessagesFile: "{#ChineseMessagesFile}"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FlClash Plus"; Filename: "{app}\FlClashPlus.exe"
Name: "{autodesktop}\FlClash Plus"; Filename: "{app}\FlClashPlus.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\FlClashPlus.exe"; Description: "{cm:LaunchProgram,FlClash Plus}"; Flags: runascurrentuser nowait postinstall skipifsilent
