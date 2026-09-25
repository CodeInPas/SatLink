unit uMainForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus,  BGRABitmap, BGRABitmapTypes,
  uGameEngine, uConfigManager, uTelemetryManager, uDataModule,
  uDecryptForm, uUpgradeForm, uLogViewerForm, UnitAbout;

type
  { TfrmMain }
  TfrmMain = class(TForm)
    btnUpgrade: TButton;
    btnViewLogs: TButton;
    cbVisualMode: TComboBox;
    lblAzimuth: TLabel;
    lblCredits: TLabel;
    lblElevation: TLabel;
    lblFrequency: TLabel;
    lblStatus: TLabel;
    lblVisualMode: TLabel;
    MainMenu1: TMainMenu;
    memoConsole: TMemo;
    MenuItem1: TMenuItem;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    mnAbout: TMenuItem;
    Panel1: TPanel;
    pbRadarOK: TPaintBox;
    pnlTerminal: TPanel;
    pbTerminal: TPaintBox;

    pnlControls: TPanel;

    lblMotorTemp: TLabel;
    lblSNR: TLabel;

    GameLoopTimer: TTimer;
    tbAzimuth: TTrackBar;
    tbElevation: TTrackBar;
    tbFrequency: TTrackBar;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure GameLoopTimerTimer(Sender: TObject);
    procedure MenuItem3Click(Sender: TObject);
    procedure mnAboutClick(Sender: TObject);
    procedure pbRadarOKPaint(Sender: TObject);
    procedure pbTerminalPaint(Sender: TObject);
    procedure InputChange(Sender: TObject);
    procedure btnUpgradeClick(Sender: TObject);
    procedure btnViewLogsClick(Sender: TObject);
    procedure cbVisualModeChange(Sender: TObject);
  private
    FEngine: TGameEngine;

    FMainBuffer: TBGRABitmap;
    FFFTBuffer: TBGRABitmap;
    FFFTLineIndex: Integer;
    FRadarBuffer: TBGRABitmap;
    FOscPhase: Double;
    FIsDecrypting: Boolean;

    // Buffer Histori Garis Seismometer
    FSeismoHistory: array of Integer;

    // Mesin Render Visual
    procedure RenderRedWaterfall(TargetBMP: TBGRABitmap; Bounds: TRect);
    procedure RenderBlueSDR(TargetBMP: TBGRABitmap; Bounds: TRect);
    procedure RenderOscilloscope(TargetBMP: TBGRABitmap; Bounds: TRect);
    procedure RenderSpectrum(TargetBMP: TBGRABitmap; Bounds: TRect);
    procedure RenderSeismometer(TargetBMP: TBGRABitmap; Bounds: TRect);

    procedure RenderRadar(TargetBMP: TBGRABitmap; Bounds: TRect);
    procedure UpdateTelemetryUI;
    procedure UpdateCreditsUI;
  public
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FEngine := TGameEngine.Create;
  FEngine.InitializeTargets;

  FMainBuffer := TBGRABitmap.Create(800, 600);
  FFFTBuffer := TBGRABitmap.Create(800, 256, BGRA(0, 0, 0, 255));
  FRadarBuffer := TBGRABitmap.Create(300, 300, BGRA(0, 0, 0, 255));
  FFFTLineIndex := 0;
  FOscPhase := 0.0;

  FIsDecrypting := False;
  SetLength(FSeismoHistory, 0);

  GameLoopTimer.Interval := 16;
  GameLoopTimer.Enabled := True;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  GameLoopTimer.Enabled := False;
  FreeAndNil(FFFTBuffer);
  FreeAndNil(FRadarBuffer);
  FreeAndNil(FMainBuffer);
  FreeAndNil(FEngine);
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  tbAzimuth.Position := Round(Config.LastAzimuth);
  tbElevation.Position := Round(Config.LastElevation);
  InputChange(Self);
  UpdateCreditsUI;
end;

procedure TfrmMain.cbVisualModeChange(Sender: TObject);
var
  i: Integer;
begin
  if cbVisualMode.ItemIndex = 4 then
  begin
    for i := 0 to High(FSeismoHistory) do
      FSeismoHistory[i] := pbTerminal.Height div 2;
  end;
  pbTerminal.Invalidate;
end;

procedure TfrmMain.InputChange(Sender: TObject);
begin
  if FEngine.IsLockdown then Exit;

  // HANYA perbarui teks label UI di sini. Input fisik dipindahkan ke Game Loop!
  lblAzimuth.Caption := Format('AZ: %d°', [tbAzimuth.Position]);
  lblElevation.Caption := Format('EL: %d°', [tbElevation.Position]);
  lblFrequency.Caption := Format('FREQ: %.2f MHz', [tbFrequency.Position / 100.0]);
end;

procedure TfrmMain.UpdateCreditsUI;
begin
  lblCredits.Caption := Format('INTEL CREDITS: %d', [GameDataModule.GetIntelCredits]);
end;

procedure TfrmMain.btnUpgradeClick(Sender: TObject);
var
  UpgradeFrm: TfrmUpgrade;
begin
  UpgradeFrm := TfrmUpgrade.Create(Self);
  try
    UpgradeFrm.ShowModal;
  finally
    UpgradeFrm.Free;
    // Terapkan upgrade ke fisika setelah kembali dari form upgrade
    FEngine.ReloadUpgrades;
    UpdateCreditsUI;
  end;
end;

procedure TfrmMain.btnViewLogsClick(Sender: TObject);
var
  FLogV : TfrmLogViewer;
begin
  try
    FLogV:= TfrmLogViewer.Create(self);
    FLogV.ShowModal;
  finally
    FLogV.Free;
  end;
end;

procedure TfrmMain.GameLoopTimerTimer(Sender: TObject);
var
  DecryptFrm: TfrmDecrypt;
  DecResult: TModalResult;
begin
  if FIsDecrypting then Exit;

  if not FEngine.IsLockdown then
    FEngine.SetPlayerInput(tbAzimuth.Position, tbElevation.Position, tbFrequency.Position / 100.0);

  FEngine.Update;
  UpdateTelemetryUI;
  pbTerminal.Invalidate;
  if Assigned(pbRadarOK) then pbRadarOK.Invalidate;

  // Sinkronisasikan slider dengan mesin jika ada perubahan eksternal (contoh: lockdown)
  if FEngine.IsLockdown then
  begin
    // Pastikan slider terlempar kembali ke 100.0 MHz seperti perintah mesin
    tbFrequency.Position := Round(FEngine.Telemetry.CurrentFreq * 100);
    lblFrequency.Caption := Format('FREQ: %.2f MHz', [FEngine.Telemetry.CurrentFreq]);
  end;

  if FEngine.Telemetry.State = tsLocked then
  begin
    FIsDecrypting := True;
    memoConsole.Lines.Add(Format('>>> [%s] SIGNAL LOCKED. INTERCEPTING PAYLOAD...', [FEngine.ActiveTarget.TargetName]));

    DecryptFrm := TfrmDecrypt.Create(Self);
    try
      DecryptFrm.InitializeSignal(
        FEngine.ActiveTarget.ID,
        FEngine.ActiveTarget.HexSignature,
        FEngine.Telemetry.AntennaPos.Azimuth,
        FEngine.Telemetry.AntennaPos.Elevation,
        FEngine.Telemetry.CurrentFreq,
        FEngine.Telemetry.CurrentSNR
      );

      // Tampilkan form dan tangkap kembalian status
      DecResult := DecryptFrm.ShowModal;

      if DecResult = mrOk then
      begin
        GameDataModule.AddIntelCredits(50);
        memoConsole.Lines.Add('>>> PAYLOAD DECRYPTED. +50 INTEL CREDITS AWARDED.');
        UpdateCreditsUI;
      end
      else if DecResult = mrAbort then // PENALTI: Gagal dekripsi sebelum batas pelacakan
      begin
        memoConsole.Lines.Add('>>> CRITICAL: ENEMY TRACE COMPLETE. TRIGGERING LOCKDOWN!');
        // Panggil Lockdown Engine selama 30 detik
        FEngine.TriggerLockdown(30.0);
      end
      else
      begin
        memoConsole.Lines.Add('>>> DECRYPTION ABORTED.');
      end;

      if not FEngine.IsLockdown then
      begin
        tbFrequency.Position := tbFrequency.Position + 150;
        if tbFrequency.Position > tbFrequency.Max then tbFrequency.Position := tbFrequency.Min;
        InputChange(Self);
      end;

      FEngine.CycleNextTarget;
      memoConsole.Lines.Add('>>> AWAITING NEW TARGET ACQUISITION...');

    finally
      DecryptFrm.Free;
      FIsDecrypting := False;
    end;
  end;
end;

procedure TfrmMain.MenuItem3Click(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TfrmMain.mnAboutClick(Sender: TObject);
var
  FAbout : TFormAbout;
begin
  try
    FAbout := TFormAbout.Create(self) ;
    FAbout.ShowModal ;
  finally
    FAbout.free;
  end;
end;

procedure TfrmMain.pbRadarOKPaint(Sender: TObject);
begin
  if not Assigned(FRadarBuffer) then Exit;

  if (FRadarBuffer.Width <> pbRadarOK.Width) or (FRadarBuffer.Height <> pbRadarOK.Height) then
    BGRAReplace(FRadarBuffer, FRadarBuffer.Resample(pbRadarOK.Width, pbRadarOK.Height) as TBGRABitmap);

  RenderRadar(FRadarBuffer, Rect(0, 0, pbRadarOK.Width, pbRadarOK.Height));
  FRadarBuffer.Draw(pbRadarOK.Canvas, 0, 0, False);
end;

procedure TfrmMain.UpdateTelemetryUI;
var
  Tel: TTelemetryManager;
begin
  Tel := FEngine.Telemetry;

  lblMotorTemp.Caption := Format('TEMP: %.1f °C', [Tel.MotorTemp]);
  lblSNR.Caption := Format('SNR: %.1f dB', [Tel.CurrentSNR]);

  if FEngine.IsLockdown then
  begin
    lblStatus.Caption := Format('SYSTEM LOCKDOWN: %.0fs', [FEngine.LockdownTimer]);
    lblStatus.Font.Color := clRed;
    Exit;
  end;

  case Tel.State of
    tsIdle: begin
      lblStatus.Caption := 'STATUS: SEARCHING...';
      lblStatus.Font.Color := clGray;
    end;
    tsTracking: begin
      lblStatus.Caption := 'STATUS: SIGNAL DETECTED';
      lblStatus.Font.Color := clYellow;
    end;
    tsLocked: begin
      lblStatus.Caption := 'STATUS: LOCKED & DECRYPTING';
      lblStatus.Font.Color := clLime;
    end;
    tsOverheated: begin
      lblStatus.Caption := 'STATUS: SYSTEM OVERHEATED!';
      lblStatus.Font.Color := clRed;
    end;
  end;
end;

procedure TfrmMain.pbTerminalPaint(Sender: TObject);
var
  Tel: TTelemetryManager;
  Dist: Double;
  TipText: string;
  TextW, FreqLower, FreqUpper: Integer;
begin
  if (FMainBuffer.Width <> pbTerminal.Width) or (FMainBuffer.Height <> pbTerminal.Height) then
  begin
    BGRAReplace(FMainBuffer, FMainBuffer.Resample(pbTerminal.Width, pbTerminal.Height) as TBGRABitmap);
    FreeAndNil(FFFTBuffer);
    FFFTBuffer := TBGRABitmap.Create(pbTerminal.Width, pbTerminal.Height, BGRA(0, 0, 0, 255));
    FFFTLineIndex := 0;
    FMainBuffer.Fill(BGRA(10, 15, 20, 255));
  end;

  case cbVisualMode.ItemIndex of
    0:
    begin
      FMainBuffer.Fill(BGRA(10, 15, 20, 255));
      RenderRedWaterfall(FMainBuffer, Rect(0, 0, pbTerminal.Width, pbTerminal.Height));
    end;
    1:
    begin
      FMainBuffer.Fill(BGRA(10, 15, 20, 255));
      RenderBlueSDR(FMainBuffer, Rect(0, 0, pbTerminal.Width, pbTerminal.Height));
    end;
    2:
    begin
      FMainBuffer.FillRect(0, 0, pbTerminal.Width, pbTerminal.Height, BGRA(5, 10, 5, 40), dmDrawWithTransparency);
      RenderOscilloscope(FMainBuffer, Rect(0, 0, pbTerminal.Width, pbTerminal.Height));
    end;
    3:
    begin
      FMainBuffer.FillRect(0, 0, pbTerminal.Width, pbTerminal.Height, BGRA(5, 10, 15, 40), dmDrawWithTransparency);
      RenderSpectrum(FMainBuffer, Rect(0, 0, pbTerminal.Width, pbTerminal.Height));
    end;
    4:
    begin
      FMainBuffer.Fill(BGRA(5, 10, 5, 255));
      RenderSeismometer(FMainBuffer, Rect(0, 0, pbTerminal.Width, pbTerminal.Height));
    end;
  end;

  // ==============================================================================
  // DYNAMIC TIPS (Sistem Bantuan Kontekstual + Intelijen Target)
  // ==============================================================================
  Tel := FEngine.Telemetry;
  Dist := Sqrt(Sqr(Tel.AntennaPos.Azimuth - Tel.TargetPos.Azimuth) + Sqr(Tel.AntennaPos.Elevation - Tel.TargetPos.Elevation));

  FreqLower := Trunc(Tel.TargetFreq / 10.0) * 10;
  FreqUpper := FreqLower + 10;

  // Update Teks jika sedang Lockdown
  if FEngine.IsLockdown then
    TipText := 'CRITICAL: ENEMY TRACE COMPLETE. TERMINAL LOCKED BY PROXY FIREWALL!'
  else if Tel.State = tsOverheated then
    TipText := 'SYSTEM OVERHEATED: Release controls! Wait for cooling motors to reduce temperature.'
  else if Dist > 25.0 then
    TipText := Format('HINT: Intel reports an anomaly near [AZ: %d° | EL: %d°]. Align the radar!', [Round(Tel.TargetPos.Azimuth), Round(Tel.TargetPos.Elevation)])
  else if Tel.CurrentSNR < 2.0 then
    TipText := Format('HINT: Antenna aligned. Sweep FREQUENCY in the %d - %d MHz range until signal line appears.', [FreqLower, FreqUpper])
  else if Tel.CurrentSNR < 15.0 then
    TipText := 'HINT: Anomaly detected! Perform subtle fine-tuning on the sliders to maximize SNR.'
  else
    TipText := 'HINT: Hold position! Signal is extremely strong, system is locking onto the target...';

  FMainBuffer.FillRect(0, FMainBuffer.Height - 35, FMainBuffer.Width, FMainBuffer.Height, BGRA(0, 0, 0, 180), dmDrawWithTransparency);

  FMainBuffer.FontName := 'Consolas';
  FMainBuffer.FontHeight := 16;
  FMainBuffer.FontStyle := [fsBold];

  TextW := FMainBuffer.TextSize(TipText).cx;

  if FEngine.IsLockdown then
    FMainBuffer.TextOut((FMainBuffer.Width - TextW) div 2, FMainBuffer.Height - 27, TipText, BGRA(255, 0, 0, 255))
  else
    FMainBuffer.TextOut((FMainBuffer.Width - TextW) div 2, FMainBuffer.Height - 27, TipText, BGRA(255, 255, 0, 255));
  // ==============================================================================

  FMainBuffer.Draw(pbTerminal.Canvas, 0, 0, False);
end;

// ==============================================================================
// 1. TACTICAL RED WATERFALL (Klasik)
// ==============================================================================
procedure TfrmMain.RenderRedWaterfall(TargetBMP: TBGRABitmap; Bounds: TRect);
var
  pLine: PBGRAPixel;
  x, TargetX, CalcIntensity: Integer;
  Tel: TTelemetryManager;
  bmpPart: TBGRABitmap;
  Dist, SpatialMatch: Double;
begin
  Tel := FEngine.Telemetry;
  pLine := FFFTBuffer.ScanLine[FFFTLineIndex];
  TargetX := Round(((Tel.TargetFreq - 100.0) / 50.0) * FFFTBuffer.Width);

  Dist := Sqrt(Sqr(Tel.AntennaPos.Azimuth - Tel.TargetPos.Azimuth) + Sqr(Tel.AntennaPos.Elevation - Tel.TargetPos.Elevation));
  if Dist < 25.0 then SpatialMatch := (25.0 - Dist) / 25.0 else SpatialMatch := 0;

  for x := 0 to FFFTBuffer.Width - 1 do
  begin
    CalcIntensity := 20 + Random(70);
    if (x mod 40 = 0) then CalcIntensity := CalcIntensity + 30;

    // Matikan grafik jika sedang dilockdown
    if not FEngine.IsLockdown then
    begin
      if (abs(x - TargetX) < 15) and (SpatialMatch > 0) then
        CalcIntensity := CalcIntensity + Round((SpatialMatch * 150.0) * (1.0 - (abs(x - TargetX) / 15.0)));

      if (abs(x - TargetX) < 15) and (Tel.CurrentSNR > 2.0) then
        CalcIntensity := CalcIntensity + Round((Tel.CurrentSNR / 100.0) * 100.0);
    end;

    if CalcIntensity > 255 then CalcIntensity := 255;

    if CalcIntensity < 80 then pLine^ := BGRA(CalcIntensity + 100, 0, 0, 255)
    else if CalcIntensity < 150 then pLine^ := BGRA(255, CalcIntensity + 50, 0, 255)
    else if CalcIntensity < 220 then pLine^ := BGRA(0, 255, 255, 255)
    else pLine^ := BGRA(255, 255, 255, 255);
    Inc(pLine);
  end;

  bmpPart := FFFTBuffer.GetPart(Rect(0, FFFTLineIndex, FFFTBuffer.Width, FFFTBuffer.Height)) as TBGRABitmap;
  TargetBMP.PutImage(Bounds.Left, Bounds.Top, bmpPart, dmDrawWithTransparency, 255);
  bmpPart.Free;
  bmpPart := FFFTBuffer.GetPart(Rect(0, 0, FFFTBuffer.Width, FFFTLineIndex)) as TBGRABitmap;
  TargetBMP.PutImage(Bounds.Left, Bounds.Top + (FFFTBuffer.Height - FFFTLineIndex), bmpPart, dmDrawWithTransparency, 255);
  bmpPart.Free;

  Dec(FFFTLineIndex);
  if FFFTLineIndex < 0 then FFFTLineIndex := FFFTBuffer.Height - 1;
end;

// ==============================================================================
// 2. COLD BLUE SDR MATRIX
// ==============================================================================
procedure TfrmMain.RenderBlueSDR(TargetBMP: TBGRABitmap; Bounds: TRect);
var
  pLine: PBGRAPixel;
  x, TargetX, CalcIntensity: Integer;
  Tel: TTelemetryManager;
  bmpPart: TBGRABitmap;
  Dist, SpatialMatch: Double;
begin
  Tel := FEngine.Telemetry;
  pLine := FFFTBuffer.ScanLine[FFFTLineIndex];
  TargetX := Round(((Tel.TargetFreq - 100.0) / 50.0) * FFFTBuffer.Width);

  Dist := Sqrt(Sqr(Tel.AntennaPos.Azimuth - Tel.TargetPos.Azimuth) + Sqr(Tel.AntennaPos.Elevation - Tel.TargetPos.Elevation));
  if Dist < 25.0 then SpatialMatch := (25.0 - Dist) / 25.0 else SpatialMatch := 0;

  for x := 0 to FFFTBuffer.Width - 1 do
  begin
    CalcIntensity := 10 + Random(50);
    if (x mod 50 = 0) then CalcIntensity := CalcIntensity + 20;

    if not FEngine.IsLockdown then
    begin
      if (abs(x - TargetX) < 15) and (SpatialMatch > 0) then
        CalcIntensity := CalcIntensity + Round((SpatialMatch * 150.0) * (1.0 - (abs(x - TargetX) / 15.0)));

      if (abs(x - TargetX) < 15) and (Tel.CurrentSNR > 2.0) then
        CalcIntensity := CalcIntensity + Round((Tel.CurrentSNR / 100.0) * 100.0);
    end;

    if CalcIntensity > 255 then CalcIntensity := 255;

    if CalcIntensity < 80 then pLine^ := BGRA(0, 20, CalcIntensity + 80, 255)
    else if CalcIntensity < 150 then pLine^ := BGRA(0, CalcIntensity, 255, 255)
    else if CalcIntensity < 220 then pLine^ := BGRA(100, 255, 255, 255)
    else pLine^ := BGRA(255, 255, 255, 255);
    Inc(pLine);
  end;

  bmpPart := FFFTBuffer.GetPart(Rect(0, FFFTLineIndex, FFFTBuffer.Width, FFFTBuffer.Height)) as TBGRABitmap;
  TargetBMP.PutImage(Bounds.Left, Bounds.Top, bmpPart, dmDrawWithTransparency, 255);
  bmpPart.Free;
  bmpPart := FFFTBuffer.GetPart(Rect(0, 0, FFFTBuffer.Width, FFFTLineIndex)) as TBGRABitmap;
  TargetBMP.PutImage(Bounds.Left, Bounds.Top + (FFFTBuffer.Height - FFFTLineIndex), bmpPart, dmDrawWithTransparency, 255);
  bmpPart.Free;

  Dec(FFFTLineIndex);
  if FFFTLineIndex < 0 then FFFTLineIndex := FFFTBuffer.Height - 1;
end;

// ==============================================================================
// 3. REAL-TIME OSCILLOSCOPE
// ==============================================================================
procedure TfrmMain.RenderOscilloscope(TargetBMP: TBGRABitmap; Bounds: TRect);
var
  x, CenterY, prevX, prevY, currY: Integer;
  Tel: TTelemetryManager;
  SNR, NoiseLevel, SignalAmp, WaveFreq: Double;
begin
  Tel := FEngine.Telemetry;
  CenterY := Bounds.Top + (Bounds.Bottom - Bounds.Top) div 2;

  if FEngine.IsLockdown then SNR := 0 else SNR := Tel.CurrentSNR;

  TargetBMP.DrawLineAntialias(Bounds.Left, CenterY, Bounds.Right, CenterY, BGRA(0, 50, 0, 100), 1);
  TargetBMP.DrawLineAntialias(Bounds.Left + (Bounds.Right div 2), Bounds.Top, Bounds.Left + (Bounds.Right div 2), Bounds.Bottom, BGRA(0, 50, 0, 100), 1);

  SignalAmp := (SNR / 100.0) * ((Bounds.Bottom - Bounds.Top) div 3);
  NoiseLevel := ((100.0 - SNR) / 100.0) * 80.0;

  WaveFreq := 0.02 + (0.08 * (1.0 - (abs(Tel.CurrentFreq - Tel.TargetFreq) / 5.0)));
  if WaveFreq < 0 then WaveFreq := 0.01;

  FOscPhase := FOscPhase + 0.3;
  if FOscPhase > 1000.0 then FOscPhase := 0.0;

  prevX := Bounds.Left;
  prevY := CenterY + Round(Sin(FOscPhase) * SignalAmp + (Random(Round(NoiseLevel)+1) - (NoiseLevel/2)));

  for x := Bounds.Left + 1 to Bounds.Right - 1 do
  begin
    currY := CenterY + Round(Sin((x * WaveFreq) + FOscPhase) * SignalAmp + (Random(Round(NoiseLevel)+1) - (NoiseLevel/2)));
    TargetBMP.DrawLineAntialias(prevX, prevY, x, currY, BGRA(50, 255, 50, 255), 2);
    prevX := x;
    prevY := currY;
  end;
end;

// ==============================================================================
// 4. FFT SPECTRUM ANALYZER
// ==============================================================================
procedure TfrmMain.RenderSpectrum(TargetBMP: TBGRABitmap; Bounds: TRect);
var
  x, BaseY, prevX, prevY, currY: Integer;
  Tel: TTelemetryManager;
  TargetX, Distance: Integer;
  Dist, SpatialMatch, NoiseLevel, SignalAmp: Double;
begin
  Tel := FEngine.Telemetry;
  BaseY := Bounds.Bottom - 20;
  TargetX := Bounds.Left + Round(((Tel.TargetFreq - 100.0) / 50.0) * (Bounds.Right - Bounds.Left));

  Dist := Sqrt(Sqr(Tel.AntennaPos.Azimuth - Tel.TargetPos.Azimuth) + Sqr(Tel.AntennaPos.Elevation - Tel.TargetPos.Elevation));
  if Dist < 25.0 then SpatialMatch := (25.0 - Dist) / 25.0 else SpatialMatch := 0;

  TargetBMP.DrawLineAntialias(Bounds.Left, BaseY, Bounds.Right, BaseY, BGRA(0, 100, 100, 150), 1);
  TargetBMP.DrawLineAntialias(Bounds.Left + ((Bounds.Right - Bounds.Left) div 2), Bounds.Top, Bounds.Left + ((Bounds.Right - Bounds.Left) div 2), Bounds.Bottom, BGRA(0, 100, 100, 150), 1);

  prevX := Bounds.Left;
  prevY := BaseY;

  for x := Bounds.Left + 1 to Bounds.Right - 1 do
  begin
    Distance := abs(x - TargetX);

    if FEngine.IsLockdown then
      NoiseLevel := Random(35)
    else
      NoiseLevel := Random(Round(((100.0 - Tel.CurrentSNR) / 100.0) * 30.0) + 5);

    if (not FEngine.IsLockdown) and (Distance < 30) and (SpatialMatch > 0.05) then
    begin
      SignalAmp := (SpatialMatch * (Bounds.Bottom - 80.0)) * (1.0 - (Distance / 30.0));
      if Tel.CurrentSNR > 2.0 then
        SignalAmp := SignalAmp + ((Tel.CurrentSNR / 100.0) * (Bounds.Bottom - 80.0) * (1.0 - (Distance / 30.0)));
    end
    else
      SignalAmp := 0;

    currY := BaseY - Round(SignalAmp + NoiseLevel);
    TargetBMP.DrawLineAntialias(prevX, prevY, x, currY, BGRA(0, 255, 255, 255), 2);
    prevX := x;
    prevY := currY;
  end;
end;

// ==============================================================================
// 5. DIGITAL SEISMOMETER (Taktis, bergerak dari Kanan ke Kiri)
// ==============================================================================
procedure TfrmMain.RenderSeismometer(TargetBMP: TBGRABitmap; Bounds: TRect);
var
  x, CenterY, NewY: Integer;
  Tel: TTelemetryManager;
  Dist, SpatialMatch, FreqDist, NoiseLevel, SignalAmp: Double;
begin
  Tel := FEngine.Telemetry;
  CenterY := Bounds.Top + (Bounds.Bottom - Bounds.Top) div 2;

  if Length(FSeismoHistory) <> (Bounds.Right - Bounds.Left) then
  begin
    SetLength(FSeismoHistory, Bounds.Right - Bounds.Left);
    for x := 0 to High(FSeismoHistory) do
      FSeismoHistory[x] := CenterY;
  end;

  for x := 0 to (Bounds.Right - Bounds.Left) div 40 do
    TargetBMP.DrawLineAntialias(Bounds.Left + (x * 40), Bounds.Top, Bounds.Left + (x * 40), Bounds.Bottom, BGRA(0, 80, 0, 80), 1);
  for x := 0 to (Bounds.Bottom - Bounds.Top) div 40 do
    TargetBMP.DrawLineAntialias(Bounds.Left, Bounds.Top + (x * 40), Bounds.Right, Bounds.Top + (x * 40), BGRA(0, 80, 0, 80), 1);

  TargetBMP.DrawLineAntialias(Bounds.Left, CenterY, Bounds.Right, CenterY, BGRA(0, 150, 0, 150), 2);

  for x := 0 to High(FSeismoHistory) - 2 do
    FSeismoHistory[x] := FSeismoHistory[x + 2];

  Dist := Sqrt(Sqr(Tel.AntennaPos.Azimuth - Tel.TargetPos.Azimuth) + Sqr(Tel.AntennaPos.Elevation - Tel.TargetPos.Elevation));
  if Dist < 25.0 then SpatialMatch := (25.0 - Dist) / 25.0 else SpatialMatch := 0;

  FreqDist := abs(Tel.CurrentFreq - Tel.TargetFreq);

  if FEngine.IsLockdown then
    NoiseLevel := 15.0
  else
    NoiseLevel := ((100.0 - Tel.CurrentSNR) / 100.0) * 15.0;

  SignalAmp := 0;
  if (not FEngine.IsLockdown) and (FreqDist < 2.0) and (SpatialMatch > 0.05) then
  begin
    SignalAmp := (SpatialMatch * (Bounds.Bottom div 3)) * (1.0 - (FreqDist / 2.0));
    if Tel.CurrentSNR > 2.0 then
      SignalAmp := SignalAmp + ((Tel.CurrentSNR / 100.0) * (Bounds.Bottom div 3));
  end;

  NewY := CenterY + Round((Random(200) / 100.0 - 1.0) * (NoiseLevel + SignalAmp));

  if Tel.State = tsLocked then
    NewY := CenterY + Round(Sin(GetTickCount64 / 20.0) * (Bounds.Bottom div 3));

  FSeismoHistory[High(FSeismoHistory) - 1] := (FSeismoHistory[High(FSeismoHistory) - 2] + NewY) div 2;
  FSeismoHistory[High(FSeismoHistory)] := NewY;

  for x := 1 to High(FSeismoHistory) do
  begin
    if FEngine.IsLockdown then
      TargetBMP.DrawLineAntialias(Bounds.Left + x - 1, FSeismoHistory[x - 1], Bounds.Left + x, FSeismoHistory[x], BGRA(255, 0, 0, 255), 2) // Merah mati saat lockdown
    else
      TargetBMP.DrawLineAntialias(Bounds.Left + x - 1, FSeismoHistory[x - 1], Bounds.Left + x, FSeismoHistory[x], BGRA(180, 255, 0, 255), 2);
  end;

  TargetBMP.FillEllipseAntialias(Bounds.Right - 3, FSeismoHistory[High(FSeismoHistory)], 5, 5, BGRA(255, 50, 50, 255));
end;

// ==============================================================================
// RADAR RENDERING
// ==============================================================================
procedure TfrmMain.RenderRadar(TargetBMP: TBGRABitmap; Bounds: TRect);
var
  CenterX, CenterY, Radius: Integer;
  Tel: TTelemetryManager;
  TargetAz, TargetEl: Double;
  Px, Py: Integer;
  i, nx, ny: Integer;
begin
  Tel := FEngine.Telemetry;
  CenterX := Bounds.Left + (Bounds.Right - Bounds.Left) div 2;
  CenterY := Bounds.Top + (Bounds.Bottom - Bounds.Top) div 2;
  Radius := ((Bounds.Right - Bounds.Left) div 2) - 20;

  TargetBMP.FillRect(Bounds.Left, Bounds.Top, Bounds.Right, Bounds.Bottom, BGRA(0, 0, 0, 255), dmSet);

  if not FEngine.IsLockdown then
  begin
    for i := 1 to 2500 do
    begin
      nx := Bounds.Left + Random(Bounds.Right - Bounds.Left);
      ny := Bounds.Top + Random(Bounds.Bottom - Bounds.Top);
      TargetBMP.SetPixel(nx, ny, BGRA(Random(256), Random(256), Random(256), 50 + Random(100)));
    end;
  end;

  TargetBMP.EllipseAntialias(CenterX, CenterY, Radius, Radius, BGRA(0, 150, 0, 255), 2);
  TargetBMP.EllipseAntialias(CenterX, CenterY, Radius div 2, Radius div 2, BGRA(0, 150, 0, 255), 1);
  TargetBMP.DrawLineAntialias(Bounds.Left + 20, CenterY, Bounds.Right - 20, CenterY, BGRA(0, 150, 0, 255), 1);
  TargetBMP.DrawLineAntialias(CenterX, Bounds.Top + 20, CenterX, Bounds.Bottom - 20, BGRA(0, 150, 0, 255), 1);

  if not FEngine.IsLockdown then
  begin
    TargetAz := DegToRad(Tel.TargetPos.Azimuth - 90);
    TargetEl := 1.0 - (Tel.TargetPos.Elevation / 90.0);

    Px := CenterX + Round(Cos(TargetAz) * (Radius * TargetEl));
    Py := CenterY + Round(Sin(TargetAz) * (Radius * TargetEl));

    TargetBMP.EllipseAntialias(Px, Py, 5, 5, BGRA(255, 50, 50, 200), 2);

    if Tel.CurrentSNR > 10.0 then
      TargetBMP.FillEllipseAntialias(Px, Py, 5, 5, BGRA(0, 255, 0, Round(Tel.CurrentSNR * 2.5)));
  end;

  TargetAz := DegToRad(Tel.AntennaPos.Azimuth - 90);
  TargetEl := 1.0 - (Tel.AntennaPos.Elevation / 90.0);

  Px := CenterX + Round(Cos(TargetAz) * (Radius * TargetEl));
  Py := CenterY + Round(Sin(TargetAz) * (Radius * TargetEl));

  if FEngine.IsLockdown then
  begin
    TargetBMP.DrawLineAntialias(Px - 10, Py, Px + 10, Py, BGRA(255, 0, 0, 255), 2);
    TargetBMP.DrawLineAntialias(Px, Py - 10, Px, Py + 10, BGRA(255, 0, 0, 255), 2);
  end
  else
  begin
    TargetBMP.DrawLineAntialias(Px - 10, Py, Px + 10, Py, BGRA(0, 255, 255, 255), 2);
    TargetBMP.DrawLineAntialias(Px, Py - 10, Px, Py + 10, BGRA(0, 255, 255, 255), 2);
  end;
end;

end.
