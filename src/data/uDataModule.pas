unit uDataModule;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, sqldb, sqlite3conn, Generics.Collections, SyncObjs;

type
  TTransmissionLog = record
    TargetID: Integer;
    Azimuth: Double;
    Elevation: Double;
    FreqLocked: Double;
    PeakSNR: Double;
    RawHex: string;
    Payload: string;
    IsDecrypted: Integer;
  end;

  TCelestialTargetDef = record
    ID: Integer;
    TargetName: string;
    Azimuth: Double;
    Elevation: Double;
    Frequency: Double;
    HexSignature: string;
  end;

  TTargetArray = array of TCelestialTargetDef;

  TPlayerUpgrade = record
    UpgradeID: string;
    Name: string;
    Description: string;
    CurrentLevel: Integer;
    MaxLevel: Integer;
    BaseCost: Integer;
    CostMultiplier: Double;
    NextLevelCost: Integer;
  end;

  TUpgradeArray = array of TPlayerUpgrade;

  TIntelLog = record
    LogID: Integer;
    TargetName: string;
    Azimuth: Double;
    Elevation: Double;
    Frequency: Double;
    PeakSNR: Double;
    DecryptedPayload: string;
    IsDecrypted: Boolean;
  end;

  TIntelLogArray = array of TIntelLog;

  TBaseQueue = specialize TQueue<TTransmissionLog>;

  { TLogQueue }
  TLogQueue = class
  private
    FQueue: TBaseQueue;
    FLock: TCriticalSection;
    FEvent: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure PushItem(const Item: TTransmissionLog);
    function PopItem(out Item: TTransmissionLog; TimeoutMS: Integer): TWaitResult;
  end;

  { TAsyncLoggerThread }
  TAsyncLoggerThread = class(TThread)
  private
    FQueue: TLogQueue;
    FDbPath: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AQueue: TLogQueue; const ADbPath: string);
  end;

  { TGameDataModule }
  TGameDataModule = class(TDataModule)
    SQLiteConn: TSQLite3Connection;
    SQLTrans: TSQLTransaction;
    qryLookup: TSQLQuery;
    qryTargets: TSQLQuery;
    qryWallet: TSQLQuery;
    qryUpgrades: TSQLQuery;
    qryLogs: TSQLQuery;
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
  private
    FLogQueue: TLogQueue;
    FLoggerThread: TAsyncLoggerThread;
    FDbPath: string;
  public
    procedure ConnectToDatabase;

    procedure AsyncLogTransmission(const LogData: TTransmissionLog);
    function GetDecryptionKey(const HexSignature: string; out DecodeKey, EncType: string): Boolean;
    function LoadCelestialTargets: TTargetArray;

    function GetIntelCredits: Integer;
    procedure AddIntelCredits(const Amount: Integer);
    function LoadUpgrades: TUpgradeArray;
    function PurchaseUpgrade(const UpgradeID: string): Boolean;

    // DITAMBAHKAN: Fungsi helper untuk mengambil level spesifik dari sebuah upgrade
    function GetUpgradeLevel(const UpgradeID: string): Integer;

    function LoadIntelLogs: TIntelLogArray;
  end;

var
  GameDataModule: TGameDataModule;

implementation

{$R *.lfm}

{ TLogQueue }

constructor TLogQueue.Create;
begin
  FQueue := TBaseQueue.Create;
  FLock := TCriticalSection.Create;
  FEvent := TEvent.Create(nil, False, False, '');
end;

destructor TLogQueue.Destroy;
begin
  FEvent.Free;
  FLock.Free;
  FQueue.Free;
  inherited Destroy;
end;

procedure TLogQueue.PushItem(const Item: TTransmissionLog);
begin
  FLock.Acquire;
  try
    FQueue.Enqueue(Item);
  finally
    FLock.Release;
  end;
  FEvent.SetEvent;
end;

function TLogQueue.PopItem(out Item: TTransmissionLog; TimeoutMS: Integer): TWaitResult;
begin
  Result := FEvent.WaitFor(TimeoutMS);

  if Result = wrSignaled then
  begin
    FLock.Acquire;
    try
      if FQueue.Count > 0 then
        Item := FQueue.Dequeue
      else
        Result := wrTimeout;

      if FQueue.Count > 0 then
        FEvent.SetEvent;
    finally
      FLock.Release;
    end;
  end;
end;

{ TAsyncLoggerThread }

constructor TAsyncLoggerThread.Create(AQueue: TLogQueue; const ADbPath: string);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FQueue := AQueue;
  FDbPath := ADbPath;
end;

procedure TAsyncLoggerThread.Execute;
var
  LogItem: TTransmissionLog;
  ThreadConn: TSQLite3Connection;
  ThreadTrans: TSQLTransaction;
  ThreadQuery: TSQLQuery;
begin
  ThreadConn := TSQLite3Connection.Create(nil);
  ThreadTrans := TSQLTransaction.Create(nil);
  ThreadQuery := TSQLQuery.Create(nil);
  try
    ThreadConn.DatabaseName := FDbPath;
    ThreadConn.Transaction := ThreadTrans;
    ThreadQuery.DataBase := ThreadConn;
    ThreadQuery.Transaction := ThreadTrans;

    while not Terminated do
    begin
      if FQueue.PopItem(LogItem, 100) = wrSignaled then
      begin
        try
          if not ThreadConn.Connected then ThreadConn.Open;

          ThreadQuery.SQL.Text :=
            'INSERT INTO transmission_logs (target_id, azimuth, elevation, frequency_locked, peak_snr, raw_hex, decrypted_payload, is_decrypted) ' +
            'VALUES (:tid, :az, :el, :fq, :snr, :hex, :payload, :isdec)';

          ThreadQuery.Params.ParamByName('tid').AsInteger := LogItem.TargetID;
          ThreadQuery.Params.ParamByName('az').AsFloat := LogItem.Azimuth;
          ThreadQuery.Params.ParamByName('el').AsFloat := LogItem.Elevation;
          ThreadQuery.Params.ParamByName('fq').AsFloat := LogItem.FreqLocked;
          ThreadQuery.Params.ParamByName('snr').AsFloat := LogItem.PeakSNR;
          ThreadQuery.Params.ParamByName('hex').AsString := LogItem.RawHex;
          ThreadQuery.Params.ParamByName('payload').AsString := LogItem.Payload;
          ThreadQuery.Params.ParamByName('isdec').AsInteger := LogItem.IsDecrypted;

          ThreadQuery.ExecSQL;
          ThreadTrans.Commit;
        except
          if ThreadTrans.Active then ThreadTrans.Rollback;
        end;
      end;
    end;
  finally
    ThreadQuery.Free;
    ThreadTrans.Free;
    ThreadConn.Free;
  end;
end;

{ TGameDataModule }

procedure TGameDataModule.DataModuleCreate(Sender: TObject);
begin
  FDbPath := ExtractFilePath(ParamStr(0)) + 'assets' + DirectorySeparator + 'db' + DirectorySeparator + 'satlink_core.db';

  FLogQueue := TLogQueue.Create;
  FLoggerThread := TAsyncLoggerThread.Create(FLogQueue, FDbPath);
end;

procedure TGameDataModule.DataModuleDestroy(Sender: TObject);
begin
  if Assigned(FLoggerThread) then
  begin
    FLoggerThread.Terminate;
    FLoggerThread.WaitFor;
    FLoggerThread.Free;
  end;

  if Assigned(FLogQueue) then
    FLogQueue.Free;
end;

procedure TGameDataModule.ConnectToDatabase;
begin
  SQLiteConn.DatabaseName := FDbPath;
  SQLiteConn.Connected := True;
end;

procedure TGameDataModule.AsyncLogTransmission(const LogData: TTransmissionLog);
begin
  FLogQueue.PushItem(LogData);
end;

function TGameDataModule.GetDecryptionKey(const HexSignature: string; out DecodeKey, EncType: string): Boolean;
begin
  Result := False;
  if not SQLiteConn.Connected then ConnectToDatabase;

  qryLookup.Close;
  qryLookup.SQL.Text := 'SELECT decode_key, encryption_type FROM hex_dictionary WHERE hex_signature = :hex LIMIT 1';
  qryLookup.Params.ParamByName('hex').AsString := HexSignature;
  qryLookup.Open;

  if not qryLookup.EOF then
  begin
    DecodeKey := qryLookup.FieldByName('decode_key').AsString;
    EncType := qryLookup.FieldByName('encryption_type').AsString;
    Result := True;
  end;

  qryLookup.Close;
end;

function TGameDataModule.LoadCelestialTargets: TTargetArray;
var
  Idx: Integer;
begin
  SetLength(Result, 0);
  if not SQLiteConn.Connected then ConnectToDatabase;

  qryTargets.Close;
  qryTargets.SQL.Text := 'SELECT * FROM celestial_targets';
  qryTargets.Open;

  Idx := 0;
  while not qryTargets.EOF do
  begin
    SetLength(Result, Idx + 1);

    if qryTargets.FieldDefs.IndexOf('id') >= 0 then
      Result[Idx].ID := qryTargets.FieldByName('id').AsInteger;

    if qryTargets.FieldDefs.IndexOf('name') >= 0 then
      Result[Idx].TargetName := qryTargets.FieldByName('name').AsString
    else if qryTargets.FieldDefs.IndexOf('target_name') >= 0 then
      Result[Idx].TargetName := qryTargets.FieldByName('target_name').AsString;

    if qryTargets.FieldDefs.IndexOf('azimuth') >= 0 then
      Result[Idx].Azimuth := qryTargets.FieldByName('azimuth').AsFloat;

    if qryTargets.FieldDefs.IndexOf('elevation') >= 0 then
      Result[Idx].Elevation := qryTargets.FieldByName('elevation').AsFloat;

    if qryTargets.FieldDefs.IndexOf('frequency') >= 0 then
      Result[Idx].Frequency := qryTargets.FieldByName('frequency').AsFloat;

    if qryTargets.FieldDefs.IndexOf('hex_signature') >= 0 then
      Result[Idx].HexSignature := qryTargets.FieldByName('hex_signature').AsString;

    Inc(Idx);
    qryTargets.Next;
  end;
  qryTargets.Close;
end;

function TGameDataModule.GetIntelCredits: Integer;
begin
  Result := 0;
  if not SQLiteConn.Connected then ConnectToDatabase;

  qryWallet.Close;
  qryWallet.SQL.Text := 'SELECT intel_credits FROM player_wallet WHERE id = 1';
  qryWallet.Open;

  if not qryWallet.EOF then
    Result := qryWallet.FieldByName('intel_credits').AsInteger;

  qryWallet.Close;
end;

procedure TGameDataModule.AddIntelCredits(const Amount: Integer);
begin
  if not SQLiteConn.Connected then ConnectToDatabase;

  qryWallet.Close;
  qryWallet.SQL.Text := 'UPDATE player_wallet SET intel_credits = intel_credits + :amt WHERE id = 1';
  qryWallet.Params.ParamByName('amt').AsInteger := Amount;
  qryWallet.ExecSQL;
  SQLTrans.Commit;
end;

function TGameDataModule.LoadUpgrades: TUpgradeArray;
var
  Idx: Integer;
begin
  SetLength(Result, 0);
  if not SQLiteConn.Connected then ConnectToDatabase;

  qryUpgrades.Close;
  qryUpgrades.SQL.Text := 'SELECT * FROM player_upgrades';
  qryUpgrades.Open;

  Idx := 0;
  while not qryUpgrades.EOF do
  begin
    SetLength(Result, Idx + 1);
    Result[Idx].UpgradeID := qryUpgrades.FieldByName('id').AsString;
    Result[Idx].Name := qryUpgrades.FieldByName('name').AsString;
    Result[Idx].Description := qryUpgrades.FieldByName('description').AsString;
    Result[Idx].CurrentLevel := qryUpgrades.FieldByName('current_level').AsInteger;
    Result[Idx].MaxLevel := qryUpgrades.FieldByName('max_level').AsInteger;
    Result[Idx].BaseCost := qryUpgrades.FieldByName('base_cost').AsInteger;
    Result[Idx].CostMultiplier := qryUpgrades.FieldByName('cost_multiplier').AsFloat;

    Result[Idx].NextLevelCost := Trunc(Result[Idx].BaseCost * Power(Result[Idx].CostMultiplier, Result[Idx].CurrentLevel));

    Inc(Idx);
    qryUpgrades.Next;
  end;
  qryUpgrades.Close;
end;

// DITAMBAHKAN: Implementasi pengambilan level instan
function TGameDataModule.GetUpgradeLevel(const UpgradeID: string): Integer;
begin
  Result := 0;
  if not SQLiteConn.Connected then ConnectToDatabase;

  qryUpgrades.Close;
  qryUpgrades.SQL.Text := 'SELECT current_level FROM player_upgrades WHERE id = :id';
  qryUpgrades.Params.ParamByName('id').AsString := UpgradeID;
  qryUpgrades.Open;

  if not qryUpgrades.EOF then
    Result := qryUpgrades.FieldByName('current_level').AsInteger;

  qryUpgrades.Close;
end;

function TGameDataModule.PurchaseUpgrade(const UpgradeID: string): Boolean;
var
  CurrentCredits, CurrentLevel, MaxLevel, Cost: Integer;
begin
  Result := False;
  if not SQLiteConn.Connected then ConnectToDatabase;

  qryUpgrades.Close;
  qryUpgrades.SQL.Text := 'SELECT current_level, max_level, base_cost, cost_multiplier FROM player_upgrades WHERE id = :id';
  qryUpgrades.Params.ParamByName('id').AsString := UpgradeID;
  qryUpgrades.Open;

  if qryUpgrades.EOF then
  begin
    qryUpgrades.Close;
    Exit;
  end;

  CurrentLevel := qryUpgrades.FieldByName('current_level').AsInteger;
  MaxLevel := qryUpgrades.FieldByName('max_level').AsInteger;
  Cost := Trunc(qryUpgrades.FieldByName('base_cost').AsInteger * Power(qryUpgrades.FieldByName('cost_multiplier').AsFloat, CurrentLevel));
  qryUpgrades.Close;

  if CurrentLevel >= MaxLevel then Exit;

  CurrentCredits := GetIntelCredits;
  if CurrentCredits >= Cost then
  begin
    qryWallet.Close;
    qryWallet.SQL.Text := 'UPDATE player_wallet SET intel_credits = intel_credits - :cost WHERE id = 1';
    qryWallet.Params.ParamByName('cost').AsInteger := Cost;
    qryWallet.ExecSQL;

    qryUpgrades.Close;
    qryUpgrades.SQL.Text := 'UPDATE player_upgrades SET current_level = current_level + 1 WHERE id = :id';
    qryUpgrades.Params.ParamByName('id').AsString := UpgradeID;
    qryUpgrades.ExecSQL;

    SQLTrans.Commit;
    Result := True;
  end;
end;

function TGameDataModule.LoadIntelLogs: TIntelLogArray;
var
  Idx: Integer;
begin
  SetLength(Result, 0);
  if not SQLiteConn.Connected then ConnectToDatabase;

  qryLogs.Close;
  qryLogs.SQL.Text :=
    'SELECT l.id, t.object_name as object_name, l.azimuth, l.elevation, ' +
    'l.frequency_locked, l.peak_snr, l.decrypted_payload, l.is_decrypted ' +
    'FROM transmission_logs l ' +
    'LEFT JOIN celestial_targets t ON l.target_id = t.id ' +
    'ORDER BY l.id DESC';
  qryLogs.Open;

  Idx := 0;
  while not qryLogs.EOF do
  begin
    SetLength(Result, Idx + 1);
    Result[Idx].LogID := qryLogs.FieldByName('id').AsInteger;

    // DIPERBAIKI: Menggunakan field 'object_name' sesuai alias pada sintaks SQL JOIN di atas
    if qryLogs.FieldByName('object_name').IsNull then
      Result[Idx].TargetName := 'UNKNOWN'
    else
      Result[Idx].TargetName := qryLogs.FieldByName('object_name').AsString;

    Result[Idx].Azimuth := qryLogs.FieldByName('azimuth').AsFloat;
    Result[Idx].Elevation := qryLogs.FieldByName('elevation').AsFloat;
    Result[Idx].Frequency := qryLogs.FieldByName('frequency_locked').AsFloat;
    Result[Idx].PeakSNR := qryLogs.FieldByName('peak_snr').AsFloat;
    Result[Idx].DecryptedPayload := qryLogs.FieldByName('decrypted_payload').AsString;
    Result[Idx].IsDecrypted := qryLogs.FieldByName('is_decrypted').AsInteger > 0;

    Inc(Idx);
    qryLogs.Next;
  end;
  qryLogs.Close;
end;

end.
