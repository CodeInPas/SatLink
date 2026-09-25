unit uLogViewerForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Grids,
  uDataModule;

type
  { TfrmLogViewer }
  TfrmLogViewer = class(TForm)
    btnClose: TButton;
    lblTitle: TLabel;
    memoPayload: TMemo;
    sgLogs: TStringGrid;
    procedure btnCloseClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure sgLogsSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
  private
    FLogs: TIntelLogArray;
    procedure RefreshLogs;
    procedure UpdatePayloadView(aRow: Integer);
  public
  end;

var
  frmLogViewer: TfrmLogViewer;

implementation

{$R *.lfm}

{ TfrmLogViewer }

procedure TfrmLogViewer.FormShow(Sender: TObject);
begin
  // Mengatur lebar kolom agar tabel rapi
  sgLogs.ColWidths[0] := 60;  // LOG ID
  sgLogs.ColWidths[1] := 160; // TARGET
  sgLogs.ColWidths[2] := 130; // AZ / EL
  sgLogs.ColWidths[3] := 100; // FREQ
  sgLogs.ColWidths[4] := 90;  // PEAK SNR
  sgLogs.ColWidths[5] := 100; // STATUS

  RefreshLogs;
end;

procedure TfrmLogViewer.btnCloseClick(Sender: TObject);
begin
  self.close;
end;

procedure TfrmLogViewer.RefreshLogs;
var
  i: Integer;
  StatusText: string;
begin
  // Tarik riwayat operasi dari SQLite
  FLogs := GameDataModule.LoadIntelLogs;

  // Sesuaikan jumlah baris (+1 untuk header)
  sgLogs.RowCount := Length(FLogs) + 1;

  for i := 0 to High(FLogs) do
  begin
    sgLogs.Cells[0, i + 1] := Format('#%03d', [FLogs[i].LogID]);
    sgLogs.Cells[1, i + 1] := FLogs[i].TargetName;
    sgLogs.Cells[2, i + 1] := Format('%.1f° / %.1f°', [FLogs[i].Azimuth, FLogs[i].Elevation]);
    sgLogs.Cells[3, i + 1] := Format('%.2f MHz', [FLogs[i].Frequency]);
    sgLogs.Cells[4, i + 1] := Format('%.1f dB', [FLogs[i].PeakSNR]);

    if FLogs[i].IsDecrypted then
      StatusText := 'DECRYPTED'
    else
      StatusText := 'CORRUPTED';

    sgLogs.Cells[5, i + 1] := StatusText;
  end;

  // Jika ada data, tampilkan isi payload baris pertama
  if sgLogs.RowCount > 1 then
    UpdatePayloadView(sgLogs.Row)
  else
    memoPayload.Text := 'NO LOGS FOUND IN DATABASE.';
end;

procedure TfrmLogViewer.UpdatePayloadView(aRow: Integer);
var
  Idx: Integer;
begin
  if (aRow < 1) or (aRow > High(FLogs) + 1) then Exit;

  Idx := aRow - 1;

  if FLogs[Idx].IsDecrypted then
    memoPayload.Text := FLogs[Idx].DecryptedPayload
  else
    memoPayload.Text := '<ENCRYPTED DATA OR CORRUPTED SIGNAL>' + sLineBreak +
                        'KEY MISSING. DECRYPTION ABORTED.';
end;

procedure TfrmLogViewer.sgLogsSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
begin
  UpdatePayloadView(aRow);
end;

end.
