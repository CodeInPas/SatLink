unit uTelemetryManager;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, uVectorMath;

const
  MAX_MOTOR_TEMP = 100.0;
  COOLING_RATE = 5.0;      // Pendinginan motor dasar (derajat Celsius per detik)
  HEATING_RATE = 15.0;     // Pemanasan motor dasar saat bergerak (derajat Celsius per detik)
  BEAMWIDTH_DEFAULT = 4.0; // Lebar tangkapan sinyal parabola dasar (derajat)
  MAX_SNR_BASE = 100.0;    // Skala maksimum Signal-to-Noise Ratio (dB konseptual)
  FREQ_TOLERANCE = 0.25;   // Toleransi deviasi frekuensi radio dasar (MHz)

  ORBIT_AZ_SPEED = 0.05;
  ORBIT_EL_SPEED = 0.02;

type
  TTelemetryState = (tsIdle, tsTracking, tsLocked, tsOverheated);

  { TTelemetryManager }
  TTelemetryManager = class
  private
    FAntennaPos: TAntennaCoord;
    FTargetPos: TAntennaCoord;

    FBaseTargetPos: TAntennaCoord;
    FDriftTime: Double;

    FCurrentFreq: Double;
    FTargetFreq: Double;

    FMotorTemp: Double;
    FCurrentSNR: Double;
    FState: TTelemetryState;

    // DITAMBAHKAN: Variabel internal untuk menampung nilai stat yang sudah di-upgrade
    FBeamwidth: Double;
    FCoolingRate: Double;
    FHeatingRate: Double;
    FFreqTolerance: Double;

    procedure CalculateCombinedSNR;
  public
    constructor Create;

    procedure Update(const DeltaTime: Double);
    procedure MoveAntenna(const TargetAz, TargetEl: Double; const DeltaTime: Double);
    procedure SetFrequency(const Freq: Double);
    procedure AssignCelestialTarget(const Az, El, Freq: Double);

    // DITAMBAHKAN: Prosedur untuk menyuntikkan level upgrade dari Database ke Engine Fisika
    procedure ApplyUpgrades(BeamLevel, CoolLevel, FreqLevel: Integer);

    property AntennaPos: TAntennaCoord read FAntennaPos;
    property TargetPos: TAntennaCoord read FTargetPos;
    property CurrentFreq: Double read FCurrentFreq;
    property TargetFreq: Double read FTargetFreq;
    property MotorTemp: Double read FMotorTemp;
    property CurrentSNR: Double read FCurrentSNR;
    property State: TTelemetryState read FState;
  end;

implementation

{ TTelemetryManager }

constructor TTelemetryManager.Create;
begin
  FAntennaPos.Azimuth := 0.0;
  FAntennaPos.Elevation := 0.0;
  FTargetPos := FAntennaPos;
  FBaseTargetPos := FAntennaPos;
  FDriftTime := 0.0;

  FCurrentFreq := 100.0;
  FTargetFreq := 100.0;

  FMotorTemp := 25.0;
  FCurrentSNR := 0.0;
  FState := tsIdle;

  // Inisialisasi stat dasar sebelum ada upgrade
  FBeamwidth := BEAMWIDTH_DEFAULT;
  FCoolingRate := COOLING_RATE;
  FHeatingRate := HEATING_RATE;
  FFreqTolerance := FREQ_TOLERANCE;
end;

procedure TTelemetryManager.ApplyUpgrades(BeamLevel, CoolLevel, FreqLevel: Integer);
begin
  // 1. Wide-Band Dish: Tiap level menambah lebar tangkapan 1.5 derajat
  FBeamwidth := BEAMWIDTH_DEFAULT + (BeamLevel * 1.5);

  // 2. Cryogenic Motor: Tiap level menambah pendinginan 2.0 C/s dan mengurangi pemanasan 1.5 C/s
  FCoolingRate := COOLING_RATE + (CoolLevel * 2.0);
  FHeatingRate := HEATING_RATE - (CoolLevel * 1.5);
  if FHeatingRate < 5.0 then FHeatingRate := 5.0; // Failsafe agar motor tetap bisa panas sedikit

  // 3. Digital Auto-Tuner: Tiap level memperlebar toleransi frekuensi 0.15 MHz
  FFreqTolerance := FREQ_TOLERANCE + (FreqLevel * 0.15);
end;

procedure TTelemetryManager.Update(const DeltaTime: Double);
begin
  // MENGGUNAKAN VARIABEL UPGRADE: FCoolingRate
  if FMotorTemp > 25.0 then
  begin
    FMotorTemp := FMotorTemp - (FCoolingRate * DeltaTime);
    if FMotorTemp < 25.0 then FMotorTemp := 25.0;
  end;

  if FMotorTemp >= MAX_MOTOR_TEMP then
  begin
    FState := tsOverheated;
    FCurrentSNR := 0.0;
    Exit;
  end;

  FDriftTime := FDriftTime + DeltaTime;

  FTargetPos.Azimuth := WrapAzimuth(FBaseTargetPos.Azimuth + (Sin(FDriftTime * ORBIT_AZ_SPEED) * 5.0));
  FTargetPos.Elevation := ClampElevation(FBaseTargetPos.Elevation + (Cos(FDriftTime * ORBIT_EL_SPEED) * 3.0));

  CalculateCombinedSNR;

  if FCurrentSNR > 85.0 then
    FState := tsLocked
  else if FCurrentSNR > 10.0 then
    FState := tsTracking
  else
    FState := tsIdle;
end;

procedure TTelemetryManager.MoveAntenna(const TargetAz, TargetEl: Double; const DeltaTime: Double);
var
  DistAz, DistEl: Double;
begin
  if FState = tsOverheated then Exit;

  FAntennaPos.Azimuth := Lerp(FAntennaPos.Azimuth, WrapAzimuth(TargetAz), 2.0 * DeltaTime);
  FAntennaPos.Elevation := Lerp(FAntennaPos.Elevation, ClampElevation(TargetEl), 2.0 * DeltaTime);

  DistAz := abs(FAntennaPos.Azimuth - TargetAz);
  DistEl := abs(FAntennaPos.Elevation - TargetEl);

  // MENGGUNAKAN VARIABEL UPGRADE: FHeatingRate
  if (DistAz > 0.1) or (DistEl > 0.1) then
  begin
    FMotorTemp := FMotorTemp + (FHeatingRate * DeltaTime);
    FMotorTemp := Min(FMotorTemp, MAX_MOTOR_TEMP);
  end;
end;

procedure TTelemetryManager.SetFrequency(const Freq: Double);
begin
  FCurrentFreq := Freq;
end;

procedure TTelemetryManager.AssignCelestialTarget(const Az, El, Freq: Double);
begin
  FBaseTargetPos.Azimuth := WrapAzimuth(Az);
  FBaseTargetPos.Elevation := ClampElevation(El);
  FTargetPos := FBaseTargetPos;
  FDriftTime := 0.0;

  FTargetFreq := Freq;
end;

procedure TTelemetryManager.CalculateCombinedSNR;
var
  SpatialError, FreqError: Double;
  SpatialSNR, FreqMultiplier: Double;
begin
  SpatialError := CalcAngularError(FAntennaPos, FTargetPos);

  // MENGGUNAKAN VARIABEL UPGRADE: FBeamwidth
  SpatialSNR := CalculateSNR(SpatialError, MAX_SNR_BASE, FBeamwidth);

  FreqError := abs(FCurrentFreq - FTargetFreq);

  // MENGGUNAKAN VARIABEL UPGRADE: FFreqTolerance
  if FreqError > FFreqTolerance then
    FreqMultiplier := 0.0
  else
    FreqMultiplier := 1.0 - (FreqError / FFreqTolerance);

  FCurrentSNR := SpatialSNR * FreqMultiplier;
end;

end.
