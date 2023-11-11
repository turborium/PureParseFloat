// -------------------------------------------------------------------------------------------------
//                       ______           __               _
//                      /_  __/_  _______/ /_  ____  _____(_)_  ______ ___
//                       / / / / / / ___/ __ \/ __ \/ ___/ / / / / __ `__ \
//                      / / / /_/ / /  / /_/ / /_/ / /  / / /_/ / / / / / /
//                     /_/  \__,_/_/  /_.___/\____/_/  /_/\__,_/_/ /_/ /_/
//
//           ____                     ____                          ______            __
//          / __ \__  __________     / __ \____ ______________     / __/ /___  ____ _/ /_
//         / /_/ / / / / ___/ _ \   / /_/ / __ `/ ___/ ___/ _ \   / /_/ / __ \/ __ `/ __/
//        / ____/ /_/ / /  /  __/  / ____/ /_/ / /  (__  )  __/  / __/ / /_/ / /_/ / /_
//       /_/    \__,_/_/   \___/  /_/    \__,_/_/  /____/\___/  /_/ /_/\____/\__,_/\__/
//
// -------------------------------------------------------------------------------------------------
//
// Pure Parse Float - This is a simple and clear, "clean" algorithm and implementation of a function
// for converting a string to a double number, with OK accuracy.
// The main feature of the algorithm that underlies this implementation is the trade-off between
// simplicity, accuracy, and speed.
//
// Original place: https://github.com/turborium/PureParseFloat
//
// -------------------------------------------------------------------------------------------------
//
// Pure Parse Float algorithm repeats the usual Simple Parse Float algorithm,
// but uses Double-Double arithmetic for correct rounding.
//
// Double-Double arithmetic is a technique to implement nearly quadruple precision using
// pairs of Double values. Using two IEEE Double values with 53-bit mantissa,
// Double-Double arithmetic provides operations on numbers with mantissa of least 2*53 = 106 bit.
// But the range(exponent) of a Double-Double remains same as the Double format.
// Double-Double number have a guaranteed precision of 31 decimal digits, with the exception of
// exponents less than -291(exp^2 >= -968), due denormalized numbers, where the precision of a
// Double-Double gradually decreases to that of a regular Double.
// An small overview of the Double-Double is available here:
// https://en.wikipedia.org/wiki/Quadruple-precision_floating-point_format#Double-double_arithmetic
// More information about Double-Double is provided in the list below in this file.
//
// The key feature of Double-Double is that it is Hi + Lo, where Hi is the properly rounded
// "Big" number, and Lo is some kind of "Remainder" that we simply ignore when converting
// Double-Double to Double.
// For example: 123456789123456789123456789 presented as 1.2345678912345679e+26 + -2.214306027e+9.
//
// -------------------------------------------------------------------------------------------------
//
// Licensed under an unmodified MIT license.
//
// Copyright (c) 2023-2023 Turborium
//
// -------------------------------------------------------------------------------------------------
unit PureParseFloat;

// User Defined Options
{$INCLUDE PureParseFloat.inc}

// Only for FreePascal
{$IFDEF FPC}
  {$WARN 5059 OFF}
  {$MODE DELPHIUNICODE}
  {$IFDEF CPUI386}
    {$DEFINE CPUX86}
  {$ENDIF}
{$ENDIF}

// Compiler Options
{$WARN SYMBOL_PLATFORM OFF}
{$OPTIMIZATION ON}
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
{$IOCHECKS OFF}
{$INLINE ON}

interface

// -------------------------------------------------------------------------------------------------
// ParseFloat parse chars with float point pattern to Double and stored to Value param.
// If no chars match the pattern then Value is unmodified, else the chars convert to
// float point value which will be is stored in Value.
// On success, EndPtr points at the first char not matching the float point pattern.
// If there is no pattern match, EndPtr equals with TextPtr.
//
// If successful function return True else False.
// Remember: on failure, the Value will not be changed.
//
// The pattern is a regular float number, with an optional exponent (E/e) and optional (+/-) sign.
// The pattern allows the values Inf/Infinity and NaN, with any register and optional sign.
// Leading spaces are not allowed in the pattern. A dot is always used as separator.
// -------------------------------------------------------------------------------------------------
//
// Examples:
//
//   "1984\0"             -- just read to terminal
//    ^   ^-------
// TextPtr,    EndPtr,    Value = 1984,        Result = True
//
//
//   "+123.45e-22 abc\0"  -- read to end of float number
//    ^          ^
// TextPtr,    EndPtr,    Value = 123.45e-22,  Result = True
//
//
//   "aboba\0"            -- invalid float point
//    ^----------
// TextPtr,    EndPtr,    Value = dont change, Result = False
//
//
//   "AAA.99\0"           -- read with leading dot notation
//    ---^  ^-----
// TextPtr,    EndPtr,    Value = 0.99,        Result = True
//
//
//   "500e\0"             -- read correct part of input
//    ^  ^--------
// TextPtr,    EndPtr,    Value = 500,         Result = True
//
// -------------------------------------------------------------------------------------------------

function ParseFloat(const TextPtr: PWideChar; var Value: Double; out EndPtr: PWideChar): Boolean; overload;
function ParseFloat(const TextPtr: PWideChar; var Value: Double): Boolean; overload;

function TryCharsToFloat(const TextPtr: PWideChar; out Value: Double): Boolean;
function CharsToFloat(const TextPtr: PWideChar; const Default: Double = 0.0): Double;

function TryStringToFloat(const Str: UnicodeString; out Value: Double): Boolean;
function StringToFloat(const Str: UnicodeString; const Default: Double = 0.0): Double;

implementation

{$IFNDEF PURE_PARSE_FLOAT_DISABLE_SET_NORMAL_FPU_SETTINGS}
{$IF NOT(DEFINED(CPUX86) OR DEFINED(CPUX64))}
uses
  Math;
{$ENDIF}
{$ENDIF}

// -------------------------------------------------------------------------------------------------
// Double-Double arithmetic routines
//
// [1]
// Mioara Joldes, Jean-Michel Muller, Valentina Popescu.
// Tight and rigourous error bounds for basic building blocks of double-word arithmetic, 2017.
// [https://hal.science/hal-01351529v3/document]
//
// [2]
// T. J. Dekker, A Floating-Point Technique for Extending the Available Precision, 1971
// [https://csclub.uwaterloo.ca/~pbarfuss/dekker1971.pdf]
//
// [3]
// Yozo Hida, Xiaoye Li, David Bailey. Library for Double-Double and Quad-Double Arithmetic, 2000.
// [http://web.mit.edu/tabbott/Public/quaddouble-debian/qd-2.3.4-old/docs/qd.pdf]
//
// [4]
// Laurent Thevenoux, Philippe Langlois, Matthieu Martel.
// Automatic Source-to-Source Error Compensation of Floating-Point Programs
// [https://hal.science/hal-01158399/document]
//
// [5]
// Jonathan Richard Shewchuk
// Adaptive Precision Floating-Point Arithmetic and Fast Robust Geometric Predicates, 1997
// [https://people.eecs.berkeley.edu/~jrs/papers/robustr.pdf]

type
  TDoubleDouble = record
    Hi, Lo: Double; // 31 digits garantee, with (exp^10 >= -291) or (exp^2 >= -968)
  end;

// Make DoubleDouble from Double
function DoubleToDoubleDouble(Value: Double): TDoubleDouble; inline;
begin
  Result.Hi := Value;
  Result.Lo := 0;
end;

// Make Double from DoubleDouble
function DoubleDoubleToDouble(const Value: TDoubleDouble): Double; inline;
begin
  Result := Value.Hi;
end;

// Check value is +Inf or -Inf
function IsInfinity(Value: Double): Boolean; inline;
begin
  Result := (Value = 1.0 / 0.0) or (Value = -1.0 / 0.0);
end;

// Add two Double1 value, condition: |A| >= |B|
// The "Fast2Sum" algorithm (Dekker 1971) [1]
function DoubleDoubleFastAdd11(A, B: Double): TDoubleDouble; inline;
begin
  Result.Hi := A + B;

  // infinity check
  if IsInfinity(Result.Hi) then
  begin
    exit(DoubleToDoubleDouble(Result.Hi));
  end;

  Result.Lo := (B - (Result.Hi - A));
end;

// The "2Sum" algorithm [1]
function DoubleDoubleAdd11(A, B: Double): TDoubleDouble; inline;
var
  AH, BH: Double;
begin
  Result.Hi := A + B;

  // infinity check
  if IsInfinity(Result.Hi) then
  begin
    exit(DoubleToDoubleDouble(Result.Hi));
  end;

  AH := Result.Hi - B;
  BH := Result.Hi - AH;

  Result.Lo := (A - AH) + (B - BH);
end;

// The "Veltkamp Split" algorithm [2] [3] [4]
// See "Splitting into Halflength Numbers" and ALGOL procedure "mul12" in Appendix in [2]
function DoubleDoubleSplit1(A: Double): TDoubleDouble; inline;
const
  // The Splitter should be chosen equal to 2^trunc(t - t / 2) + 1,
  // where t is the number of binary digits in the mantissa.
  Splitter: Double = 134217729.0;// = 2^(53 - 53 div 2) + 1 = 2^27 + 1
  // Just make sure we don't have an overflow for Splitter,
  // InfinitySplit is 2^(e - (t - t div 2))
  // where e is max exponent, t is number of binary digits.
  InfinitySplit: Double = 6.69692879491417e+299;// = 2^(1023 - (53 - 53 div 2)) = 2^996
  // just multiply by the next lower power of two to get rid of the overflow
  // 2^(+/-)27 + 1 = 2^(+/-)28
  InfinityDown: Double = 3.7252902984619140625e-09;// = 2^-(27 + 1) = 2^-28
  InfinityUp: Double = 268435456.0;// = 2^(27 + 1) = 2^28
var
  Temp: Double;
begin
  if (A > InfinitySplit) or (A < -InfinitySplit) then
  begin
    // down
    A := A * InfinityDown;
    // mul
    Temp := Splitter * A;
    Result.Hi := Temp + (A - Temp);
    Result.Lo := A - Result.Hi;
    // up
    Result.Hi := Result.Hi * InfinityUp;
    Result.Lo := Result.Lo * InfinityUp;
  end else
  begin
    Temp := Splitter * A;
    Result.Hi := Temp + (A - Temp);
    Result.Lo := A - Result.Hi;
  end;
end;

// Multiplication two Double1 value
// The "TWO-PRODUCT" algorithm [5]
function DoubleDoubleMul11(A, B: Double): TDoubleDouble;// inline;
var
  A2, B2: TDoubleDouble;
  Err1, Err2, Err3: Double;
begin
  Result.Hi := A * B;

  // infinity check
  if IsInfinity(Result.Hi) then
  begin
    exit(DoubleToDoubleDouble(Result.Hi));
  end;

  A2 := DoubleDoubleSplit1(A);
  B2 := DoubleDoubleSplit1(B);

  Err1 := Result.Hi - (A2.Hi * B2.Hi);
  Err2 := Err1 - (A2.Lo * B2.Hi);
  Err3 := Err2 - (A2.Hi * B2.Lo);

  Result.Lo := (A2.Lo * B2.Lo) - Err3;
end;

// Multiplication Double2 by Double1
// The "DWTimesFP1" algorithm [1]
function DoubleDoubleMul21(const A: TDoubleDouble; B: Double): TDoubleDouble; inline;
var
  C: TDoubleDouble;
begin
  C := DoubleDoubleMul11(A.Hi, B);

  // infinity check
  if IsInfinity(C.Hi) then
  begin
    exit(DoubleToDoubleDouble(C.Hi));
  end;

  Result := DoubleDoubleFastAdd11(C.Hi, A.Lo * B);
  Result := DoubleDoubleFastAdd11(Result.Hi, Result.Lo + C.Lo);
end;

// Division Double2 by Double1
// The "DWDivFP2" algorithm [1]
function DoubleDoubleDiv21(const A: TDoubleDouble; B: Double): TDoubleDouble; inline;
var
  P, D: TDoubleDouble;
begin
  Result.Hi := A.Hi / B;

  // infinity check
  if IsInfinity(Result.Hi) then
  begin
    exit(DoubleToDoubleDouble(Result.Hi));
  end;

  P := DoubleDoubleMul11(Result.Hi, B);

  D.Hi := A.Hi - P.Hi;
  D.Lo := D.Hi - P.Lo;

  Result.Lo := (D.Lo + A.Lo) / B;

  Result := DoubleDoubleFastAdd11(Result.Hi, Result.Lo);
end;

// Addition Double2 and Double1
// The DWPlusFP algorithm [1]
function DoubleDoubleAdd21(const A: TDoubleDouble; B: Double): TDoubleDouble; inline;
begin
  Result := DoubleDoubleAdd11(A.Hi, B);

  // infinity check
  if IsInfinity(Result.Hi) then
  begin
    exit(DoubleToDoubleDouble(Result.Hi));
  end;

  Result.Lo := Result.Lo + A.Lo;
  Result := DoubleDoubleFastAdd11(Result.Hi, Result.Lo);
end;

// -------------------------------------------------------------------------------------------------

const
  QNAN = -(0.0 / 0.0);// +NAN

type
  TDigitsArray = array [0 .. 17 * 2 - 1] of Byte;// Max digits in Double value * 2

  TFixedDecimal = record
    Count: Integer;
    Exponent: Integer;
    IsNegative: Boolean;
    Digits: TDigitsArray;
  end;

function TextPrefixLength(const Text: PWideChar; const Prefix: PWideChar): Integer;
var
  I: Integer;
begin
  I := 0;
  while (Text[I] = Prefix[I]) or
    ((Text[I] >= 'A') and (Text[I] <= 'Z') and (WideChar(Ord(Text[I]) + 32) = Prefix[I])) do
  begin
    if Text[I] = #0 then
    begin
      break;
    end;
    Inc(I);
  end;

  exit(I);
end;

function ReadSpecial(var Number: Double; const Text: PWideChar; out TextEnd: PWideChar): Boolean;
var
  P: PWideChar;
  IsNegative: Boolean;
  Len: Integer;
begin
  // clean
  IsNegative := False;

  // read from start
  P := Text;

  // read sign
  case P^ of
  '+':
    begin
      Inc(P);
    end;
  '-':
    begin
      IsNegative := True;
      Inc(P);
    end;
  end;

  // special
  case P^ of
  'I', 'i':
    begin
      Len := TextPrefixLength(P, 'infinity');
      if (Len = 3) or (Len = 8) then
      begin
        Number := 1.0 / 0.0;
        if IsNegative then
        begin
          Number := -Number;
        end;
        P := P + Len;
        TextEnd := P;
        exit(True);
      end;
    end;
  'N', 'n':
    begin
      Len := TextPrefixLength(P, 'nan');
      if Len = 3 then
      begin
        Number := QNAN;
        if IsNegative then
        begin
          Number := -Number;
        end;
        P := P + Len;
        TextEnd := P;
        exit(True);
      end;
    end;
  end;

  // fail
  TextEnd := Text;
  exit(False);
end;

function ReadTextToFixedDecimal(out Decimal: TFixedDecimal; const Text: PWideChar; out EndText: PWideChar): Boolean;
const
  ClipExponent = 1000000;
var
  P, PStartExponent: PWideChar;
  HasPoint, HasDigit: Boolean;
  ExponentSign: Integer;
  Exponent: Integer;
begin
  // clean
  Decimal.Count := 0;
  Decimal.IsNegative := False;
  Decimal.Exponent := -1;

  // read from start
  P := Text;

  // read sign
  case P^ of
  '+':
    begin
      Inc(P);
    end;
  '-':
    begin
      Decimal.IsNegative := True;
      Inc(P);
    end;
  end;

  // read mantissa
  HasDigit := False;// has read any digit (0..9)
  HasPoint := False;// has read decimal point
  while True do
  begin
    case P^ of
    '0'..'9':
      begin
        if (Decimal.Count <> 0) or (P^ <> '0') then
        begin
          // save digit
          if Decimal.Count < Length(Decimal.Digits) then
          begin
            Decimal.Digits[Decimal.Count] := Ord(P^) - Ord('0');
            Inc(Decimal.Count);
          end;
          // inc exponenta
          if (not HasPoint) and (Decimal.Exponent < ClipExponent) then
          begin
            Inc(Decimal.Exponent);
          end;
        end else
        begin
          // skip zero (dec exponenta)
          if HasPoint and (Decimal.Exponent > -ClipExponent) then
          begin
            Dec(Decimal.Exponent);
          end;
        end;
        HasDigit := True;
      end;
    '.':
      begin
        if HasPoint then
        begin
          EndText := P;
          exit(True);// make
        end;
        HasPoint := True;
      end;
    else
      break;
    end;
    Inc(P);
  end;

  if not HasDigit then
  begin
    EndText := Text;
    exit(False);// fail
  end;

  // read exponenta
  if (P^ = 'e') or (P^ = 'E') then
  begin
    PStartExponent := P;
    Inc(P);

    Exponent := 0;
    ExponentSign := 1;

    // check sign
    case P^ of
    '+':
      begin
        Inc(P);
      end;
    '-':
      begin
        ExponentSign := -1;
        Inc(P);
      end;
    end;

    // read
    if (P^ >= '0') and (P^ <= '9') then
    begin
      while (P^ >= '0') and (P^ <= '9') do
      begin
        Exponent := Exponent * 10 + (Ord(P^) - Ord('0'));
        if Exponent > ClipExponent then
        begin
          Exponent := ClipExponent;
        end;
        Inc(P);
      end;
    end else
    begin
      EndText := PStartExponent;// revert
      exit(True);// make
    end;

    // fix
    Decimal.Exponent := Decimal.Exponent + ExponentSign * Exponent;
  end;

  EndText := P;
  exit(True);// make
end;

function FixedDecimalToDouble(var Decimal: TFixedDecimal): Double;
const
  LastAccuracyExponent10 = 22;// for Double
  LastAccuracyPower10 = 1e22;// for Double
  PowerOf10: array [0..LastAccuracyExponent10] of Double = (
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
  );
  MaxSafeInt = 9007199254740991;// (2^53−1) for Double
  MaxSafeHi = (MaxSafeInt - 9) div 10;// for X * 10 + 9
var
  I: Integer;
  Number: TDoubleDouble;
  Exponent: Integer;
begin
  Number := DoubleToDoubleDouble(0.0);

  // set mantissa
  for I := 0 to Decimal.Count - 1 do
  begin
    if Number.Hi <= MaxSafeHi then
    begin
      Number.Hi := Number.Hi * 10;// * 10
      Number.Hi := Number.Hi + Decimal.Digits[I];// + Digit
    end else
    begin
      Number := DoubleDoubleMul21(Number, 10.0);// * 10
      Number := DoubleDoubleAdd21(Number, Decimal.Digits[I]);// + Digit
    end;
  end;

  // set exponent
  Exponent := Decimal.Exponent - Decimal.Count + 1;

  // positive exponent
  while Exponent > 0 do
  begin
    if Exponent > LastAccuracyExponent10 then
    begin
      // * e22
      Number := DoubleDoubleMul21(Number, LastAccuracyPower10);
      // overflow break
      if IsInfinity(DoubleDoubleToDouble(Number)) then
      begin
        break;
      end;
      Exponent := Exponent - LastAccuracyExponent10;
    end else
    begin
      // * eX
      Number := DoubleDoubleMul21(Number, PowerOf10[Exponent]);
      break;
    end;
  end;

  // negative exponent
  while Exponent < 0 do
  begin
    if Exponent < -LastAccuracyExponent10 then
    begin
      // / e22
      Number := DoubleDoubleDiv21(Number, LastAccuracyPower10);
      // underflow break
      if DoubleDoubleToDouble(Number) = 0.0 then
      begin
        break;
      end;
      Exponent := Exponent + LastAccuracyExponent10;
    end else
    begin
      // / eX
      Number := DoubleDoubleDiv21(Number, PowerOf10[-Exponent]);
      break;
    end;
  end;

  // make result
  Result := DoubleDoubleToDouble(Number);

  // fix sign
  if Decimal.IsNegative then
  begin
    Result := -Result;
  end;
end;

// -------------------------------------------------------------------------------------------------

{$IFNDEF PURE_PARSE_FLOAT_DISABLE_SET_NORMAL_FPU_SETTINGS}
type
  TFPUSettings = record
    {$IF DEFINED(CPUX86)}
    CW: UInt16;
    {$ELSEIF DEFINED(CPUX64)}
    MXCSR: UInt32;
    {$ELSE}
    ExceptionMask: TFPUExceptionMask;
    RoundingMode: TFPURoundingMode;
    PrecisionMode: TFPUPrecisionMode;
    {$ENDIF}
  end;

procedure SetNormalDoubleFPUSettings(out FPUSettings: TFPUSettings); inline;
begin
  {$IF DEFINED(CPUX86)}
  FPUSettings.CW := Get8087CW();
  Set8087CW($123F);// Mask all exceptions, Double (https://www.club155.ru/x86internalreg-fpucw)
  {$ELSEIF DEFINED(CPUX64)}
  FPUSettings.MXCSR := GetMXCSR();
  SetMXCSR($1F80);// Mask all exceptions (https://www.club155.ru/x86internalreg-simd)
  {$ELSE}
  FPUSettings.ExceptionMask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  FPUSettings.RoundingMode := SetRoundMode(rmNearest);
  FPUSettings.PrecisionMode := SetPrecisionMode(pmDouble);
  {$ENDIF}
end;

procedure RestoreFPUSettings(const FPUSettings: TFPUSettings); inline;
begin
  {$IF DEFINED(CPUX86)}
  Set8087CW(FPUSettings.CW);
  {$ELSEIF DEFINED(CPUX64)}
  SetMXCSR(FPUSettings.MXCSR);
  {$ELSE}
  SetExceptionMask(FPUSettings.ExceptionMask);
  SetRoundMode(FPUSettings.RoundingMode);
  SetPrecisionMode(FPUSettings.PrecisionMode);
  {$ENDIF}
end;
{$ENDIF}

// -------------------------------------------------------------------------------------------------

function ParseFloat(const TextPtr: PWideChar; var Value: Double; out EndPtr: PWideChar): Boolean;
var
  Decimal: TFixedDecimal;
  {$IFNDEF PURE_PARSE_FLOAT_DISABLE_SET_NORMAL_FPU_SETTINGS}
  FPUSettings: TFPUSettings;
  {$ENDIF}
begin
  // try read inf/nan
  if ReadSpecial(Value, TextPtr, EndPtr) then
  begin
    // read done
    exit(True);
  end;

  // try read number
  if ReadTextToFixedDecimal(Decimal, TextPtr, EndPtr) then
  begin
    {$IFNDEF PURE_PARSE_FLOAT_DISABLE_SET_NORMAL_FPU_SETTINGS}
    // Change FPU settings to Double Precision, Banker Rounding, Mask FPU Exceptions
    SetNormalDoubleFPUSettings(FPUSettings);
    try
      // Convert Decimal to Double
      Value := FixedDecimalToDouble(Decimal);
    finally
      // Restore FPU settings
      RestoreFPUSettings(FPUSettings);
    end;
    {$ELSE}
    // convert Decimal to Double
    Value := FixedDecimalToDouble(Decimal);
    {$ENDIF}

    // read done
    exit(True);
  end;

  // fail
  exit(False);
end;

function ParseFloat(const TextPtr: PWideChar; var Value: Double): Boolean;
var
  DeadBeef: PWideChar;
begin
  Result := ParseFloat(TextPtr, Value, DeadBeef);
end;

// -------------------------------------------------------------------------------------------------

procedure SkipSpaces(var TextPtr: PWideChar); inline;
begin
  while (TextPtr^ = ' ') or (TextPtr^ = #11) do
  begin
    Inc(TextPtr);
  end;
end;

function TryCharsToFloat(const TextPtr: PWideChar; out Value: Double): Boolean;
var
  P: PWideChar;
begin
  Value := 0.0;

  // read from start
  P := TextPtr;

  // skip leading spaces
  SkipSpaces(P);

  // try parse
  if not ParseFloat(P, Value, P) then
  begin
    Exit(False);
  end;

  // skip trailing spaces
  SkipSpaces(P);

  // check normal end
  if P^ <> #0 then
  begin
    exit(False);
  end;

  // ok
  exit(True);
end;

function CharsToFloat(const TextPtr: PWideChar; const Default: Double = 0.0): Double;
begin
  if not TryCharsToFloat(TextPtr, Result) then
  begin
    Result := Default;
  end;
end;

function TryStringToFloat(const Str: UnicodeString; out Value: Double): Boolean;
begin
  Result := TryCharsToFloat(PWideChar(Str), Value);
end;

function StringToFloat(const Str: UnicodeString; const Default: Double = 0.0): Double;
begin
  Result := CharsToFloat(PWideChar(Str), Default);
end;

end.
