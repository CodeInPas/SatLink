unit uDecryptForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, uDataModule;

type
  { TfrmDecrypt }
  TfrmDecrypt = class(TForm)
    btnDecrypt: TButton;
    edtDecodedKey: TEdit;
    lblHeader: TLabel;
    lblInstruction: TLabel;
    lblStatus: TLabel;
    memoHexStream: TMemo;
    pnlBackground: TPanel;

    pbTrace: TProgressBar;
    TraceTimer: TTimer;
    lblWarning: TLabel;

    procedure btnDecryptClick(Sender: TObject);
    procedure edtDecodedKeyKeyPress(Sender: TObject; var Key: char);
    procedure TraceTimerTimer(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  private
    FTargetID: Integer;
    FRawHex: string;
    FPeakSNR: Double;
    FAzimuth: Double;
    FElevation: Double;
    FFreqLocked: Double;

    FTraceProgress: Double;
    FTraceSpeed: Double;
  public
    procedure InitializeSignal(TargetID: Integer; const HexData: string;
      Az, El, Freq, SNR: Double);
  end;

var
  frmDecrypt: TfrmDecrypt;

implementation

{$R *.lfm}

{ TfrmDecrypt }

procedure TfrmDecrypt.InitializeSignal(TargetID: Integer; const HexData: string;
  Az, El, Freq, SNR: Double);
var
  ProxyLevel: Integer;
begin
  FTargetID := TargetID;
  FRawHex := HexData;
  FAzimuth := Az;
  FElevation := El;
  FFreqLocked := Freq;
  FPeakSNR := SNR;

  memoHexStream.Lines.Text := HexData;
  edtDecodedKey.Clear;
  lblStatus.Caption := 'AWAITING KEY INPUT...';
  lblStatus.Font.Color := clYellow;

  // SUNTIKKAN UPGRADE: Ambil level Proxy Router dari database
  ProxyLevel := GameDataModule.GetUpgradeLevel('UPG_PROXY');

  // Kalkulasi pengurangan kecepatan pelacakan
  // Kecepatan basis = 0.50% per 100ms (20 detik total)
  // Tiap level Proxy Router mengurangi kecepatan sebesar 0.08%
  FTraceSpeed := 0.5 - (ProxyLevel * 0.08);

  // Failsafe agar musuh tetap bisa melacak meski di level maksimal
  if FTraceSpeed < 0.1 then FTraceSpeed := 0.1;

  FTraceProgress := 0.0;
  pbTrace.Position := 0;

  lblWarning.Caption := 'WARNING: ENEMY TRACE DETECTED';
  lblWarning.Visible := True;

  ActiveControl := edtDecodedKey;
end;

procedure TfrmDecrypt.FormShow(Sender: TObject);
begin
  TraceTimer.Interval := 100;
  TraceTimer.Enabled := True;
end;

procedure TfrmDecrypt.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  TraceTimer.Enabled := False;
end;

procedure TfrmDecrypt.TraceTimerTimer(Sender: TObject);
begin
  FTraceProgress := FTraceProgress + FTraceSpeed;

  if FTraceProgress >= 100.0 then
  begin
    FTraceProgress := 100.0;
    TraceTimer.Enabled := False;
    pbTrace.Position := 100;

    lblWarning.Caption := 'TRACE COMPLETE. SYSTEM COMPROMISED!';
    lblWarning.Font.Color := clRed;

    ShowMessage('CRITICAL: Lokasi Anda terlacak oleh musuh! Memulai protokol Lockdown...');

    ModalResult := mrAbort;
  end
  else
  begin
    pbTrace.Position := Round(FTraceProgress);

    if (Round(FTraceProgress) mod 10) < 5 then
      lblWarning.Font.Color := clRed
    else
      lblWarning.Font.Color := clMaroon;
  end;
end;

procedure TfrmDecrypt.btnDecryptClick(Sender: TObject);
var
  ValidKey, EncType: string;
  LogData: TTransmissionLog;
begin
  if Trim(edtDecodedKey.Text) = '' then Exit;

  if GameDataModule.GetDecryptionKey(FRawHex, ValidKey, EncType) then
  begin
    if SameText(Trim(edtDecodedKey.Text), ValidKey) then
    begin
      TraceTimer.Enabled := False;

      lblStatus.Caption := 'DECRYPTION SUCCESSFUL!';
      lblStatus.Font.Color := clLime;

      LogData.TargetID := FTargetID;
      LogData.Azimuth := FAzimuth;
      LogData.Elevation := FElevation;
      LogData.FreqLocked := FFreqLocked;
      LogData.PeakSNR := FPeakSNR;
      LogData.RawHex := FRawHex;
      LogData.Payload := 'DECRYPTED VIA ' + EncType;
      LogData.IsDecrypted := 1;

      GameDataModule.AsyncLogTransmission(LogData);

      ShowMessage('Payload terdekripsi dan tersimpan di database intelijen.');
      ModalResult := mrOk;
    end
    else
    begin
      lblStatus.Caption := 'ERROR: INVALID KEY';
      lblStatus.Font.Color := clRed;
      edtDecodedKey.SelectAll;

      // Hukuman memasukkan sandi yang salah akan mendongkrak progress pelacakan 5%
      FTraceProgress := FTraceProgress + 5.0;
    end;
  end
  else
  begin
    lblStatus.Caption := 'ERROR: HEX SIGNATURE UNKNOWN';
    lblStatus.Font.Color := clRed;
  end;
end;

procedure TfrmDecrypt.edtDecodedKeyKeyPress(Sender: TObject; var Key: char);
begin
  if Key = #13 then
  begin
    Key := #0;
    btnDecrypt.Click;
  end;
end;

end.
