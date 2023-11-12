using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

#pragma warning disable CS8500

namespace CSharpUnsafe
{
    public class CSharpFloatParserUnsafe
    {
        private struct DoubleDouble
        {
            public double Hi;
            public double Lo;
        }

        private struct FixedDecimal
        {
            public int Count;
            public long Exponent;
            public int IsNegative;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17 * 2)]
            public byte[] Digits = new byte[17 * 2];

            public FixedDecimal(){}
        }


        private static DoubleDouble DoubleToDoubleDouble(double value)
        {
            DoubleDouble result;

            result.Hi = value;
            result.Lo = 0;

            return result;
        }

        private static double DoubleDoubleToDouble(DoubleDouble value) => value.Hi;

        // Alternative is return double.IsInfinity(value);
        private static bool IsInfinity(double value) => (value == 1.0 / 0.0) || (value == -1.0 / 0.0);
        
        private static DoubleDouble DoubleDoubleFastAdd11(double a, double b)
        {
            DoubleDouble result;

            result.Hi = a + b;

            if (IsInfinity(result.Hi))
                return DoubleToDoubleDouble(result.Hi);

            result.Lo = (b - (result.Hi - a));
            return result;
        }

        private static DoubleDouble DoubleDoubleAdd11(double a, double b)
        {
            DoubleDouble result;
            double ah, bh;

            result.Hi = a + b;

            if (IsInfinity(result.Hi))
                return DoubleToDoubleDouble(result.Hi);

            ah = result.Hi - b;
            bh = result.Hi - ah;

            result.Lo = (a - ah) + (b - bh);
            return result;
        }

        private static DoubleDouble DoubleDoubleSplit1(double a)
        {
            const double splitter = 134217729.0;
            const double infinitySplit = 6.69692879491417e+299;
            const double infinityDown = 3.7252902984619140625e-09;
            const double infinityUp = 268435456.0;

            DoubleDouble result;
            double temp;

            if ((a > infinitySplit) || (a < -infinitySplit))
            {
                a *= infinityDown;
                temp = splitter * a;
                result.Hi = temp + (a - temp);
                result.Lo = a - result.Hi;
                result.Hi *= infinityUp;
                result.Lo *= infinityUp;
            }
            else
            {
                temp = splitter * a;
                result.Hi = temp + (a - temp);
                result.Lo = a - result.Hi;
            }

            return result;
        }

        private static DoubleDouble DoubleDoubleMul11(double a, double b)
        {
            DoubleDouble result;
            DoubleDouble a2, b2;
            double err1, err2, err3;

            result.Hi = a * b;

            if (IsInfinity(result.Hi))
                return DoubleToDoubleDouble(result.Hi);

            a2 = DoubleDoubleSplit1(a);
            b2 = DoubleDoubleSplit1(b);

            err1 = result.Hi - (a2.Hi * b2.Hi);
            err2 = err1 - (a2.Lo * b2.Hi);
            err3 = err2 - (a2.Hi * b2.Lo);

            result.Lo = (a2.Lo * b2.Lo) - err3;

            return result;
        }

        private static DoubleDouble DoubleDoubleMul21(DoubleDouble a, double b)
        {
            DoubleDouble result;
            DoubleDouble c;

            c = DoubleDoubleMul11(a.Hi, b);

            if (IsInfinity(c.Hi))
                return DoubleToDoubleDouble(c.Hi);

            result = DoubleDoubleFastAdd11(c.Hi, a.Lo * b);
            return DoubleDoubleFastAdd11(result.Hi, result.Lo + c.Lo);
        }

        private static DoubleDouble DoubleDoubleDiv21(DoubleDouble a, double b)
        {
            DoubleDouble result;
            DoubleDouble p, d;

            result.Hi = a.Hi / b;

            if (IsInfinity(result.Hi))
                return DoubleToDoubleDouble(result.Hi);

            p = DoubleDoubleMul11(result.Hi, b);

            d.Hi = a.Hi - p.Hi;
            d.Lo = d.Hi - p.Lo;

            result.Lo = (d.Lo + a.Lo) / b;

            return DoubleDoubleFastAdd11(result.Hi, result.Lo);
        }

        private static DoubleDouble DoubleDoubleAdd21(DoubleDouble a, double b)
        {
            DoubleDouble result;

            result = DoubleDoubleAdd11(a.Hi, b);

            if (IsInfinity(result.Hi))
                return DoubleToDoubleDouble(result.Hi);

            result.Lo = result.Lo + a.Lo;
            return DoubleDoubleFastAdd11(result.Hi, result.Lo);
        }

        private static unsafe int TextPrefixLength(byte* text, byte* prefix)
        {
            int i = 0;

            while ((text[i] == prefix[i]) ||
                  ((text[i] >= 'A') &&
                  (text[i] <= 'Z') &&
                  ((text[i] + 32) == prefix[i])))
            {
                if (text[i] == '\0') break;
                i++;
            }
            return i;
        }

        private static unsafe int ReadSpecial(double* number, byte* text, byte** textEnd)
        {
            byte* p;
            int isNegative = 0;
            int len;

            p = (byte*)text;

            switch ((char)*p)
            {
                case '+':
                    p++;
                    break;
                case '-':
                    isNegative = 1;
                    p++;
                    break;
            }

            switch ((char)*p)
            {
                case 'I':
                case 'i':
                    fixed (byte* infinityPtr = Encoding.ASCII.GetBytes("infinity"))
                        len = TextPrefixLength(p, infinityPtr);

                    if ((len == 3) || (len == 8))
                    {
                        *number = Double.PositiveInfinity;

                        if (isNegative == 1)
                            *number = -*number;
                        
                        p = p + len;
                        *textEnd = p;

                        return 1;
                    }
                    break;
                case 'N':
                case 'n':
                    fixed (byte* nanPtr = Encoding.ASCII.GetBytes("nan"))
                        len = TextPrefixLength(p, nanPtr);
                    
                    if (len == 3)
                    {
                        *number = Double.CopySign(Double.NaN, +0.0);

                        if (isNegative == 1)
                            *number = -*number;
                        
                        p = p + len;
                        *textEnd = p;

                        return 1;
                    }
                    break;
            }
            *textEnd = (byte*)text;
            return 0;
        }

        private static unsafe int ReadTextToFixedDecimal(FixedDecimal* decimalValue, byte* text, byte** textEnd)
        {
            const long clipExponent = 1000000;

            byte* p, pStartExponent;
            int hasPoint, hasDigit;
            int exponentSign;
            long exponent;

            decimalValue->Count = 0;
            decimalValue->IsNegative = 0;
            decimalValue->Exponent = -1;

            p = (byte*)text;

            switch (*p)
            {
                case (byte)'+':
                    p++;
                    break;
                case (byte)'-':
                    decimalValue->IsNegative = 1;
                    p++;
                    break;
            }

            hasDigit = 0;
            hasPoint = 0;
            while (*p != '\0')
            {
                switch (*p)
                {
                    case (byte)'0':
                    case (byte)'1':
                    case (byte)'2':
                    case (byte)'3':
                    case (byte)'4':
                    case (byte)'5':
                    case (byte)'6':
                    case (byte)'7':
                    case (byte)'8':
                    case (byte)'9':
                        if ((decimalValue->Count != 0) || (*p != '0'))
                        {
                            if (decimalValue->Count < decimalValue->Digits.Length)
                            {
                                decimalValue->Digits[decimalValue->Count] = (byte)(*p - '0');
                                decimalValue->Count++;
                            }

                            if ((hasPoint == 0) && (decimalValue->Exponent < clipExponent))
                                decimalValue->Exponent++;
                        }
                        else
                        {
                            if (hasPoint == 1 && (decimalValue->Exponent > -clipExponent))
                                decimalValue->Exponent--;
                        }
                        hasDigit = 1;
                        break;
                    case (byte)'.':
                        if (hasPoint == 1)
                        {
                            *textEnd = p;
                            return 1;
                        }
                        hasPoint = 1;
                        break;
                    default:
                        goto endReadMantissa;
                }
                p++;
            }

        endReadMantissa:

            if (hasDigit == 0)
            {
                *textEnd = (byte*)text;
                return 0;
            }

            if ((*p == 'e') || (*p == 'E'))
            {
                pStartExponent = p;
                p++;

                exponent = 0;
                exponentSign = 1;

                switch ((char)*p)
                {
                    case '+':
                        p++;
                        break;
                    case '-':
                        exponentSign = -1;
                        p++;
                        break;
                }

                if ((*p >= '0') && (*p <= '9'))
                {
                    while ((*p >= '0') && (*p <= '9'))
                    {
                        exponent = exponent * 10 + (*p - '0');

                        if (exponent > clipExponent)
                            exponent = clipExponent;
                        
                        p++;
                    }
                }
                else
                {
                    *textEnd = pStartExponent;
                    return 1;
                }

                decimalValue->Exponent = decimalValue->Exponent + exponentSign * exponent;
            }

            *textEnd = p;
            return 1;
        }

        private static unsafe double FixedDecimalToDouble(FixedDecimal* decimalValue)
        {
            const int lastAccuracyExponent10 = 22;
            const double lastAccuracyPower10 = 1e22;
            const long maxSafeInt = 9007199254740991;
            const long maxSafeHi = (maxSafeInt - 9) / 10;
            double[] powerOf10 = 
            {
                1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
                1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
            };

            DoubleDouble number = DoubleToDoubleDouble(0.0);

            for (int i = 0; i < decimalValue->Count; i++)
            {
                if (number.Hi <= maxSafeHi)
                {
                    number.Hi = number.Hi * 10;
                    number.Hi = number.Hi + decimalValue->Digits[i];
                }
                else
                {
                    number = DoubleDoubleMul21(number, 10.0);
                    number = DoubleDoubleAdd21(number, decimalValue->Digits[i]);
                }
            }

            long exponent = decimalValue->Exponent - decimalValue->Count + 1;

            while (exponent > 0)
            {
                if (exponent > lastAccuracyExponent10)
                {
                    number = DoubleDoubleMul21(number, lastAccuracyPower10);

                    if (IsInfinity(DoubleDoubleToDouble(number))) break;
                    
                    exponent -= lastAccuracyExponent10;
                }
                else
                {
                    number = DoubleDoubleMul21(number, powerOf10[exponent]);
                    break;
                }
            }

            while (exponent < 0)
            {
                if (exponent < -lastAccuracyExponent10)
                {
                    number = DoubleDoubleDiv21(number, lastAccuracyPower10);

                    if (DoubleDoubleToDouble(number) == 0.0) break;
                    
                    exponent += lastAccuracyExponent10;
                }
                else
                {
                    number = DoubleDoubleDiv21(number, powerOf10[-exponent]);
                    break;
                }
            }

            double result = DoubleDoubleToDouble(number);

            if (decimalValue->IsNegative != 0)
                result = -result;
            
            return result;
        }

        [UnmanagedCallersOnly(EntryPoint = "ParseFloat")]
        public static unsafe int ParseFloat(byte* text, double* value, byte** textEnd)
        {
            FixedDecimal decimalValue = new FixedDecimal();

            byte[] bytes = new byte[200];
            byte* dummy = (byte*)bytes[0];

            if (textEnd == null)
                textEnd = &dummy;
            
            if (ReadSpecial(value, text, textEnd) == 1) return 1;
            
            if (ReadTextToFixedDecimal(&decimalValue, text, textEnd) == 1)
            {
                *value = FixedDecimalToDouble(&decimalValue);

                return 1;
            }
            return 0;
        }
    }
}