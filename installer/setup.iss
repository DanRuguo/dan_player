; Dan Player's offline installer. Inno handles embedded extraction and ordinary
; installation; dan_installer_native supplies explicit manifest-bounded recovery.
#ifndef BuildConfig
  #error Build with scripts/build_windows_installer.ps1; no implicit payload path.
#endif
#include BuildConfig
#define ProductionDialogFontSize 11

[Setup]
#ifdef QaBuild
AppId=DanRuguo.DanPlayer.InstallerQA
SetupMutex=DanRuguo.DanPlayer.InstallerQA
#else
AppId=DanRuguo.DanPlayer
SetupMutex=DanRuguo.DanPlayer.Installer
#endif
AppName=Dan Player
AppVersion={#AppVersion}
AppVerName=Dan Player {#DisplayVersion}
AppPublisher=DanRuguo
AppPublisherURL=https://github.com/DanRuguo/dan_player
AppSupportURL=https://github.com/DanRuguo/dan_player/issues
VersionInfoProductName=Dan Player Installer
VersionInfoVersion={#NumericVersion}
VersionInfoProductTextVersion={#AppVersion}
SetupArchitecture=x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\danplayer_{#AppVersion}
UsePreviousAppDir=no
UsePreviousTasks=no
DisableWelcomePage=yes
DisableDirPage=no
DisableProgramGroupPage=yes
DisableReadyPage=yes
CloseApplications=no
RestartApplications=no
AllowRootDirectory=no
AllowUNCPath=no
AllowNetworkDrive=no
DirExistsWarning=no
AppendDefaultDirName=no
UninstallFilesDir={app}\.dan-player-install
UninstallDisplayIcon={app}\Dan Player.exe
SetupIconFile={#RepositoryRoot}\app_icon.ico
#ifdef QaThemeLight
WizardStyle=modern light windows11 hidebevels
#else
#ifdef QaThemeDark
WizardStyle=modern dark windows11 hidebevels
#else
WizardStyle=modern dynamic windows11 hidebevels
#endif
#endif
#ifdef QaThemeDark
WizardBackColor=#202020
#else
WizardBackColor=#f3f3f3
#endif
WizardBackColorDynamicDark=#202020
; Let Inno size its own notebook/footer together. No manual upward footer move.
WizardSizePercent=110,100
WizardImageFile=
WizardSmallImageFile=
WizardImageBackColor=none
WizardSmallImageBackColor=none
OutputDir={#OutputDirectory}
OutputBaseFilename={#OutputFilename}
Compression=lzma2
SolidCompression=yes
SetupLogging=yes
DisableFinishedPage=no
#ifdef QaBuild
; Exercise real uninstall metadata in the sandbox, without ARP registration.
Uninstallable=yes
CreateUninstallRegKey=no
#endif

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[LangOptions]
#ifdef QaDialogFontSize
DialogFontSize={#QaDialogFontSize}
#else
; 11 pt keeps the embedded CJK face at least as readable as Windows' standard
; confirmation text. Inno applies this baseline to wizard copy and dialogs and
; scales its native layout before the private family is selected below.
DialogFontSize={#ProductionDialogFontSize}
#endif

[Messages]
SelectDirLabel3=请选择安装位置。检测到旧版时将在原位置升级，并保留用户数据。
SelectDirBrowseLabel=可直接编辑下面的最终路径。手动编辑后，安装器不会再自动改变它。
ButtonNext=安装(&I)
FinishedHeadingLabel=安装完成
FinishedLabel=Dan Player 已安装。您可以打开播放器，或明确选择删除本安装器。关闭窗口不会删除安装器。

[Files]
Source: "{#NativeLibrary}"; DestName: "dan_installer_native.dll"; Flags: dontcopy
Source: "{#ManifestFile}"; DestName: "payload.manifest"; Flags: dontcopy
Source: "{#ManifestFile}"; DestDir: "{app}\.dan-player-install"; DestName: "payload.manifest"; Flags: ignoreversion
Source: "{#RepositoryRoot}\assets\images\RCE_logo_transparent.png"; Flags: dontcopy
Source: "{#RepositoryRoot}\assets\images\RCE_logo_white.png"; Flags: dontcopy
Source: "{#RepositoryRoot}\assets\branding\danruguo_light.png"; Flags: dontcopy
Source: "{#RepositoryRoot}\assets\branding\danruguo_dark.png"; Flags: dontcopy
Source: "{#RepositoryRoot}\assets\fonts\PingFangSC-Regular.ttf"; Flags: dontcopy
#include PayloadFileEntries

[Icons]
Name: "{code:DesktopDirectory}\Dan Player"; Filename: "{app}\Dan Player.exe"; WorkingDir: "{app}"; Check: WantDesktop; AfterInstall: ShortcutInstalled(True)
Name: "{code:StartDirectory}\Dan Player"; Filename: "{app}\Dan Player.exe"; WorkingDir: "{app}"; Check: WantStartMenu; AfterInstall: ShortcutInstalled(False)

[Code]
type
  TInstallerRect = record
    Left, Top, Right, Bottom: LongInt;
  end;
  TInstallerPoint = record
    X, Y: LongInt;
  end;
var
  BrandPage: TWizardPage;
  UpdatePage: TWizardPage;
  UpdateNote: TNewStaticText;
  ParentButton, OpenButton, DeleteButton: TNewButton;
  DesktopCheck, StartCheck: TNewCheckBox;
  DataNote: TNewStaticText;
  FinishedSignature: TBitmapImage;
  BrandRcePath, BrandDanPath: String;
  AutomaticEdit, BrandFinished, BrandStarted, TransactionStarted, InstallSucceeded: Boolean;
  InstallationReady, LaunchAfterSuccess, DeleteAfterSuccess: Boolean;
  InstallFailure: String;
  CopiedFiles: Integer;
  UpdateMode, UpdateReady, UpdateTimedOut: Boolean;
  UpdateFailure: String;
  UpdateTimer: WPARAM;
  UpdatePollCount: Integer;
#ifdef QaBuild
  QaCancelRequested: Boolean;
  QaRenderPhase: Integer;
#endif

function DP_GetError(Buffer: String; Capacity: Integer): Integer;
  external 'DP_GetError@files:dan_installer_native.dll stdcall';
function DP_UpdateOpen(Target, Manifest, Version, ParentPID, ReadyEvent: String): Integer;
  external 'DP_UpdateOpen@files:dan_installer_native.dll stdcall';
function DP_UpdatePoll(): Integer;
  external 'DP_UpdatePoll@files:dan_installer_native.dll stdcall';
function DP_UpdateRetry(): Integer;
  external 'DP_UpdateRetry@files:dan_installer_native.dll stdcall';
procedure DP_UpdateClose();
  external 'DP_UpdateClose@files:dan_installer_native.dll stdcall';
function DP_SelectionCreate(Version: String): Integer;
  external 'DP_SelectionCreate@files:dan_installer_native.dll stdcall';
function DP_SelectionParent(Parent: String): Integer;
  external 'DP_SelectionParent@files:dan_installer_native.dll stdcall';
function DP_SelectionEdit(Path: String): Integer;
  external 'DP_SelectionEdit@files:dan_installer_native.dll stdcall';
function DP_SelectionPrevious(Path: String): Integer;
  external 'DP_SelectionPrevious@files:dan_installer_native.dll stdcall';
function DP_SelectionGet(Buffer: String; Capacity: Integer): Integer;
  external 'DP_SelectionGet@files:dan_installer_native.dll stdcall';
function DP_Configure(Target, Manifest, Desktop, StartMenu, SetupSource: String): Integer;
  external 'DP_Configure@files:dan_installer_native.dll stdcall';
function DP_HasRecovery(): Integer;
  external 'DP_HasRecovery@files:dan_installer_native.dll stdcall';
function DP_Begin(): Integer;
  external 'DP_Begin@files:dan_installer_native.dll stdcall';
function DP_Commit(): Integer;
  external 'DP_Commit@files:dan_installer_native.dll stdcall';
function DP_VerifyInstalled(): Integer;
  external 'DP_VerifyInstalled@files:dan_installer_native.dll stdcall';
function DP_RecordWritten(Path: String): Integer;
  external 'DP_RecordWritten@files:dan_installer_native.dll stdcall';
function DP_Rollback(): Integer;
  external 'DP_Rollback@files:dan_installer_native.dll stdcall';
function DP_BackupPath(Buffer: String; Capacity: Integer): Integer;
  external 'DP_BackupPath@files:dan_installer_native.dll stdcall';
function DP_DeleteOriginalInstaller(): Integer;
  external 'DP_DeleteOriginalInstaller@files:dan_installer_native.dll stdcall';
function DP_LoadPrivateFont(Path, Buffer: String; Capacity: Integer): Integer;
  external 'DP_LoadPrivateFont@files:dan_installer_native.dll stdcall';
function DP_ShowBrand(Parent: HWND; Width, Height: Integer; Background: LongWord;
  RcePath, DanPath: String; Callback: NativeInt): Integer;
  external 'DP_ShowBrand@files:dan_installer_native.dll stdcall';
procedure DP_CloseBrand();
  external 'DP_CloseBrand@files:dan_installer_native.dll stdcall';
function DP_AccentColor(): LongWord;
  external 'DP_AccentColor@files:dan_installer_native.dll stdcall';
function DP_StyleButton(Window: HWND; Surface, Accent: LongWord; Primary: Boolean; Radius: Integer): Integer;
  external 'DP_StyleButton@files:dan_installer_native.dll stdcall';
procedure DP_CloseControls();
  external 'DP_CloseControls@files:dan_installer_native.dll stdcall';
function PostMessage(Window: HWND; Message: UINT; WParam: WPARAM; LParam: LPARAM): Boolean;
  external 'PostMessageW@user32.dll stdcall';
function InstallerGetWindowRect(Window: HWND; var Bounds: TInstallerRect): Boolean;
  external 'GetWindowRect@user32.dll stdcall';
function InstallerScreenToClient(Window: HWND; var Position: TInstallerPoint): Boolean;
  external 'ScreenToClient@user32.dll stdcall';
function InstallerSetTimer(Window: HWND; ID: WPARAM; Interval: UINT; Callback: NativeInt): WPARAM;
  external 'SetTimer@user32.dll stdcall';
function InstallerKillTimer(Window: HWND; ID: WPARAM): Boolean;
  external 'KillTimer@user32.dll stdcall';
#ifdef QaBuild
function DP_QA_ScheduleFrame(Window: HWND; Delay: Integer; Callback: NativeInt): Integer;
  external 'DP_QA_ScheduleFrame@files:dan_installer_native.dll stdcall';
procedure DP_QA_CancelFrame();
  external 'DP_QA_CancelFrame@files:dan_installer_native.dll stdcall';
function DP_QA_Capture(Window: HWND; Path: String): Integer;
  external 'DP_QA_Capture@files:dan_installer_native.dll stdcall';
function DP_QA_ControlCorners(Window: HWND): Integer;
  external 'DP_QA_ControlCorners@files:dan_installer_native.dll stdcall';
function DP_QA_ButtonFont(Window, Reference: HWND): Integer;
  external 'DP_QA_ButtonFont@files:dan_installer_native.dll stdcall';
function DP_QA_DirectoryGeometry(Edit, Browse, Desktop, StartMenu, Note, Next, Back, Cancel, DiskSpace: HWND): Integer;
  external 'DP_QA_DirectoryGeometry@files:dan_installer_native.dll stdcall';
function DP_QA_FooterGeometry(Content, Next, Back, Cancel: HWND; Name: String): Integer;
  external 'DP_QA_FooterGeometry@files:dan_installer_native.dll stdcall';
function DP_QA_FinishedGeometry(LabelWindow, Open, Delete, Finish: HWND; WidthLimit: Integer): Integer;
  external 'DP_QA_FinishedGeometry@files:dan_installer_native.dll stdcall';
function DP_QA_Graphic(Parent: HWND; Left, Top, Width, Height: Integer; Name: String): Integer;
  external 'DP_QA_Graphic@files:dan_installer_native.dll stdcall';
#endif

function NativeError(): String;
var Count: Integer;
begin
  Result := StringOfChar(#0, 2048);
  Count := DP_GetError(Result, 2048);
  SetLength(Result, Count);
end;

function BackupPath(): String;
var Count: Integer;
begin
  Result := StringOfChar(#0, 2048);
  Count := DP_BackupPath(Result, 2048);
  SetLength(Result, Count);
end;

function WantDesktop(): Boolean;
begin
  Result := not UpdateMode and (InstallFailure = '') and Assigned(DesktopCheck) and DesktopCheck.Checked;
end;

function WantStartMenu(): Boolean;
begin
  Result := not UpdateMode and (InstallFailure = '') and Assigned(StartCheck) and StartCheck.Checked;
end;

function DesktopLink(Param: String): String;
begin
#ifdef QaBuild
  Result := AddBackslash(ExtractFileDir(WizardDirValue)) + 'redirect-desktop\Dan Player.lnk';
#else
  Result := ExpandConstant('{userdesktop}\Dan Player.lnk');
#endif
end;

function StartLink(Param: String): String;
begin
#ifdef QaBuild
  Result := AddBackslash(ExtractFileDir(WizardDirValue)) + 'redirect-start\Dan Player.lnk';
#else
  Result := ExpandConstant('{userprograms}\Dan Player.lnk');
#endif
end;

function DesktopDirectory(Param: String): String;
begin
  Result := ExtractFileDir(DesktopLink(''));
end;

function StartDirectory(Param: String): String;
begin
  Result := ExtractFileDir(StartLink(''));
end;

procedure RefreshSelection();
var Value: String; Count: Integer;
begin
  Value := StringOfChar(#0, 2048);
  Count := DP_SelectionGet(Value, 2048);
  SetLength(Value, Count);
  AutomaticEdit := True;
  WizardForm.DirEdit.Text := Value;
  AutomaticEdit := False;
end;

procedure FinalPathChanged(Sender: TObject);
begin
  if not AutomaticEdit then DP_SelectionEdit(WizardForm.DirEdit.Text);
end;

procedure ChooseParent(Sender: TObject);
var Parent: String;
begin
  Parent := ExtractFileDir(WizardDirValue);
  if BrowseForFolder('选择父目录（最终路径手动编辑后不会自动变化）', Parent, False) then begin
    if DP_SelectionParent(Parent) = 0 then
      MsgBox(NativeError(), mbError, MB_OK)
    else RefreshSelection();
  end;
end;

procedure BrandComplete();
begin
  BrandFinished := True;
  if WizardForm.CurPageID = BrandPage.ID then begin
    WizardForm.NextButton.Enabled := True;
    PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0);
  end;
end;

procedure OpenPlayer(Sender: TObject);
begin
  if not InstallationReady then Exit;
  LaunchAfterSuccess := True;
  PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0);
end;

procedure DeleteThisInstaller(Sender: TObject);
begin
  if not InstallationReady then Exit;
  DeleteAfterSuccess := True;
  PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0);
end;

procedure StopUpdateTimer();
begin
  if UpdateTimer <> 0 then InstallerKillTimer(WizardForm.Handle, UpdateTimer);
  UpdateTimer := 0;
end;

procedure UpdateWaitTick(Window: HWND; Message: UINT; ID: WPARAM; Time: DWORD);
var State: Integer;
begin
  if (UpdateTimer = 0) or (WizardForm.CurPageID <> UpdatePage.ID) then Exit;
  UpdatePollCount := UpdatePollCount + 1;
#ifdef QaBuild
  if (ExpandConstant('{param:QAUPDATEACTION|}') = 'cancel') and (UpdatePollCount >= 1) then begin
    StopUpdateTimer(); QaCancelRequested := True;
    Log('QA update cancellation while parent remains alive');
    PostMessage(WizardForm.Handle, $0010, 0, 0); Exit;
  end;
#endif
  if UpdateFailure <> '' then begin
    StopUpdateTimer();
#ifdef QaBuild
    if ExpandConstant('{param:QAUPDATEACTION|}') <> '' then begin
      QaCancelRequested := True; PostMessage(WizardForm.Handle, $0010, 0, 0);
    end;
#endif
    Exit;
  end;
  State := DP_UpdatePoll();
  if State = 0 then Exit;
  StopUpdateTimer();
  if State = 1 then begin
    UpdateReady := True;
    UpdateNote.Caption := '播放器已退出。正在验证文件并开始原位更新。';
    WizardForm.NextButton.Enabled := True;
    Log('Verified update parent exited; advancing without directory or shortcut changes');
    PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0);
  end else if State = 2 then begin
    UpdateTimedOut := True;
    UpdateNote.Caption := '播放器尚未退出，尚未修改任何程序文件。' + #13#10 +
      '请正常关闭播放器后点击“重试”，或点击“取消”稍后更新。安装器不会强制结束进程。';
    WizardForm.NextButton.Caption := '重试';
    WizardForm.NextButton.Enabled := True;
    Log('Update parent wait timed out; no installation transaction started');
#ifdef QaBuild
    if ExpandConstant('{param:QAUPDATEACTION|}') = 'timeout' then begin
      QaCancelRequested := True; PostMessage(WizardForm.Handle, $0010, 0, 0);
    end;
    if ExpandConstant('{param:QAUPDATEACTION|}') = 'retry' then
      PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0);
#endif
  end else begin
    UpdateFailure := '无法继续验证播放器进程。请取消后重新从播放器发起更新。' + #13#10 + NativeError();
    UpdateNote.Caption := UpdateFailure;
#ifdef QaBuild
    if ExpandConstant('{param:QAUPDATEACTION|}') <> '' then begin
      QaCancelRequested := True; PostMessage(WizardForm.Handle, $0010, 0, 0);
    end;
#endif
  end;
end;

procedure StartUpdateTimer();
begin
  StopUpdateTimer();
  UpdateTimer := InstallerSetTimer(WizardForm.Handle, $DA77, 250, CreateCallback(@UpdateWaitTick));
  if UpdateTimer = 0 then begin
    UpdateFailure := '无法启动更新等待。尚未修改程序文件，请取消后重试。';
    UpdateNote.Caption := UpdateFailure;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if UpdateMode and (CurPageID = UpdatePage.ID) then begin
    Result := UpdateReady and (UpdateFailure = '');
    if UpdateTimedOut and (UpdateFailure = '') then begin
      UpdateTimedOut := False;
      if DP_UpdateRetry() = 0 then begin UpdateFailure := NativeError(); UpdateNote.Caption := UpdateFailure; Exit; end;
      UpdateNote.Caption := '等待播放器正常退出。可以随时取消，安装器不会强制结束进程。';
      WizardForm.NextButton.Enabled := False;
      StartUpdateTimer();
    end;
  end;
end;

procedure LayoutFinishedActions();
var ActionTop, ActionHeight, ActionWidth, ActionLeft: Integer;
begin
  { FinishedPage includes Inno's left illustration. Its label, not page x=0,
    defines the usable content column. Re-evaluate after Inno wraps the label. }
  ActionHeight := WizardForm.NextButton.Height;
  ActionTop := WizardForm.FinishedLabel.Top + WizardForm.FinishedLabel.Height + ScaleY(16);
  ActionWidth := ScaleX(240);
  if ActionWidth > WizardForm.FinishedLabel.Width then ActionWidth := WizardForm.FinishedLabel.Width;
  ActionLeft := WizardForm.FinishedLabel.Left + (WizardForm.FinishedLabel.Width - ActionWidth) div 2;
  OpenButton.SetBounds(ActionLeft, ActionTop, ActionWidth, ActionHeight);
  DeleteButton.SetBounds(ActionLeft, ActionTop + ActionHeight + ScaleY(8), ActionWidth, ActionHeight);
end;

procedure CenterFinishedFooter();
var Bounds: TInstallerRect; Center: TInstallerPoint; NewLeft, MaximumLeft: Integer;
begin
  { FinishedLabel and NextButton have different parents. Convert the content
    column's screen center into the existing footer parent; only move Left.
    Native Top/Height/Width, anchors, click handling and other pages stay intact. }
  if not InstallerGetWindowRect(WizardForm.FinishedLabel.Handle, Bounds) then Exit;
  Center.X := (Bounds.Left + Bounds.Right) div 2;
  Center.Y := Bounds.Top;
  if not InstallerScreenToClient(WizardForm.NextButton.Parent.Handle, Center) then Exit;
  NewLeft := Center.X - WizardForm.NextButton.Width div 2;
  MaximumLeft := WizardForm.NextButton.Parent.ClientWidth - WizardForm.NextButton.Width;
  if MaximumLeft < 0 then Exit;
  if NewLeft < 0 then NewLeft := 0;
  if NewLeft > MaximumLeft then NewLeft := MaximumLeft;
  WizardForm.NextButton.Left := NewLeft;
end;

procedure FitBrandImage(Image: TBitmapImage; Left, Top, Width: Integer);
var Height: Integer;
begin
  Height := Width * Image.PngImage.Height div Image.PngImage.Width;
  Image.SetBounds(Left, Top, Width, Height);
  Image.Stretch := True;
  Image.BackColor := clNone;
end;

procedure LayoutFinishedBranding();
var ColumnWidth, GroupHeight, GroupTop: Integer;
begin
  ColumnWidth := WizardForm.FinishedLabel.Left - ScaleX(12);
  FitBrandImage(WizardForm.WizardBitmapImage2, ScaleX(16), 0, ColumnWidth - ScaleX(32));
  FitBrandImage(FinishedSignature, ScaleX(12), 0, ColumnWidth - ScaleX(24));
  GroupHeight := WizardForm.WizardBitmapImage2.Height + ScaleY(20) + FinishedSignature.Height;
  GroupTop := (WizardForm.FinishedPage.Height - GroupHeight) div 2;
  WizardForm.WizardBitmapImage2.Top := GroupTop;
  FinishedSignature.Top := GroupTop + WizardForm.WizardBitmapImage2.Height + ScaleY(20);
end;

#ifdef QaBuild
procedure QaAuditFooter(Name: String);
begin
  if DP_QA_FooterGeometry(WizardForm.OuterNotebook.Handle, WizardForm.NextButton.Handle,
      WizardForm.BackButton.Handle, WizardForm.CancelButton.Handle, Name) = 1 then
    Log('QA UI footer fully visible: ' + Name)
  else Log('QA UI FOOTER CLIPPED: ' + Name);
  if (DP_QA_ButtonFont(WizardForm.NextButton.Handle, WizardForm.DirEdit.Handle) <> 1) or
     (DP_QA_ButtonFont(WizardForm.BackButton.Handle, WizardForm.DirEdit.Handle) <> 1) or
     (DP_QA_ButtonFont(WizardForm.CancelButton.Handle, WizardForm.DirEdit.Handle) <> 1) then
    Log('QA UI BUTTON FONT FAILED: ' + Name);
end;

procedure QaAuditGraphic(Parent: HWND; Image: TBitmapImage; Name: String);
begin
  if DP_QA_Graphic(Parent, Image.Left, Image.Top, Image.Width, Image.Height, Name) = 1 then
    Log('QA UI brand bounds and transparent corners pass: ' + Name)
  else Log('QA UI BRAND FAILED: ' + Name);
end;

procedure QaRenderFrame();
var Name, Root: String; Corners: Boolean;
begin
  Root := ExpandConstant('{param:QARENDERROOT|}');
  if Root = '' then Exit;
  if QaRenderPhase = 0 then Name := 'rce'
  else if QaRenderPhase = 1 then Name := 'danruguo'
  else if QaRenderPhase = 2 then Name := 'directory'
  else Name := 'finished';
  if DP_QA_Capture(WizardForm.Handle, AddBackslash(Root) + Name + '.png') = 1 then
    Log('QA UI rendered nonblank real Inno tree: ' + Name)
  else Log('QA UI RENDER FAILED: ' + Name);
  QaAuditFooter(Name);
  if QaRenderPhase = 0 then begin
    QaRenderPhase := 1;
    DP_QA_ScheduleFrame(WizardForm.Handle, 780, CreateCallback(@QaRenderFrame));
  end else if QaRenderPhase = 2 then begin
    if (DP_QA_ButtonFont(ParentButton.Handle, WizardForm.DirEdit.Handle) <> 1) or
       (DP_QA_ButtonFont(OpenButton.Handle, WizardForm.DirEdit.Handle) <> 1) or
       (DP_QA_ButtonFont(DeleteButton.Handle, WizardForm.DirEdit.Handle) <> 1) then
      Log('QA UI BUTTON FONT FAILED: directory actions');
    Corners := DP_QA_ControlCorners(WizardForm.NextButton.Handle) = 1;
    if DP_QA_ControlCorners(WizardForm.BackButton.Handle) <> 1 then Corners := False;
    if DP_QA_ControlCorners(WizardForm.CancelButton.Handle) <> 1 then Corners := False;
    if DP_QA_ControlCorners(ParentButton.Handle) <> 1 then Corners := False;
    if DP_QA_ControlCorners(OpenButton.Handle) <> 1 then Corners := False;
    if DP_QA_ControlCorners(DeleteButton.Handle) <> 1 then Corners := False;
    Log(Format('QA UI geometry: client=%dx%d nextTop=%d nextHeight=%d cancelTop=%d', [
       WizardForm.ClientWidth, WizardForm.ClientHeight, WizardForm.NextButton.Top,
       WizardForm.NextButton.Height, WizardForm.CancelButton.Top]));
    if Corners then Log('QA UI all six button corners match actual VCL parent')
    else Log('QA UI CORNER MISMATCH');
    if DP_QA_DirectoryGeometry(WizardForm.DirEdit.Handle, ParentButton.Handle,
        DesktopCheck.Handle, StartCheck.Handle, DataNote.Handle,
        WizardForm.NextButton.Handle, WizardForm.BackButton.Handle,
        WizardForm.CancelButton.Handle, WizardForm.DiskSpaceLabel.Handle) = 1 then
      Log('QA UI real HWND centers, bounds and spacing pass')
    else Log('QA UI GEOMETRY FAILED');
    QaAuditGraphic(WizardForm.MainPanel.Handle, WizardForm.WizardSmallBitmapImage, 'header-rce');
    Log(Format('QA UI header bounds: imageLeft=%d titleRight=%d descriptionRight=%d', [
      WizardForm.WizardSmallBitmapImage.Left,
      WizardForm.PageNameLabel.Left + WizardForm.PageNameLabel.Width,
      WizardForm.PageDescriptionLabel.Left + WizardForm.PageDescriptionLabel.Width]));
    if (WizardForm.PageNameLabel.Left + WizardForm.PageNameLabel.Width >= WizardForm.WizardSmallBitmapImage.Left) or
       (WizardForm.PageDescriptionLabel.Left + WizardForm.PageDescriptionLabel.Width >= WizardForm.WizardSmallBitmapImage.Left) then
      Log('QA UI BRAND FAILED: header overlap');
    if ExpandConstant('{param:QARENDERINSTALL|0}') = '1' then
      PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0)
    else begin
      QaCancelRequested := True;
      PostMessage(WizardForm.Handle, $0010, 0, 0);
    end;
  end else if QaRenderPhase = 3 then begin
    if (DP_QA_ButtonFont(OpenButton.Handle, WizardForm.DirEdit.Handle) <> 1) or
       (DP_QA_ButtonFont(DeleteButton.Handle, WizardForm.DirEdit.Handle) <> 1) then
      Log('QA UI BUTTON FONT FAILED: finished actions');
    if (DP_QA_ControlCorners(OpenButton.Handle) <> 1) or
       (DP_QA_ControlCorners(DeleteButton.Handle) <> 1) or
       (DP_QA_ControlCorners(WizardForm.NextButton.Handle) <> 1) then
      Log('QA UI CORNER MISMATCH: finished');
    if DP_QA_FinishedGeometry(WizardForm.FinishedLabel.Handle, OpenButton.Handle,
        DeleteButton.Handle, WizardForm.NextButton.Handle, ScaleX(240)) = 1 then Log('QA UI finished actions and native Finish share content center without overlap')
    else Log('QA UI FINISHED ACTIONS MISPLACED');
    QaAuditGraphic(WizardForm.FinishedPage.Handle, WizardForm.WizardBitmapImage2, 'finished-rce');
    QaAuditGraphic(WizardForm.FinishedPage.Handle, FinishedSignature, 'finished-signature');
    if (WizardForm.WizardBitmapImage2.Left + WizardForm.WizardBitmapImage2.Width >= WizardForm.FinishedLabel.Left) or
       (FinishedSignature.Left + FinishedSignature.Width >= WizardForm.FinishedLabel.Left) or
       (WizardForm.WizardBitmapImage2.Top + WizardForm.WizardBitmapImage2.Height >= FinishedSignature.Top) then
      Log('QA UI BRAND FAILED: finished column overlap');
    { Exercise ordinary Finish only. Never press Open/Delete in a render run. }
    PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0);
  end;
end;
#endif

procedure InitializeWizard();
var Previous, FontName, Forced, UpdateFlag: String; Count: Integer;
begin
  ExtractTemporaryFile('payload.manifest');
  ExtractTemporaryFile('PingFangSC-Regular.ttf');
  FontName := StringOfChar(#0, 128);
  Count := DP_LoadPrivateFont(ExpandConstant('{tmp}\PingFangSC-Regular.ttf'), FontName, 128);
  if Count > 0 then begin
    SetLength(FontName, Count);
    WizardForm.Font.Name := FontName;
  end;
  if IsDarkInstallMode then begin
    BrandRcePath := 'RCE_logo_white.png'; BrandDanPath := 'danruguo_dark.png';
  end else begin
    BrandRcePath := 'RCE_logo_transparent.png'; BrandDanPath := 'danruguo_light.png';
  end;
  ExtractTemporaryFile(BrandRcePath); ExtractTemporaryFile(BrandDanPath);
  BrandRcePath := ExpandConstant('{tmp}\') + BrandRcePath;
  BrandDanPath := ExpandConstant('{tmp}\') + BrandDanPath;
  WizardForm.WizardSmallBitmapImage.PngImage.LoadFromFile(BrandRcePath);
  FitBrandImage(WizardForm.WizardSmallBitmapImage, WizardForm.WizardSmallBitmapImage.Left,
    0, WizardForm.WizardSmallBitmapImage.Width);
  WizardForm.WizardSmallBitmapImage.Top :=
    (WizardForm.MainPanel.Height - WizardForm.WizardSmallBitmapImage.Height) div 2;
  WizardForm.WizardBitmapImage2.PngImage.LoadFromFile(BrandRcePath);
  FinishedSignature := TBitmapImage.Create(WizardForm);
  FinishedSignature.Parent := WizardForm.FinishedPage;
  FinishedSignature.PngImage.LoadFromFile(BrandDanPath);
  LayoutFinishedBranding();
  BrandPage := CreateCustomPage(wpWelcome, 'Dan Player', '{#DisplayVersion}');
  UpdatePage := CreateCustomPage(BrandPage.ID, '正在更新 Dan Player', '保留原安装位置和现有快捷方式');
  UpdateNote := TNewStaticText.Create(WizardForm);
  UpdateNote.Parent := UpdatePage.Surface;
  UpdateNote.SetBounds(ScaleX(0), ScaleY(12), UpdatePage.SurfaceWidth, UpdatePage.SurfaceHeight - ScaleY(24));
  UpdateNote.AutoSize := False; UpdateNote.WordWrap := True;
  UpdateNote.Caption := '等待播放器正常退出。可以随时取消，安装器不会强制结束进程。';
  UpdateFlag := ExpandConstant('{param:DANUPDATE|}');
  UpdateMode := (UpdateFlag <> '') or (ExpandConstant('{param:DANPARENTPID|}') <> '') or
    (ExpandConstant('{param:DANUPDATEEVENT|}') <> '') or (ExpandConstant('{param:DANUPDATEVERSION|}') <> '');
  BrandFinished := False;
  BrandStarted := False;
  AutomaticEdit := True;
  DP_SelectionCreate('{#AppVersion}');
  DP_SelectionParent(ExpandConstant('{localappdata}\Programs'));
#ifndef QaBuild
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\DanRuguo.DanPlayer_is1', 'InstallLocation', Previous) then
    DP_SelectionPrevious(RemoveBackslashUnlessRoot(Previous));
#endif
  Forced := ExpandConstant('{param:DIR|}');
  if Forced <> '' then DP_SelectionEdit(Forced);
  RefreshSelection();
  if UpdateMode then begin
    if (UpdateFlag <> '1') or (Forced = '') or WizardSilent or
        (ExpandConstant('{param:DANUPDATEVERSION|}') <> '{#AppVersion}') then
      UpdateFailure := '更新参数无效。尚未修改程序文件，请从播放器重新发起更新。'
    else if DP_UpdateOpen(WizardDirValue, ExpandConstant('{tmp}\payload.manifest'), '{#AppVersion}',
        ExpandConstant('{param:DANPARENTPID|}'), ExpandConstant('{param:DANUPDATEEVENT|}')) = 0 then
      UpdateFailure := '无法验证更新来源。尚未修改程序文件，请从播放器重新发起更新。' + #13#10 + NativeError();
    if UpdateFailure <> '' then begin UpdateNote.Caption := UpdateFailure; Log('UPDATE REJECTED: ' + UpdateFailure); end
    else begin LaunchAfterSuccess := True; Log('Update parent verified and readiness acknowledged'); end;
  end;
  WizardForm.DirEdit.OnChange := @FinalPathChanged;
  WizardForm.DirBrowseButton.Visible := False;
  ParentButton := TNewButton.Create(WizardForm);
  ParentButton.Parent := WizardForm.SelectDirPage;
  ParentButton.SetBounds(WizardForm.DirBrowseButton.Left, WizardForm.DirBrowseButton.Top,
    WizardForm.DirBrowseButton.Width, WizardForm.DirBrowseButton.Height);
  ParentButton.Caption := '选择父目录';
  ParentButton.OnClick := @ChooseParent;
  { Keep both native controls' text metrics and align their centers. }
  WizardForm.DirEdit.Top := ParentButton.Top +
    (ParentButton.Height - WizardForm.DirEdit.Height) div 2;
  DesktopCheck := TNewCheckBox.Create(WizardForm);
  DesktopCheck.Parent := WizardForm.SelectDirPage;
  DesktopCheck.SetBounds(ScaleX(0), ParentButton.Top + ParentButton.Height + ScaleY(12),
    WizardForm.SelectDirPage.Width, ScaleY(28));
  DesktopCheck.Caption := '创建桌面快捷方式';
  DesktopCheck.Checked := True;
#ifdef QaBuild
  DesktopCheck.Checked := ExpandConstant('{param:QADESKTOP|1}') = '1';
#endif
  StartCheck := TNewCheckBox.Create(WizardForm);
  StartCheck.Parent := WizardForm.SelectDirPage;
  StartCheck.SetBounds(ScaleX(0), DesktopCheck.Top + DesktopCheck.Height + ScaleY(6),
    WizardForm.SelectDirPage.Width, ScaleY(28));
  StartCheck.Caption := '创建开始菜单快捷方式';
  StartCheck.Checked := True;
#ifdef QaBuild
  StartCheck.Checked := ExpandConstant('{param:QASTART|1}') = '1';
#endif
  DataNote := TNewStaticText.Create(WizardForm);
  DataNote.Parent := WizardForm.SelectDirPage;
  DataNote.SetBounds(ScaleX(0), StartCheck.Top + StartCheck.Height + ScaleY(8),
    WizardForm.SelectDirPage.Width, ScaleY(66));
  DataNote.AutoSize := False;
  DataNote.WordWrap := True;
  DataNote.Caption := '仅为当前用户安装，不会自动提权。受保护的位置请改选可写文件夹。' + #13#10 +
    '升级保留用户数据；失败备份保存在安装目录旁，供恢复使用。';
  DataNote.AdjustHeight;
  OpenButton := TNewButton.Create(WizardForm);
  OpenButton.Parent := WizardForm.FinishedPage;
  OpenButton.Caption := '打开播放器';
  OpenButton.OnClick := @OpenPlayer;
  DeleteButton := TNewButton.Create(WizardForm);
  DeleteButton.Parent := WizardForm.FinishedPage;
  DeleteButton.Caption := '删除本安装器并关闭';
  DeleteButton.OnClick := @DeleteThisInstaller;
  LayoutFinishedActions();
  { Keep Inno's original footer Top/Height/anchors. Growing these controls
    upwards without shrinking OuterNotebook lets that sibling clip their top. }
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := ((PageID = BrandPage.ID) and WizardSilent) or
    ((PageID = UpdatePage.ID) and not UpdateMode) or ((PageID = wpSelectDir) and UpdateMode);
#ifdef QaBuild
  if (PageID = BrandPage.ID) and (ExpandConstant('{param:QAAUTOINSTALL|0}') = '1') then Result := True;
#endif
end;

procedure CurPageChanged(CurPageID: Integer);
var Background, Accent: LongWord;
begin
  if IsDarkInstallMode then Background := $00202020 else Background := $00F3F3F3;
  Accent := DP_AccentColor();
  WizardForm.PageNameLabel.Alignment := taCenter;
  WizardForm.PageDescriptionLabel.Alignment := taCenter;
  WizardForm.FinishedHeadingLabel.Alignment := taCenter;
  WizardForm.WizardSmallBitmapImage.Visible := CurPageID <> BrandPage.ID;
  { VCL owns the bold HFONT. The native painter borrows WM_GETFONT directly,
    so this changes actual glyph weight without replacing family or size. }
  WizardForm.NextButton.Font.Style := WizardForm.NextButton.Font.Style + [fsBold];
  WizardForm.BackButton.Font.Style := WizardForm.BackButton.Font.Style + [fsBold];
  WizardForm.CancelButton.Font.Style := WizardForm.CancelButton.Font.Style + [fsBold];
  ParentButton.Font.Style := ParentButton.Font.Style + [fsBold];
  OpenButton.Font.Style := OpenButton.Font.Style + [fsBold];
  DeleteButton.Font.Style := DeleteButton.Font.Style + [fsBold];
  DP_StyleButton(WizardForm.NextButton.Handle, Background, Accent, True, ScaleX(6));
  DP_StyleButton(WizardForm.BackButton.Handle, Background, Accent, False, ScaleX(6));
  DP_StyleButton(WizardForm.CancelButton.Handle, Background, Accent, False, ScaleX(6));
  DP_StyleButton(ParentButton.Handle, Background, Accent, False, ScaleX(6));
  DP_StyleButton(OpenButton.Handle, Background, Accent, True, ScaleX(6));
  DP_StyleButton(DeleteButton.Handle, Background, Accent, False, ScaleX(6));
#ifdef QaBuild
  if (CurPageID = wpSelectDir) and (ExpandConstant('{param:QAAUTOINSTALL|0}') = '1') then
    PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0);
#endif
  if CurPageID = BrandPage.ID then begin
    WizardForm.NextButton.Enabled := BrandFinished;
    if not BrandStarted then begin
      BrandStarted := True;
      if DP_ShowBrand(BrandPage.Surface.Handle, BrandPage.SurfaceWidth, BrandPage.SurfaceHeight,
        Background, BrandRcePath, BrandDanPath,
        CreateCallback(@BrandComplete)) = 0 then BrandComplete();
#ifdef QaBuild
      if ExpandConstant('{param:QARENDERROOT|}') <> '' then begin
        QaRenderPhase := 0;
        DP_QA_ScheduleFrame(WizardForm.Handle, 320, CreateCallback(@QaRenderFrame));
      end;
#endif
    end;
  end;
  if UpdateMode and (CurPageID = UpdatePage.ID) then begin
    WizardForm.BackButton.Visible := False;
    WizardForm.NextButton.Enabled := False;
    StartUpdateTimer();
  end;
  if CurPageID = wpFinished then begin
    LayoutFinishedActions();
    LayoutFinishedBranding();
    CenterFinishedFooter();
    OpenButton.Visible := InstallationReady;
    DeleteButton.Visible := InstallationReady;
    if InstallFailure <> '' then begin
      WizardForm.FinishedHeadingLabel.Caption := '安装未完成';
      WizardForm.FinishedLabel.Caption := InstallFailure + #13#10 +
        '关闭后将恢复原有文件。备份保留在：' + BackupPath();
    end;
    if UpdateMode and InstallationReady and (InstallFailure = '') then
      PostMessage(WizardForm.NextButton.Handle, $00F5, 0, 0);
  end;
#ifdef QaBuild
  if (CurPageID = wpSelectDir) and (ExpandConstant('{param:QARENDERROOT|}') <> '') then begin
    QaRenderPhase := 2;
    DP_QA_ScheduleFrame(WizardForm.Handle, 320, CreateCallback(@QaRenderFrame));
  end;
  if (CurPageID = wpFinished) and (ExpandConstant('{param:QARENDERROOT|}') <> '') then begin
    QaRenderPhase := 3;
    DP_QA_ScheduleFrame(WizardForm.Handle, 320, CreateCallback(@QaRenderFrame));
  end;
  if (CurPageID = wpInstalling) and (ExpandConstant('{param:QARENDERROOT|}') <> '') then begin
    if DP_QA_Capture(WizardForm.Handle,
        AddBackslash(ExpandConstant('{param:QARENDERROOT|}')) + 'installing.png') = 1 then
      Log('QA UI rendered nonblank real Inno tree: installing')
    else Log('QA UI RENDER FAILED: installing');
    QaAuditFooter('installing');
    QaAuditGraphic(WizardForm.MainPanel.Handle, WizardForm.WizardSmallBitmapImage, 'installing-rce');
  end;
#endif
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Desktop, StartMenu: String; Recovery: Integer;
begin
  Result := '';
  if UpdateMode and ((UpdateFailure <> '') or not UpdateReady) then begin
    Result := '更新尚未获得许可或播放器尚未正常退出。请取消后重新发起更新。'; Exit;
  end;
  Desktop := ''; StartMenu := '';
  if WantDesktop() then Desktop := DesktopLink('');
  if WantStartMenu() then StartMenu := StartLink('');
  if DP_Configure(WizardDirValue, ExpandConstant('{tmp}\payload.manifest'), Desktop,
      StartMenu, ExpandConstant('{srcexe}')) = 0 then begin
#ifdef QaBuild
    if UpdateMode and (ExpandConstant('{param:QAUPDATEACTION|}') = 'locked') then begin
      QaCancelRequested := True; PostMessage(WizardForm.Handle, $0010, 0, 0);
    end;
#endif
    Result := NativeError(); Exit;
  end;
  Recovery := DP_HasRecovery();
  if Recovery < 0 then begin Result := NativeError(); Exit; end;
  if Recovery = 1 then begin
    if not WizardSilent and (MsgBox('上次安装未完成。是否先恢复已验证的备份？', mbConfirmation, MB_YESNO) <> IDYES) then begin
      Result := '请先恢复上次安装。备份保留在：' + BackupPath(); Exit;
    end;
    if DP_Rollback() = 0 then begin Result := NativeError(); Exit; end;
  end;
  if DP_Begin() = 0 then begin Result := NativeError(); Exit; end;
  TransactionStarted := True;
#ifdef QaBuild
  if ExpandConstant('{param:QAHOLDAFTERBEGIN|0}') = '1' then Sleep(5000);
#endif
end;

procedure FailInstallation(Message: String);
begin
  if InstallFailure = '' then InstallFailure := Message;
  InstallationReady := False;
  Log('INSTALLATION FAILURE: ' + Message);
  { Exceptions in Inno AfterInstall/ssPostInstall are non-fatal. Explicitly
    latch failure, request ordinary cancellation, and never commit/launch. }
  if WizardForm.CurPageID = wpInstalling then
    SendMessage(WizardForm.CancelButton.Handle, $00F5, 0, 0);
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if UpdateMode and not TransactionStarted then begin Cancel := True; Confirm := False; end;
  if InstallFailure <> '' then begin Cancel := True; Confirm := False; end;
#ifdef QaBuild
  if QaCancelRequested then
    begin Cancel := True; Confirm := False; end;
#endif
end;

function GetCustomSetupExitCode(): Integer;
begin
  Result := 0;
  if InstallFailure <> '' then Result := 20;
  if UpdateFailure <> '' then Result := 21;
end;

procedure ShortcutInstalled(Desktop: Boolean);
var Path: String;
begin
  if Desktop then Path := DesktopLink('') else Path := StartLink('');
  if DP_RecordWritten(Path) = 0 then FailInstallation(NativeError());
end;

function ContinueInstall(): Boolean;
begin
  Result := InstallFailure = '';
end;

procedure PayloadInstalled(Path: String);
begin
  if DP_RecordWritten(Path) = 0 then FailInstallation(NativeError());
  CopiedFiles := CopiedFiles + 1;
#ifdef QaBuild
  if StrToIntDef(ExpandConstant('{param:QAFAILAFTER|0}'), 0) = CopiedFiles then
    FailInstallation('Injected QA copy failure');
  if StrToIntDef(ExpandConstant('{param:QACANCELAFTER|0}'), 0) = CopiedFiles then
    begin QaCancelRequested := True; PostMessage(WizardForm.Handle, $0010, 0, 0); end;
#endif
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer; Path: String;
begin
  if CurStep = ssPostInstall then begin
    Path := ExpandConstant('{app}\.dan-player-install\unins000.exe');
    if FileExists(Path) and (DP_RecordWritten(Path) = 0) then FailInstallation(NativeError());
    Path := ExpandConstant('{app}\.dan-player-install\unins000.dat');
    if FileExists(Path) and (DP_RecordWritten(Path) = 0) then FailInstallation(NativeError());
    Path := ExpandConstant('{app}\.dan-player-install\unins000.msg');
    if FileExists(Path) and (DP_RecordWritten(Path) = 0) then FailInstallation(NativeError());
    if InstallFailure <> '' then Exit;
    if DP_VerifyInstalled() = 0 then FailInstallation(NativeError());
    if InstallFailure <> '' then Exit;
    InstallationReady := True;
#ifdef QaBuild
    if ExpandConstant('{param:QAFAILAFTERREADY|0}') = '1' then
      FailInstallation('Injected QA failure after installed-payload verification');
#endif
  end;
  if CurStep = ssDone then begin
    { ssDone is Inno's documented final successful-install event. Keep our
      recovery armed until this point, including any late Inno failure. }
    if InstallFailure <> '' then Exit;
    if DP_Commit() = 0 then begin FailInstallation(NativeError()); Exit; end;
    InstallSucceeded := True;
    TransactionStarted := False;
    Log('Verified installation committed. Retained backup: ' + BackupPath());
#ifndef QaBuild
    if LaunchAfterSuccess and not Exec(ExpandConstant('{app}\Dan Player.exe'), '', ExpandConstant('{app}'),
        SW_SHOWNORMAL, ewNoWait, Code) then
      MsgBox('无法打开播放器，请从安装目录重试。', mbError, MB_OK);
    if DeleteAfterSuccess and (DP_DeleteOriginalInstaller() = 0) then
      MsgBox('安装器已保留：' + NativeError(), mbError, MB_OK);
#endif
  end;
end;

procedure DeinitializeSetup();
begin
  if Assigned(WizardForm) then StopUpdateTimer();
#ifdef QaBuild
  DP_QA_CancelFrame();
#endif
  if TransactionStarted and not InstallSucceeded then begin
    if DP_Rollback() = 0 then begin
      Log('RECOVERY REQUIRED: ' + NativeError() + ' Backup: ' + BackupPath());
      if not WizardSilent then MsgBox('恢复尚未完成，备份未删除。请重新运行安装器恢复：' +
        BackupPath() + #13#10 + NativeError(), mbError, MB_OK);
    end else Log('Original product files and installer metadata restored. Backup retained: ' + BackupPath());
  end;
  DP_CloseControls();
  DP_UpdateClose();
  { Release inherited VCL font selections before removing the private in-memory
    font resource. GDI owns its copied font data, never a temp-file mapping. }
  if Assigned(WizardForm) then WizardForm.Font.Name := 'Segoe UI';
  DP_CloseBrand();
end;
