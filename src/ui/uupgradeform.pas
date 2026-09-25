unit uUpgradeForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Grids,
  uDataModule, uGameEngine;

type
  { TfrmUpgrade }
  TfrmUpgrade = class(TForm)
    btnBuy: TButton;
    btnClose: TButton;
    lblTitle: TLabel;
    lblWallet: TLabel;
    memoDesc: TMemo;
    sgUpgrades: TStringGrid;
    procedure btnBuyClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure sgUpgradesSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
  private
    FUpgrades: TUpgradeArray;
    procedure RefreshData;
    procedure UpdateSelection(aRow: Integer);
  public
  end;

var
  frmUpgrade: TfrmUpgrade;

implementation

{$R *.lfm}

{ TfrmUpgrade }

procedure TfrmUpgrade.FormShow(Sender: TObject);
begin
  // Atur lebar kolom grid. Kolom ID (0) disembunyikan.
  sgUpgrades.ColWidths[0] := 0;
  sgUpgrades.ColWidths[1] := 250; // Nama Modul
  sgUpgrades.ColWidths[2] := 100; // Level Terkini
  sgUpgrades.ColWidths[3] := 120; // Biaya Upgrade

  RefreshData;
end;

procedure TfrmUpgrade.RefreshData;
var
  i: Integer;
begin
  // Segarkan teks saldo pemain
  lblWallet.Caption := Format('CREDITS: %d', [GameDataModule.GetIntelCredits]);

  // Muat data dari SQLite
  FUpgrades := GameDataModule.LoadUpgrades;
  sgUpgrades.RowCount := Length(FUpgrades) + 1; // +1 untuk header

  for i := 0 to High(FUpgrades) do
  begin
    sgUpgrades.Cells[0, i + 1] := FUpgrades[i].UpgradeID;
    sgUpgrades.Cells[1, i + 1] := FUpgrades[i].Name;

    if FUpgrades[i].CurrentLevel >= FUpgrades[i].MaxLevel then
    begin
      sgUpgrades.Cells[2, i + 1] := 'MAX';
      sgUpgrades.Cells[3, i + 1] := '---';
    end
    else
    begin
      sgUpgrades.Cells[2, i + 1] := Format('Lvl %d/%d', [FUpgrades[i].CurrentLevel, FUpgrades[i].MaxLevel]);
      sgUpgrades.Cells[3, i + 1] := IntToStr(FUpgrades[i].NextLevelCost) + ' CR';
    end;
  end;

  if sgUpgrades.RowCount > 1 then
    UpdateSelection(sgUpgrades.Row);
end;

procedure TfrmUpgrade.UpdateSelection(aRow: Integer);
var
  Idx: Integer;
begin
  if (aRow < 1) or (aRow > High(FUpgrades) + 1) then Exit;

  Idx := aRow - 1;
  memoDesc.Text := FUpgrades[Idx].Description;

  // Cek validasi logika tombol beli
  if FUpgrades[Idx].CurrentLevel >= FUpgrades[Idx].MaxLevel then
  begin
    btnBuy.Enabled := False;
    btnBuy.Caption := 'MAX LEVEL REACHED';
  end
  else if GameDataModule.GetIntelCredits < FUpgrades[Idx].NextLevelCost then
  begin
    btnBuy.Enabled := False;
    btnBuy.Caption := 'INSUFFICIENT FUNDS';
  end
  else
  begin
    btnBuy.Enabled := True;
    btnBuy.Caption := 'PURCHASE UPGRADE';
  end;
end;

procedure TfrmUpgrade.sgUpgradesSelectCell(Sender: TObject; aCol, aRow: Integer; var CanSelect: Boolean);
begin
  UpdateSelection(aRow);
end;

procedure TfrmUpgrade.btnBuyClick(Sender: TObject);
var
  SelID: string;
  Idx: Integer;
begin
  if sgUpgrades.Row < 1 then Exit;
  Idx := sgUpgrades.Row - 1;
  SelID := FUpgrades[Idx].UpgradeID;

  // Coba proses transaksi
  if GameDataModule.PurchaseUpgrade(SelID) then
  begin
    ShowMessage('Module successfully upgraded!');

    // SUNTIKKAN LANGSUNG KE ENGINE: Update parameter fisika secara real-time
    if GlobalEngine <> nil then
      GlobalEngine.ReloadUpgrades;

    // Segarkan antarmuka agar biaya eksponensial level berikutnya terkalkulasi
    RefreshData;
  end
  else
  begin
    ShowMessage('Transaction failed. Ensure the database is not locked.');
  end;
end;

procedure TfrmUpgrade.btnCloseClick(Sender: TObject);
begin
  Self.Close;
end;

end.
