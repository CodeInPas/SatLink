unit uVectorMath;

{$mode ObjFPC}{$H+}

interface

uses
  Math;

type
  { TAntennaCoord }
  // Record ringan untuk merepresentasikan koordinat antena dan objek di langit.
  // Menggunakan tipe Double untuk mencegah floating-point inaccuracy (jitter).
  TAntennaCoord = record
    Azimuth: Double;   // Derajat rotasi horizontal (0..360)
    Elevation: Double; // Derajat sudut vertikal (0..90)
  end;

// Fungsi utilitas dasar
// Modifikasi 'inline' digunakan agar compiler menyisipkan assembly langsung
// tanpa overhead pemanggilan memori (sangat efisien untuk render loop 60 FPS).
function Lerp(const A, B, T: Double): Double; inline;
function WrapAzimuth(const Angle: Double): Double; inline;
function ClampElevation(const Angle: Double): Double; inline;

// Mengkalkulasi deviasi sudut asli (Angular Distance) antara antena pemain dan posisi target
function CalcAngularError(const Current, Target: TAntennaCoord): Double;

// Menghitung kekuatan sinyal (SNR) berdasarkan akurasi kuncian antena
function CalculateSNR(const AngularError, MaxSNR, Beamwidth: Double): Double;

implementation

function Lerp(const A, B, T: Double): Double; inline;
begin
  // Linear Interpolation: menghasilkan pergerakan/transisi yang halus.
  // Parameter T (waktu/faktor) dibatasi 0.0 hingga 1.0.
  Result := A + (B - A) * EnsureRange(T, 0.0, 1.0);
end;

function WrapAzimuth(const Angle: Double): Double; inline;
var
  Res: Double;
begin
  // Menjaga agar Azimuth berputar secara logis (misal: 365 derajat menjadi 5 derajat).
  Res := fmod(Angle, 360.0);
  if Res < 0 then
    Res := Res + 360.0;
  Result := Res;
end;

function ClampElevation(const Angle: Double): Double; inline;
begin
  // Fisik antena parabola stasiun bumi tidak bisa menunduk menembus tanah (<0)
  // atau melipat ke belakang (>90).
  Result := EnsureRange(Angle, 0.0, 90.0);
end;

function CalcAngularError(const Current, Target: TAntennaCoord): Double;
var
  Az1, El1, Az2, El2: Double;
  CosC: Double;
begin
  // Konversi dari derajat ke radian karena fungsi trigonometri FPC membutuhkan radian
  Az1 := DegToRad(Current.Azimuth);
  El1 := DegToRad(Current.Elevation);
  Az2 := DegToRad(Target.Azimuth);
  El2 := DegToRad(Target.Elevation);

  // Menggunakan Spherical Law of Cosines untuk mencari jarak terpendek (Great-Circle Distance)
  // di atas bidang bola langit tiga dimensi.
  CosC := Sin(El1) * Sin(El2) + Cos(El1) * Cos(El2) * Cos(Az1 - Az2);

  // Melindungi dari floating-point error mikro yang dapat menggeser nilai CosC keluar dari rentang -1..1,
  // yang mana akan membuat fungsi ArcCos memunculkan pesan error "EInvalidOp".
  CosC := EnsureRange(CosC, -1.0, 1.0);

  // Kembalikan error dalam derajat
  Result := RadToDeg(ArcCos(CosC));
end;

function CalculateSNR(const AngularError, MaxSNR, Beamwidth: Double): Double;
var
  SignalDrop: Double;
begin
  // Jika error (deviasi) lebih besar dari sebaran antena (Beamwidth),
  // sinyal hilang sepenuhnya di telan cosmic noise.
  if AngularError > Beamwidth then
    Exit(0.0);

  // Kurva Atenuasi Gaussian:
  // Sinyal paling jernih berada di pusat (error=0) dan menurun drastis secara kurva lengkung di pinggir.
  // Penggunaan Sqr() (pangkat dua) jauh lebih efisien di FPC daripada memanggil fungsi Power().
  SignalDrop := Exp(- (Sqr(AngularError) / Sqr(Beamwidth * 0.5)));

  Result := MaxSNR * SignalDrop;
end;

end.

