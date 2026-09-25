unit uGameEngine;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math,
  BASS, // Pastikan unit bass.pas dari BASS Audio Library sudah masuk di search path proyek
  uTelemetryManager, uDataModule;

type
  { TGameEngine }
  TGameEngine = class
  private
    FTelemetry: TTelemetryManager;
    FLastTick: Int64;

    // BASS Audio Handles
    FStreamHandle: HSTREAM;
    FStaticStreamHandle: HSTREAM;
    FIsAudioReady: Boolean;

    // Variabel state untuk procedural audio
    FPhase: Double;

    // Manajemen Target Dinamis
    FTargets: TTargetArray;
    FActiveTargetIndex: Integer;

    // DITAMBAHKAN: Variabel state untuk sistem penalti Enemy Trace
    FLockdownTimer: Double;

    procedure InitAudio;
    procedure ShutdownAudio;
    procedure UpdateAudio;

    function GetActiveTarget: TCelestialTargetDef;
    function GetIsLockdown: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Update;
    procedure SetPlayerInput(const Az, El, Freq: Double);
    procedure InitializeTargets;
    procedure CycleNextTarget;
    procedure ReloadUpgrades;

    // DITAMBAHKAN: Pemicu Lockdown dari MainForm
    procedure TriggerLockdown(DurationInSeconds: Double);

    property Telemetry: TTelemetryManager read FTelemetry;
    property IsAudioReady: Boolean read FIsAudioReady;
    property ActiveTarget: TCelestialTargetDef read GetActiveTarget;

    // DITAMBAHKAN: Properti publik untuk dibaca oleh UI
    property IsLockdown: Boolean read GetIsLockdown;
    property LockdownTimer: Double read FLockdownTimer;
  end;

var
  GlobalEngine: TGameEngine = nil;

implementation

// Callback BASS untuk mengenerate Nada Sinyal (Sine Wave)
function ProceduralAudioProc(handle: LongWord; buffer: Pointer; length: LongWord; user: Pointer): DWord; stdcall;
var
  buf: PSingle;
  samples, i: Integer;
  SNR, SignalAmp, TargetFreq: Double;
  SineVal: Double;
begin
  if (GlobalEngine = nil) or (GlobalEngine.Telemetry = nil) then
    Exit(0);

  buf := PSingle(buffer);
  samples := length div SizeOf(Single);

  SNR := GlobalEngine.Telemetry.CurrentSNR;
  TargetFreq := GlobalEngine.Telemetry.CurrentFreq;

  SignalAmp := (SNR / 100.0) * 0.8;
  if TargetFreq < 20 then TargetFreq := 20;

  for i := 0 to samples - 1 do
  begin
    SineVal := Sin(GlobalEngine.FPhase);

    GlobalEngine.FPhase := GlobalEngine.FPhase + (2.0 * PI * TargetFreq / 44100.0);
    if GlobalEngine.FPhase > (2.0 * PI) then
      GlobalEngine.FPhase := GlobalEngine.FPhase - (2.0 * PI);

    buf[i] := SineVal * SignalAmp;
  end;

  Result := length;
end;

type
  TBassStreamProc = function(handle: LongWord; buffer: Pointer; length: LongWord; user: Pointer): DWord; stdcall;

{ TGameEngine }

constructor TGameEngine.Create;
begin
  GlobalEngine := Self;

  FTelemetry := TTelemetryManager.Create;
  FLastTick := GetTickCount64;
  FPhase := 0.0;
  FLockdownTimer := 0.0; // Inisialisasi timer

  SetLength(FTargets, 0);
  FActiveTargetIndex := -1;

  InitAudio;
end;

destructor TGameEngine.Destroy;
begin
  ShutdownAudio;
  FreeAndNil(FTelemetry);
  GlobalEngine := nil;
  inherited Destroy;
end;

procedure TGameEngine.InitAudio;
var
  ProcCB: TBassStreamProc;
  AudioPath: string;
begin
  FIsAudioReady := BASS_Init(-1, 44100, 0, 0, nil);

  if FIsAudioReady then
  begin
    ProcCB := @ProceduralAudioProc;
    FStreamHandle := BASS_StreamCreate(44100, 1, BASS_SAMPLE_FLOAT, ProcCB, nil);
    if FStreamHandle <> 0 then
      BASS_ChannelPlay(FStreamHandle, False);

    AudioPath := ExtractFilePath(ParamStr(0)) + 'assets' + DirectorySeparator + 'audio' + DirectorySeparator + 'radio_ambient.mp3';
    FStaticStreamHandle := BASS_StreamCreateFile(False, PChar(AudioPath), 0, 0, BASS_SAMPLE_LOOP);
    if FStaticStreamHandle <> 0 then
      BASS_ChannelPlay(FStaticStreamHandle, False);
  end;
end;

procedure TGameEngine.ShutdownAudio;
begin
  if FIsAudioReady then
  begin
    if FStaticStreamHandle <> 0 then
    begin
      BASS_ChannelStop(FStaticStreamHandle);
      BASS_StreamFree(FStaticStreamHandle);
    end;

    if FStreamHandle <> 0 then
    begin
      BASS_ChannelStop(FStreamHandle);
      BASS_StreamFree(FStreamHandle);
    end;

    BASS_Free;
  end;
end;

procedure TGameEngine.UpdateAudio;
var
  NoiseVol: Double;
begin
  if not FIsAudioReady then Exit;

  // DITAMBAHKAN: Matikan semua suara jika sistem Overheat atau sedang Lockdown
  if (FTelemetry.State = tsOverheated) or (FLockdownTimer > 0) then
  begin
    if FStreamHandle <> 0 then BASS_ChannelSetAttribute(FStreamHandle, BASS_ATTRIB_VOL, 0.0);
    if FStaticStreamHandle <> 0 then BASS_ChannelSetAttribute(FStaticStreamHandle, BASS_ATTRIB_VOL, 0.0);
  end
  else
  begin
    if FStreamHandle <> 0 then BASS_ChannelSetAttribute(FStreamHandle, BASS_ATTRIB_VOL, 1.0);

    NoiseVol := (100.0 - FTelemetry.CurrentSNR) / 100.0;
    if NoiseVol < 0.0 then NoiseVol := 0.0;
    if NoiseVol > 1.0 then NoiseVol := 1.0;

    if FStaticStreamHandle <> 0 then
      BASS_ChannelSetAttribute(FStaticStreamHandle, BASS_ATTRIB_VOL, NoiseVol);
  end;
end;

procedure TGameEngine.Update;
var
  CurrentTick: Int64;
  DeltaTime: Double;
begin
  CurrentTick := GetTickCount64;
  DeltaTime := (CurrentTick - FLastTick) / 1000.0;
  FLastTick := CurrentTick;

  if DeltaTime > 0.1 then DeltaTime := 0.1;

  // DITAMBAHKAN: Jalankan hitung mundur Lockdown jika sedang aktif
  if FLockdownTimer > 0 then
  begin
    FLockdownTimer := FLockdownTimer - DeltaTime;
    if FLockdownTimer < 0 then FLockdownTimer := 0;
  end;

  FTelemetry.Update(DeltaTime);
  UpdateAudio;
end;

procedure TGameEngine.SetPlayerInput(const Az, El, Freq: Double);
var
  DeltaTime: Double;
begin
  // DITAMBAHKAN: Blokir kontrol fisik dan gelombang jika sistem dikunci musuh
  if FLockdownTimer > 0 then Exit;

  DeltaTime := 0.016;
  FTelemetry.MoveAntenna(Az, El, DeltaTime);
  FTelemetry.SetFrequency(Freq);
end;

procedure TGameEngine.ReloadUpgrades;
var
  Upgrades: TUpgradeArray;
  i, BeamLvl, CoolLvl, FreqLvl: Integer;
begin
  BeamLvl := 0;
  CoolLvl := 0;
  FreqLvl := 0;

  Upgrades := GameDataModule.LoadUpgrades;

  for i := 0 to High(Upgrades) do
  begin
    if Upgrades[i].UpgradeID = 'UPG_BEAM' then
      BeamLvl := Upgrades[i].CurrentLevel
    else if Upgrades[i].UpgradeID = 'UPG_COOL' then
      CoolLvl := Upgrades[i].CurrentLevel
    else if Upgrades[i].UpgradeID = 'UPG_FREQ' then
      FreqLvl := Upgrades[i].CurrentLevel;
  end;

  FTelemetry.ApplyUpgrades(BeamLvl, CoolLvl, FreqLvl);
end;

procedure TGameEngine.InitializeTargets;
var
  i: Integer;
begin
  ReloadUpgrades;
  FTargets := GameDataModule.LoadCelestialTargets;

  Randomize;
  for i := 0 to High(FTargets) do
  begin
    FTargets[i].Azimuth := Random(360);
    FTargets[i].Elevation := Random(90);
    FTargets[i].Frequency := 100.0 + (Random(5000) / 100.0);
  end;

  FActiveTargetIndex := 0;

  if Length(FTargets) > 0 then
    FTelemetry.AssignCelestialTarget(
      FTargets[FActiveTargetIndex].Azimuth,
      FTargets[FActiveTargetIndex].Elevation,
      FTargets[FActiveTargetIndex].Frequency
    )
  else
    FTelemetry.AssignCelestialTarget(120.5, 45.0, 137.50);
end;

procedure TGameEngine.CycleNextTarget;
begin
  if Length(FTargets) = 0 then Exit;

  Inc(FActiveTargetIndex);
  if FActiveTargetIndex >= Length(FTargets) then
    FActiveTargetIndex := 0;

  FTelemetry.AssignCelestialTarget(
    FTargets[FActiveTargetIndex].Azimuth,
    FTargets[FActiveTargetIndex].Elevation,
    FTargets[FActiveTargetIndex].Frequency
  );
end;

function TGameEngine.GetActiveTarget: TCelestialTargetDef;
begin
  if (Length(FTargets) > 0) and (FActiveTargetIndex >= 0) and (FActiveTargetIndex < Length(FTargets)) then
    Result := FTargets[FActiveTargetIndex]
  else
  begin
    Result.ID := -1;
    Result.TargetName := 'UNKNOWN ANOMALY';
    Result.HexSignature := '41 4C 50 48 41 2D 43 45 4E 54 41 55 52 49';
  end;
end;

// DITAMBAHKAN: Fungsi pembacaan status dan pemicu lockdown
function TGameEngine.GetIsLockdown: Boolean;
begin
  Result := FLockdownTimer > 0;
end;

procedure TGameEngine.TriggerLockdown(DurationInSeconds: Double);
begin
  FLockdownTimer := DurationInSeconds;

  // Hukuman tambahan: Tendang paksa frekuensi pemain ke ujung bawah agar
  // mereka kehilangan jejak sinyal target setelah lockdown selesai.
  FTelemetry.SetFrequency(100.0);
end;

end.
