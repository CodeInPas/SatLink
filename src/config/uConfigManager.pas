unit uConfigManager;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, Forms;

type
  { TConfigManager }
  // Menggunakan arsitektur Singleton Pattern agar status konfigurasi (Audio, FPS, State)
  // dapat diakses secara instan dari unit manapun tanpa harus mem-passing object berulang kali.
  TConfigManager = class
  private
    FIniFilePath: string;
    FMasterVolume: Integer;
    FTargetFPS: Integer;
    FIsFullscreen: Boolean;
    FLastAzimuth: Double;
    FLastElevation: Double;

    procedure SetMasterVolume(AValue: Integer);
    procedure SetTargetFPS(AValue: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadConfig;
    procedure SaveConfig;

    // Properti Konfigurasi dengan enkapsulasi (Setters untuk validasi limit)
    property MasterVolume: Integer read FMasterVolume write SetMasterVolume;
    property TargetFPS: Integer read FTargetFPS write SetTargetFPS;
    property IsFullscreen: Boolean read FIsFullscreen write FIsFullscreen;
    property LastAzimuth: Double read FLastAzimuth write FLastAzimuth;
    property LastElevation: Double read FLastElevation write FLastElevation;
  end;

// Akses Global ke Singleton
function Config: TConfigManager;

implementation

var
  GlobalConfigManager: TConfigManager = nil;

// Fungsi global untuk menjamin hanya ada satu instance ConfigManager (Lazy Initialization)
function Config: TConfigManager;
begin
  if GlobalConfigManager = nil then
    GlobalConfigManager := TConfigManager.Create;
  Result := GlobalConfigManager;
end;

{ TConfigManager }

constructor TConfigManager.Create;
begin
  // Meletakkan file settings.ini di root folder aplikasi
  FIniFilePath := ExtractFilePath(Application.ExeName) + 'settings.ini';
  LoadConfig;
end;

destructor TConfigManager.Destroy;
begin
  SaveConfig; // Auto-save saat aplikasi ditutup (garbage collection)
  inherited Destroy;
end;

procedure TConfigManager.LoadConfig;
var
  Ini: TMemIniFile; // TMemIniFile jauh lebih efisien dari TIniFile karena memuat semuanya ke RAM
begin
  Ini := TMemIniFile.Create(FIniFilePath);
  try
    // Hardware & Audio Settings (Fallback ke default jika key tidak ditemukan)
    FMasterVolume := Ini.ReadInteger('Audio', 'MasterVolume', 80);
    FTargetFPS := Ini.ReadInteger('Graphics', 'TargetFPS', 60);
    FIsFullscreen := Ini.ReadBool('Graphics', 'Fullscreen', False);

    // State Antena Terakhir (Agar pemain melanjutkan dari posisi shift sebelumnya)
    FLastAzimuth := Ini.ReadFloat('State', 'LastAzimuth', 0.0);
    FLastElevation := Ini.ReadFloat('State', 'LastElevation', 0.0);
  finally
    Ini.Free;
  end;
end;

procedure TConfigManager.SaveConfig;
var
  Ini: TMemIniFile;
begin
  Ini := TMemIniFile.Create(FIniFilePath);
  try
    Ini.WriteInteger('Audio', 'MasterVolume', FMasterVolume);
    Ini.WriteInteger('Graphics', 'TargetFPS', FTargetFPS);
    Ini.WriteBool('Graphics', 'Fullscreen', FIsFullscreen);

    Ini.WriteFloat('State', 'LastAzimuth', FLastAzimuth);
    Ini.WriteFloat('State', 'LastElevation', FLastElevation);

    // Wajib dipanggil pada TMemIniFile untuk memindahkan buffer RAM (Cache) ke Disk (File fisik)
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

procedure TConfigManager.SetMasterVolume(AValue: Integer);
begin
  if FMasterVolume = AValue then Exit;

  // Hard limit untuk audio DSP (0% - 100%)
  if AValue < 0 then FMasterVolume := 0
  else if AValue > 100 then FMasterVolume := 100
  else FMasterVolume := AValue;
end;

procedure TConfigManager.SetTargetFPS(AValue: Integer);
begin
  if FTargetFPS = AValue then Exit;

  // Mengamankan performa engine agar tidak membekukan CPU
  if AValue < 30 then FTargetFPS := 30
  else if AValue > 144 then FTargetFPS := 144
  else FTargetFPS := AValue;
end;

finalization
  // Membersihkan memory secara otomatis saat aplikasi di-terminate
  if GlobalConfigManager <> nil then
    FreeAndNil(GlobalConfigManager);

end.

