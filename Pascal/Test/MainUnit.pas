// Pure Parse Float Test Unit
unit MainUnit;

{$IFDEF FPC}
  {$MODE DELPHIUNICODE}
  {$WARN 5036 off}
  {$WARN 4104 off}
  {$WARN 6018 off}
{$ENDIF}

{$ASSERTIONS ON}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  Math, StrUtils, SysUtils, Classes, PureParseFloat, Windows;

procedure RunTests();

implementation

const
  DigitCount = 31;
  SizeLarge =  10000000;
  SizeMedium = 1000000;
  SizeSmall =  100000;

var
  TestCount: Integer = SizeMedium;
  Mode: (ModePure, ModeDelphi, ModeMicrosoft) = ModePure;
  TestCVersion: Boolean = False;

function IeeeCharsToDouble(Str: PAnsiChar; PtrEnd: PPAnsiChar): Double; cdecl;
  {$IFDEF CPUX64}
  external 'IeeeConvert64.dll' name 'IeeeCharsToDouble'
  {$ELSE}
  external 'IeeeConvert32.dll' name 'IeeeCharsToDouble'
  {$ENDIF};

function IeeeDoubleToChars(Buf32: PAnsiChar; Value: Double): PAnsiChar; cdecl;
  {$IFDEF CPUX64}
  external 'IeeeConvert64.dll' name 'IeeeDoubleToChars'
  {$ELSE}
  external 'IeeeConvert32.dll' name 'IeeeDoubleToChars'
  {$ENDIF};

function MsvcrtStrtod(Str: PAnsiChar; PtrEnd: PPAnsiChar): Double; cdecl; external 'MSVCRT.DLL' name 'strtod';
function MsvcrtWcstod(Str: PWideChar; PtrEnd: PPWideChar): Double; cdecl; external 'MSVCRT.DLL' name 'wcstod';
// function UcrtbaseStrtod(Str: PAnsiChar; PtrEnd: PPAnsiChar): Double; cdecl; external 'UCRTBASE.DLL' name 'strtod';

// c version here:
var
  pure_parse_float_library: HMODULE;
  pure_parse_float: function(Str: PAnsiChar; Double: PDouble; PtrEnd: PPAnsiChar): Double; cdecl;
  dll_pure_parse_float_library: HMODULE;
  dll_pure_parse_float: function(Str: PAnsiChar; Double: PDouble; PtrEnd: PPAnsiChar): Double; cdecl;

// from ieee_convert32.dll/ieee_convert64.dll
function IeeeStringToDouble(Str: UnicodeString; out Value: Double): Integer;
var
  AnsiStr: AnsiString;
  PEnd: PAnsiChar;
begin
  AnsiStr := AnsiString(Str);// unicode -> ansi

  Value := IeeeCharsToDouble(PAnsiChar(AnsiStr), @PEnd);// convert

  Result := PEnd - PAnsiChar(AnsiStr);// calc length
end;

// from ieee_convert32.dll/ieee_convert64.dll
function IeeeDoubleToString(Value: Double): UnicodeString;
var
  Buf32: array [0..31] of AnsiChar;
begin
  IeeeDoubleToChars(Buf32, Value);

  Result := UnicodeString(Buf32);// ansi -> unicode
end;

// from PureParseFloat.pas
function PureStringToDouble(Str: UnicodeString; out Value: Double): Integer;
var
  PEnd: PWideChar;
begin
  Value := 0.0;

  ParseFloat(PWideChar(Str), Value, PEnd);

  Result := PEnd - PWideChar(Str);
end;

// from pure_parse_float.dll
function PureStringToDoubleC(Str: UnicodeString; out Value: Double): Integer;
var
  AnsiStr: AnsiString;
  PEnd: PAnsiChar;
begin
  Value := 0.0;
  AnsiStr := AnsiString(Str);// unicode -> ansi

  pure_parse_float(PAnsiChar(AnsiStr), @Value, @PEnd);

  Result := PEnd - PAnsiChar(AnsiStr);
end;

// from user dll
function PureStringToDoubleUserDll(Str: UnicodeString; out Value: Double): Integer;
var
  AnsiStr: AnsiString;
  PEnd: PAnsiChar;
begin
  Value := 0.0;
  AnsiStr := AnsiString(Str);// unicode -> ansi

  dll_pure_parse_float(PAnsiChar(AnsiStr), @Value, @PEnd);

  Result := PEnd - PAnsiChar(AnsiStr);
end;

// form MSVCRT.dll
function MsvcrtStringToDouble(Str: UnicodeString; out Value: Double): Integer;
var
  AnsiStr: AnsiString;
  PEnd: PAnsiChar;
begin
  AnsiStr := AnsiString(Str);// unicode -> ansi

  Value := MsvcrtStrtod(PAnsiChar(AnsiStr), @PEnd);

  Result := PEnd - PAnsiChar(AnsiStr);// calc length
end;

// form UCRTBASE.dll
(*function UcrtbaseStringToDouble(Str: UnicodeString; out Value: Double): Integer;
var
  AnsiStr: AnsiString;
  PEnd: PAnsiChar;
begin
  AnsiStr := AnsiString(Str);// unicode -> ansi

  Value := UcrtbaseStrtod(PAnsiChar(AnsiStr), @PEnd);

  Result := PEnd - PAnsiChar(AnsiStr);// calc length
end;*)

// random

var
  TestRandSeed: UInt32;

procedure SetTestSeed(const Seed: Integer);
begin
  TestRandSeed := Seed;
end;

{$R-} {$Q-}
function TestRandom(const Max: Integer): Integer;
begin
  Result := Int32(TestRandSeed) * $08088405 + 1;
  TestRandSeed := Result;

  Result := (UInt64(UInt32(Max)) * UInt64(UInt32(Result))) shr 32;
  Assert(Result >= 0);
end;
{$R+} {$Q+}

procedure AssertEqual(S: UnicodeString; WarnPrint: Boolean = False);
var
  A, B: Double;
  ABin: UInt64 absolute A;
  BBin: UInt64 absolute B;
  CountA, CountB: Integer;
begin
  CountA := IeeeStringToDouble(S, A);

  if @dll_pure_parse_float <> nil then
  begin
    CountB := PureStringToDoubleUserDll(S, B);
    if WarnPrint then
    begin
      if CountA <> CountB then
      begin
        Writeln('  Fail Length!');
        Writeln('    String: "', S, '"');
        Writeln('    Expected: ', CountA, ', Actual: ', CountB);
      end;
    end;
    Assert(CountA = CountB);
    if WarnPrint then
    begin
      if ABin <> BBin then
      begin
        Writeln('  Fail Bin!');
        Writeln('    String: "', S, '"');
        Writeln('    Expected: 0x', IntToHex(ABin, 8), ', Actual: 0x', IntToHex(BBin, 8));
      end;
    end;
    Assert(ABin = BBin);
    exit;
  end;

  case Mode of
  ModePure:
    begin
      if not TestCVersion then
        CountB := PureStringToDouble(S, B)// pascal
      else
        CountB := PureStringToDoubleC(S, B);// c
      Assert(CountA = CountB);
    end;
  ModeDelphi:
    begin
      {$IFNDEF FPC}
      SysUtils.TextToFloat(PWideChar(S), B);
      {$ELSE}
      SysUtils.TextToFloat(PAnsiChar(AnsiString(S)), B);
      {$ENDIF}
      if IsNan(A) and IsNan(B) then
        exit;
    end;
  else
    begin
      CountB := MsvcrtStringToDouble(S, B);
      if IsNan(A) and IsNan(B) then
        exit;
      Assert(CountA = CountB);
    end;
  end;

  // check equal numbers
  Assert(ABin = BBin);
end;

procedure AssertEqualWarn(S: UnicodeString);
begin
  AssertEqual(S, True);
end;

type
  TUlpDiffType = (udtSame, udtOne, udtMoreThanOne);
{$R-} {$Q-}
// True - 0 or 1, False - more than 1
function UlpDiff(S: UnicodeString): TUlpDiffType;
var
  A, B: Double;
  ABin: Int64 absolute A;
  BBin: Int64 absolute B;
begin
  IeeeStringToDouble(S, A);

  if @dll_pure_parse_float <> nil then
  begin
    PureStringToDoubleUserDll(S, B);
    if ABin = BBin then
    begin
      exit(udtSame);
    end;
    if (ABin - 1 = BBin) or (ABin + 1 = BBin) then
    begin
      exit(udtOne);
    end;
    exit(udtMoreThanOne);
  end;

  case Mode of
  ModePure:
    begin
      if not TestCVersion then
        PureStringToDouble(S, B)// pascal
      else
        PureStringToDoubleC(S, B);// c
    end;
  ModeDelphi:
    begin
      {$IFNDEF FPC}
      SysUtils.TextToFloat(PWideChar(S), B);
      {$ELSE}
      SysUtils.TextToFloat(PAnsiChar(AnsiString(S)), B);
      {$ENDIF}
    end;
  else
    begin
      MsvcrtStringToDouble(S, B);
    end;
  end;

  if ABin = BBin then
  begin
    exit(udtSame);
  end;

  if (ABin - 1 = BBin) or (ABin + 1 = BBin) then
  begin
    exit(udtOne);
  end;

  exit(udtMoreThanOne);
end;
{$R+} {$Q+}

type
  TTest = record
    Name: UnicodeString;
    Proc: TProcedure;
  end;

function MakeTest(Name: UnicodeString; Proc: TProcedure): TTest;
begin
  Result.Name := Name;
  Result.Proc := Proc;
end;

procedure SimpleIntegerTest();
begin
  AssertEqualWarn('0');
  AssertEqualWarn('666999');
  AssertEqualWarn('+12345');
  AssertEqualWarn('100000000000000001');
  AssertEqualWarn('-329');
  AssertEqualWarn('00000000000004');
  AssertEqualWarn('-00000000000009');
  AssertEqualWarn('+00000000000009');
end;

procedure SimpleFloatTest();
begin
  AssertEqualWarn('0.0');
  AssertEqualWarn('10.2');
  AssertEqualWarn('-1.2');
  AssertEqualWarn('0.2');
end;

procedure SimpleExponentTest();
begin
  AssertEqualWarn('0.0e0');
  AssertEqualWarn('10.2e10');
  AssertEqualWarn('-1.2e99');
  AssertEqualWarn('0.2e-12');
end;

procedure SpecialStringTest();
begin
  AssertEqualWarn('Nan');
  AssertEqualWarn('Inf');
  AssertEqualWarn('+Inf');
  AssertEqualWarn('-Inf');
  AssertEqualWarn('+Infinity');
  AssertEqualWarn('-Infinity');
  AssertEqualWarn('+Nan');
  AssertEqualWarn('-Nan');
end;

procedure HardParseTest();
begin
  AssertEqualWarn('.e1');// not a number
  AssertEqualWarn('1.e1');
  AssertEqualWarn('.1');
  AssertEqualWarn('.1e000000000010');
  AssertEqualWarn('-.1e-000000000010');
  AssertEqualWarn('1.');
  AssertEqualWarn('2e.10');
  AssertEqualWarn('-0.00e-214');
  AssertEqualWarn('0e320');
  AssertEqualWarn('.123e10');
  AssertEqualWarn('123' + DupeString('0', 10000) + 'e-10000');// 123.0
  AssertEqualWarn('1234567891234567891234567891234' + DupeString('0', 10000) + 'e-10000');// 1234567891234567891234567891234.0
  AssertEqualWarn('-0.' + DupeString('0', 10000) + '9e10000');// -0.9
  // special values
  AssertEqualWarn('6.69692879491417e+299');
  AssertEqualWarn('3.7252902984619140625e-09');
  AssertEqualWarn('1.1754943508222875080e-38');
  AssertEqualWarn('1.4012984643248170709e-45');
  AssertEqualWarn('340282346638528859811704183484516925440.0');
  AssertEqualWarn('2.2250738585072013831e-308');
  AssertEqualWarn('4.9406564584124654418e-324');
  AssertEqualWarn('1.7976931348623157081e+308');
  AssertEqualWarn('1.8145860519450699870567321328132e-5');
  AssertEqualWarn('0.34657359027997265470861606072909');
  // inf
  AssertEqualWarn('1000000000000e307');// +inf
  AssertEqualWarn('-1000000000000e307');// -inf
  // demo values
  AssertEqualWarn('18014398509481993');
end;

procedure RandomIntegerTest();
var
  I, J: Integer;
  S: UnicodeString;
begin
  SetTestSeed(29);

  for I := 0 to TestCount - 1 do
  begin
    S := '';
    // make sign
    if TestRandom(2) = 0 then
      S := S + '-'
    else
      S := S + '+';
    // make digits
    for J := 0 to DigitCount - 1 do
    begin
      S := S + Char(Ord('0') + TestRandom(10));
    end;
    // check
    AssertEqual(S);
  end;
end;

procedure RandomDoubleTest();
var
  I, J: Integer;
  S: UnicodeString;
begin
  SetTestSeed(777);
  //
  for I := 0 to TestCount - 1 do
  begin
    S := '';
    // make sign
    if TestRandom(2) = 0 then
      S := S + '-'
    else
      S := S + '+';
    // make digits
    for J := 0 to DigitCount - 1 do
    begin
      S := S + Char(Ord('0') + TestRandom(10));
    end;
    // dot
    Insert('.', S, 2 + TestRandom(Length(S) - 2 + 1));
    // check
    AssertEqual(S);
  end;
end;

procedure RoundTest();
var
  I, J: Integer;
  S: UnicodeString;
begin
  SetTestSeed(1337);
  for I := 0 to TestCount - 1 do
  begin
    S := '1';
    for J := 0 to DigitCount - 1 - 1 do
    begin
      case TestRandom(30) of
        1: S := S + '1';
        5: S := S + '5';
        6: S := S + '6';
      else
        S := S + '0';
      end;
    end;
    S := S + 'e' + IntToStr(291 - TestRandom(291 * 2 + 1));
    AssertEqual(S);
  end;
end;

procedure RegularDoubleTest();
var
  I, J: Integer;
  S: UnicodeString;
begin
  SetTestSeed(57005);
  for I := 0 to TestCount - 1 do
  begin
    S := '';
    // make sign
    if TestRandom(2) = 0 then
      S := S + '-'
    else
      S := S + '+';
    // make digits
    for J := 0 to TestRandom(DigitCount - 1) + 1 do
    begin
      S := S + Char(Ord('0') + TestRandom(10));
    end;
    // dot
    Insert('.', S, 2 + TestRandom(Length(S) - 2 + 1));
    // expo
    S := S + 'e' + IntToStr(291 - TestRandom(291 * 2 + 1));
    // test
    AssertEqual(S);
  end;
end;

procedure BigDoubleTest();
var
  I, J: Integer;
  S: UnicodeString;
begin
  SetTestSeed(57005);
  for I := 0 to TestCount - 1 do
  begin
    S := '';
    // make sign
    if TestRandom(2) = 0 then
      S := S + '-'
    else
      S := S + '+';
    // make digits
    for J := 0 to TestRandom(DigitCount - 1) + 1 do
    begin
      S := S + Char(Ord('0') + TestRandom(10));
    end;
    // dot
    Insert('.', S, 2 + TestRandom(Length(S) - 2 + 1));
    // expo
    S := S + 'e' + IntToStr(280 + TestRandom(30));
    // test
    AssertEqual(S);
  end;
end;

procedure HardOneUlpDiffTest();
var
  I, J: Integer;
  S: UnicodeString;
begin
  SetTestSeed(47806);
  for I := 0 to TestCount - 1 do
  begin
    S := '';
    // make sign
    if TestRandom(2) = 0 then
      S := S + '-'
    else
      S := S + '+';
    // make digits
    for J := 0 to TestRandom(200) + 1 do
    begin
      S := S + Char(Ord('0') + TestRandom(10));
    end;
    // expo
    S := S + 'e' + IntToStr(-290 - TestRandom(100));
    // test
    Assert(UlpDiff(S) <> udtMoreThanOne);
  end;
end;

procedure HardRoundOneUlpDiffTest();
var
  I, J: Integer;
  S: UnicodeString;
begin
  SetTestSeed(2077);
  for I := 0 to TestCount - 1 do
  begin
    S := '1';
    for J := 0 to 10 + TestRandom(50) do
    begin
      case TestRandom(30) of
        1: S := S + '1';
        5: S := S + '5';
        6: S := S + '6';
      else
        S := S + '0';
      end;
    end;
    S := S + 'e' + IntToStr(-290 - TestRandom(100));
    Assert(UlpDiff(S) <> udtMoreThanOne);
  end;
end;

procedure RegularOneUlpDiffTest();
var
  I, J: Integer;
  S: UnicodeString;
  Diff: TUlpDiffType;
  OneUlpErrorCount: Integer;
  MoreUlpErrorCount: Integer;
begin
  SetTestSeed(237);

  OneUlpErrorCount := 0;
  MoreUlpErrorCount := 0;
  for I := 0 to TestCount - 1 do
  begin
    S := '';
    // make sign
    if TestRandom(2) = 0 then
      S := S + '-'
    else
      S := S + '+';
    // make digits
    for J := 0 to TestRandom(30) + 1 do
    begin
      S := S + Char(Ord('0') + TestRandom(10));
    end;
    // dot
    Insert('.', S, 2 + TestRandom(Length(S) - 2 + 1));
    // expo
    S := S + 'e' + IntToStr(308 - TestRandom(308 + 324 + 10 + 1));
    // test
    Diff := UlpDiff(S);
    if Diff = udtOne then
      OneUlpErrorCount := OneUlpErrorCount + 1
    else if Diff = udtMoreThanOne then
      MoreUlpErrorCount := MoreUlpErrorCount + 1;
  end;

  // display
  Writeln('    Number Count: ', TestCount);
  Writeln('    One ULP Error Count: ', OneUlpErrorCount);
  case TestCount of
    100000: Writeln('      Expected: ', 39);
    1000000: Writeln('      Expected: ', 328);
    10000000: Writeln('      Expected: ', 3386);
  end;
  if MoreUlpErrorCount <> 0 then
    Writeln('    More Than One ULP Error Count (Fail Count): ', MoreUlpErrorCount);
  Writeln('    Percent Error: ', ((OneUlpErrorCount + MoreUlpErrorCount) / TestCount) * 100:0:3, '%');
  if MoreUlpErrorCount > 0 then
  begin
    Writeln('      One ULP Error: ', (OneUlpErrorCount / TestCount) * 100:0:3, '%');
    Writeln('      More ULP Error: ', (MoreUlpErrorCount / TestCount) * 100:0:3, '%');
  end;

  // final check
  Assert(MoreUlpErrorCount = 0);
end;

procedure LongNumberOneUlpDiffTest();
var
  I, J: Integer;
  S: UnicodeString;
  Diff: TUlpDiffType;
  OneUlpErrorCount: Integer;
  MoreUlpErrorCount: Integer;
begin
  SetTestSeed(420);

  OneUlpErrorCount := 0;
  MoreUlpErrorCount := 0;
  for I := 0 to TestCount - 1 do
  begin
    S := '';
    // make sign
    if TestRandom(2) = 0 then
      S := S + '-'
    else
      S := S + '+';
    // make digits
    for J := 0 to TestRandom(200) + 1 do
    begin
      S := S + Char(Ord('0') + TestRandom(10));
    end;
    // dot
    Insert('.', S, 2 + TestRandom(Length(S) - 2 + 1));
    // expo
    S := S + 'e' + IntToStr(308 - TestRandom(308 + 324 + 10 + 1));
    // test
    Diff := UlpDiff(S);
    if Diff = udtOne then
      OneUlpErrorCount := OneUlpErrorCount + 1
    else if Diff = udtMoreThanOne then
      MoreUlpErrorCount := MoreUlpErrorCount + 1;
  end;

  // display
  Writeln('    Number Count: ', TestCount);
  Writeln('    One ULP Error Count: ', OneUlpErrorCount);
  case TestCount of
    100000: Writeln('      Expected: ', 11);
    1000000: Writeln('      Expected: ', 128);
    10000000: Writeln('      Expected: ', 1379);
  end;
  if MoreUlpErrorCount <> 0 then
    Writeln('    More Than One ULP Error Count (Fail Count): ', MoreUlpErrorCount);
  Writeln('    Percent Error: ', ((OneUlpErrorCount + MoreUlpErrorCount) / TestCount) * 100:0:3, '%');
  if MoreUlpErrorCount > 0 then
  begin
    Writeln('      One ULP Error: ', (OneUlpErrorCount / TestCount) * 100:0:3, '%');
    Writeln('      More ULP Error: ', (MoreUlpErrorCount / TestCount) * 100:0:3, '%');
  end;

  // final check
  Assert(MoreUlpErrorCount = 0);
end;

procedure ReadWriteOneUlpDiffTest();
var
  I: Integer;
  S: UnicodeString;
  Diff: TUlpDiffType;
  OneUlpErrorCount: Integer;
  MoreUlpErrorCount: Integer;
  D: Double;
  W: array [0..3] of UInt16 absolute D;
begin
  SetTestSeed(1591);

  OneUlpErrorCount := 0;
  MoreUlpErrorCount := 0;
  for I := 0 to TestCount - 1 do
  begin
    // make bit/double
    repeat
      W[0] := TestRandom($FFFF + 1);
      W[1] := TestRandom($FFFF + 1);
      W[2] := TestRandom($FFFF + 1);
      W[3] := TestRandom($FFFF + 1);
    until not (IsInfinite(D) or IsNan(D));
    // https://stackoverflow.com/questions/6988192/cant-get-a-nan-from-the-msvcrt-strtod-sscanf-atof-functions
    // gen string
    S := IeeeDoubleToString(D);
    // test
    Diff := UlpDiff(S);
    if Diff = udtOne then
      OneUlpErrorCount := OneUlpErrorCount + 1
    else if Diff = udtMoreThanOne then
      MoreUlpErrorCount := MoreUlpErrorCount + 1;
  end;

  // display
  Writeln('    Number Count: ', TestCount);
  Writeln('    One ULP Error Count: ', OneUlpErrorCount);
  case TestCount of
    100000: Writeln('      Expected: ', 16);
    1000000: Writeln('      Expected: ', 157);
    10000000: Writeln('      Expected: ', 1624);
  end;
  if MoreUlpErrorCount <> 0 then
    Writeln('    More Than One ULP Error Count (Fail Count): ', MoreUlpErrorCount);
  Writeln('    Percent Error: ', ((OneUlpErrorCount + MoreUlpErrorCount) / TestCount) * 100:0:3, '%');
  if MoreUlpErrorCount > 0 then
  begin
    Writeln('      One ULP Error: ', (OneUlpErrorCount / TestCount) * 100:0:3, '%');
    Writeln('      More ULP Error: ', (MoreUlpErrorCount / TestCount) * 100:0:3, '%');
  end;

  // final check
  Assert(MoreUlpErrorCount = 0);
end;

procedure Benchmark();
var
  UnicodeTestStrings: array of UnicodeString;
  AnsiTestStrings: array of AnsiString;
  D: Double;
  W: array [0..3] of UInt16 absolute D;
  E: Extended;
  S: UnicodeString;
  I: Integer;
  PAnsiEnd: PAnsiChar;
  Time: UInt64;
  Times: array of Int64;
  N: Integer;
begin
  Writeln('Benchmark, less time is better.');
  Writeln;

  // make
  SetTestSeed(404);
  UnicodeTestStrings := [];
  AnsiTestStrings := [];
  for I := 0 to 10000 do
  begin
    // make bit/double
    repeat
      W[0] := TestRandom($FFFF + 1);
      W[1] := TestRandom($FFFF + 1);
      W[2] := TestRandom($FFFF + 1);
      W[3] := TestRandom($FFFF + 1);
    until not (IsInfinite(D) or IsNan(D));
    // https://stackoverflow.com/questions/6988192/cant-get-a-nan-from-the-msvcrt-strtod-sscanf-atof-functions
    // gen string
    S := IeeeDoubleToString(D);
    UnicodeTestStrings := UnicodeTestStrings + [S];
    AnsiTestStrings := AnsiTestStrings + [AnsiString(S)];
  end;

  Times := [0, 0, 0, 0, 0, 0];
  for N := 0 to 400 - 1 do
  begin
    // netlib/David M. Gay
    Time := TThread.GetTickCount64();
    for I := 0 to High(AnsiTestStrings) do
    begin
      IeeeCharsToDouble(PAnsiChar(AnsiTestStrings[I]), @PAnsiEnd);
    end;
    Times[0] := Times[0] + Int64(TThread.GetTickCount64() - Time);

    // delphi TextToFloat
    Time := TThread.GetTickCount64();
    for I := 0 to High(AnsiTestStrings) do
    begin
      {$IFDEF FPC}
      SysUtils.TextToFloat(PAnsiChar(AnsiTestStrings[I]), E, fvExtended);
      {$ELSE}
      SysUtils.TextToFloat(PWideChar(UnicodeTestStrings[I]), E, fvExtended);
      {$ENDIF}
    end;
    Times[1] := Times[1] + Int64(TThread.GetTickCount64() - Time);

    // microsoft strtod
    Time := TThread.GetTickCount64();
    for I := 0 to High(AnsiTestStrings) do
    begin
      MsvcrtStrtod(PAnsiChar(AnsiTestStrings[I]), @PAnsiEnd);
    end;
    Times[2] := Times[2] + Int64(TThread.GetTickCount64() - Time);

    // ParseFloat
    Time := TThread.GetTickCount64();
    for I := 0 to High(AnsiTestStrings) do
    begin
      ParseFloat(PWideChar(UnicodeTestStrings[I]), D);
    end;
    Times[3] := Times[3] + Int64(TThread.GetTickCount64() - Time);

    // ParseFloat C
    if TestCVersion then
    begin
      Time := TThread.GetTickCount64();
      for I := 0 to High(AnsiTestStrings) do
      begin
        pure_parse_float(PAnsiChar(AnsiTestStrings[I]), @D, nil);
      end;
      Times[4] := Times[4] + Int64(TThread.GetTickCount64() - Time);
    end;

    // ParseFloat dll
    if @dll_pure_parse_float <> nil then
    begin
      Time := TThread.GetTickCount64();
      for I := 0 to High(AnsiTestStrings) do
      begin
        dll_pure_parse_float(PAnsiChar(AnsiTestStrings[I]), @D, @PAnsiEnd);
      end;
      Times[5] := Times[5] + Int64(TThread.GetTickCount64() - Time);
    end;
  end;

  Writeln('Netlib strtod: ', Times[0], 'ms');
  Writeln('Delphi TextToFloat: ', Times[1], 'ms');
  Writeln('Microsoft strtod: ', Times[2], 'ms');
  Writeln('ParseFloat: ', Times[3], 'ms');
  if TestCVersion then
  begin
    Writeln('ParseFloat C Version: ', Times[4], 'ms');
    if Times[3] >= Times[4] then
    begin
      Writeln('  ', (Times[3] / Times[4]):0:2, 'x faser');
    end else
    begin
      Writeln('  ', (Times[4] / Times[3]):0:2, 'x slower');
    end;
  end;
  if @dll_pure_parse_float <> nil then
  begin
    Writeln('User DLL ParseFloat: ', Times[5], 'ms');
  end;
end;

procedure DoRunTests();
var
  Tests: array of TTest;
  I: Integer;
  SuccessCount: Integer;
  CmdSize, CmdMode: UnicodeString;
  DllName, DllFunctionName: UnicodeString;
begin
  Writeln('=== PureFloatParser Test ===');

  if FindCmdLineSwitch('dll') then
  begin
    if not FindCmdLineSwitch('function') then
    begin
      Writeln('Please use -function with -dll option!');
      exit;
    end;
    // load dll
    {$IFDEF FPC}
    DllName := GetCmdLineArg('dll', ['-']);
    {$ELSE}
    DllName := '';
    FindCmdLineSwitch('dll', DllName, True, [clstValueNextParam]);
    {$ENDIF}
    if DllName = '' then
    begin
      Writeln('Bad -dll param!');
      exit;
    end;
    {$IFDEF FPC}
    dll_pure_parse_float_library := LoadLibrary(PAnsiChar(AnsiString(DllName)));
    {$ELSE}
    dll_pure_parse_float_library := LoadLibrary(PWideChar(DllName));
    {$ENDIF}
    if pure_parse_float_library = 0 then
    begin
      Writeln('Can''t open "' + DllName + '" dll!');
      exit;
    end;
    // load func
    {$IFDEF FPC}
    DllFunctionName := GetCmdLineArg('function', ['-']);
    {$ELSE}
    DllFunctionName := '';
    FindCmdLineSwitch('function', DllFunctionName, True, [clstValueNextParam]);
    {$ENDIF}
    if DllFunctionName = '' then
    begin
      Writeln('Bad -function param!');
      exit;
    end;
    {$IFDEF FPC}
    @dll_pure_parse_float := GetProcAddress(dll_pure_parse_float_library, PAnsiChar(AnsiString(DllFunctionName)));
    {$ELSE}
    @dll_pure_parse_float := GetProcAddress(dll_pure_parse_float_library, PWideChar(DllFunctionName));
    {$ENDIF}
    if @dll_pure_parse_float = nil then
    begin
      Writeln('Can''t load function "' + DllFunctionName + '" from dll!');
      exit;
    end;
    // print info
    Writeln('*** Parser function "' + DllFunctionName + '", from user DLL "', DllName, '" ***');
  end;

  if FindCmdLineSwitch('c') then
  begin
    if @pure_parse_float = nil then
    begin
      Writeln('Please place pure_float_parser_c_32.dll/pure_float_parser_c_64.dll for test C version!');
      exit;
    end;
    TestCVersion := True;
  end;

  if FindCmdLineSwitch('benchmark') then
  begin
    Benchmark();
    exit;
  end;

  {$IFDEF FPC}
  CmdSize := GetCmdLineArg('size', ['-']);
  {$ENDIF}
  if {$IFDEF FPC}CmdSize <> ''{$ELSE}FindCmdLineSwitch('size', CmdSize, True, [clstValueNextParam]){$ENDIF} then
  begin
    if UpperCase(CmdSize) = 'SMALL' then
    begin
      TestCount := SizeSmall;
    end
    else if UpperCase(CmdSize) = 'MEDIUM' then
    begin
      TestCount := SizeMedium;
    end
    else if UpperCase(CmdSize) = 'LARGE' then
    begin
      TestCount := SizeLarge;
    end else
    begin
      Writeln('Bad param size!');
      exit;
    end;
  end else
  begin
    Writeln('Use "-size small/medium/large" for change sub test count.');
    Writeln('  Size=Small by default.');
    Writeln;
  end;

  {$IFDEF FPC}
  CmdMode := GetCmdLineArg('parser', ['-']);
  {$ENDIF}
  if {$IFDEF FPC}CmdMode <> ''{$ELSE}FindCmdLineSwitch('parser', CmdMode, True, [clstValueNextParam]){$ENDIF} then
  begin
    if UpperCase(CmdMode) = 'PURE' then
    begin
      Mode := ModePure;
    end
    else if UpperCase(CmdMode) = 'DELPHI' then
    begin
      Mode := ModeDelphi;
    end
    else if UpperCase(CmdMode) = 'MICROSOFT' then
    begin
      Mode := ModeMicrosoft;
    end else
    begin
      Writeln('Bad param parser!');
      exit;
    end;
  end
  else if @dll_pure_parse_float = nil then
  begin
    Writeln('Use "-parser pure/delphi/microsoft" for change a parser under test.');
    Writeln('  Parser=Pure by default.');
    Writeln;
  end;

  if High(NativeInt) = High(Int32) then
    Writeln('  32 bit cpu')
  else
    Writeln('  64 bit cpu');

  if @dll_pure_parse_float = nil then
  begin
    case Mode of
      ModePure: Writeln('  Parser=Pure');
      ModeDelphi: Writeln('  Parser=Delphi');
      ModeMicrosoft: Writeln('  Parser=Microsoft');
    end;
    if TestCVersion then
    begin
      Writeln('  Test C Version');
    end;
  end else
    Writeln('  Parser=User DLL');

  case TestCount of
    SizeSmall: Writeln('  Size=Small');
    SizeMedium: Writeln('  Size=Medium');
    SizeLarge: Writeln('  Size=Large');
  end;

  Writeln;

  // make tests
  Tests := [
    MakeTest('Simple Integer Test', SimpleIntegerTest),
    MakeTest('Simple Float Test', SimpleFloatTest),
    MakeTest('Simple Exponent Test', SimpleExponentTest),
    MakeTest('Special String Test', SpecialStringTest),
    MakeTest('Hard Parse Test', HardParseTest),
    MakeTest('Random Integer Test', RandomIntegerTest),
    MakeTest('Random Double Test',  RandomDoubleTest),
    MakeTest('Round Test', RoundTest),
    MakeTest('Regular Double Test', RegularDoubleTest),
    MakeTest('Big Double Test', BigDoubleTest),
    MakeTest('Hard One Ulp Diff Test', HardOneUlpDiffTest),
    MakeTest('Hard Round One Ulp Diff Test', HardRoundOneUlpDiffTest), 
    MakeTest('Regular One Ulp Diff Test', RegularOneUlpDiffTest),
    MakeTest('Long Number One Ulp Diff Test', LongNumberOneUlpDiffTest),
    MakeTest('Read Write One Ulp Diff Test', ReadWriteOneUlpDiffTest)
  ];

  // run tests
  SuccessCount := 0;
  for I := 0 to High(Tests) do
  begin
    Writeln('Start "', Tests[I].Name, '", ', (I + 1), '/', Length(Tests));
    try
      Tests[I].Proc();
      SuccessCount := SuccessCount + 1;
      Writeln('  Passed!');
    except
      Writeln('  Failed!');
    end;
  end;

  // show result
  Writeln;
  if SuccessCount = Length(Tests) then
  begin
    Writeln('All Tests Passed!');
    Writeln('  Count: ', Length(Tests));
  end else
  begin
    Writeln('Tests Failed!');
    Writeln('  Count: ', Length(Tests));
    Writeln('  Passed: ', SuccessCount);
    Writeln('  Faild: ', Length(Tests) - SuccessCount);
  end;
end;

procedure RunTests();
var
  Time: UInt64;
begin
  FormatSettings.DecimalSeparator := '.';
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  SetRoundMode(rmNearest);
  SetPrecisionMode(pmDouble);

  Time := TThread.GetTickCount64();
  try
    DoRunTests();
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
  Writeln;
  Writeln('Executing Time: ', (TThread.GetTickCount64() - Time) div 1000, 's');
  Writeln;

  Writeln('Press Enter to exit...');
  Readln;
end;

initialization
  {$IFDEF CPUX64}
  pure_parse_float_library := LoadLibrary('pure_parse_float_c_64.dll');
  {$ELSE}
  pure_parse_float_library := LoadLibrary('pure_parse_float_c_32.dll');
  {$ENDIF}
  if pure_parse_float_library <> 0 then
  begin
    @pure_parse_float := GetProcAddress(pure_parse_float_library, 'pure_parse_float');
  end;

finalization
  FreeLibrary(pure_parse_float_library);
  FreeLibrary(dll_pure_parse_float_library);

end.

