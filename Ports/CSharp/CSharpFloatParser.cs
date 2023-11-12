using System.Collections;
using System.Runtime.InteropServices;
using System.Text;

namespace CSharpSafe
{
    public class CSharpFloatParser
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

            public FixedDecimal() { }
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

        private static int TextPrefixLength(string text, string prefix)
        {
            int i = 0;

            while (i < text.Length && i < prefix.Length && (char.ToLowerInvariant(text[i]) == char.ToLowerInvariant(prefix[i])))
            {
                if (text[i] == '\0') break;
                i++;
            }

            return i;
        }

        static int ReadSpecial(ref double number, string text, ref int index)
        {
            int isNegative = 0;
            int len;

            isNegative = 0;

            index = 0;

            switch (text[index])
            {
                case '+':
                    index++;
                    break;
                case '-':
                    isNegative = 1;
                    index++;
                    break;
            }

            switch (Char.ToLower(text[index]))
            {
                case 'i':
                    len = TextPrefixLength(text.Substring(index), "infinity");
                    if (len == 3 || len == 8)
                    {
                        number = Double.PositiveInfinity;

                        if (isNegative == 1)
                            number = -number;
                        
                        index += len;

                        return 1;
                    }
                    break;
                case 'n':
                    len = TextPrefixLength(text.Substring(index), "nan");
                    if (len == 3)
                    {
                        number = Double.CopySign(Double.NaN, +0.0);

                        if (isNegative == 1)
                            number = -number;
                        
                        index += len;

                        return 1;
                    }
                    break;
            }

            number = 0;
            return 0;
        }

        private static int ReadTextToFixedDecimal(ref FixedDecimal result, string text, ref int index)
        {
            const long clipExponent = 1000000;

            result.Count = 0;
            result.IsNegative = 0;
            result.Exponent = -1;
            result.Digits = new byte[17 * 2];

            index = 0;

            if (text[index] == '-')
            {
                result.IsNegative = 1;
                index++;
            }
            else if (text[index] == '+') index++;
            
            int hasPoint = 0;
            int hasDigit = 0;

            while (index < text.Length)
            {
                switch (text[index])
                {
                    case '0':
                    case '1':
                    case '2':
                    case '3':
                    case '4':
                    case '5':
                    case '6':
                    case '7':
                    case '8':
                    case '9':
                        if (result.Count != 0 || text[index] != '0')
                        {
                            if (result.Count < result.Digits.Length)
                            {
                                result.Digits[result.Count] = (byte)(text[index] - '0');
                                result.Count++;
                            }

                            if (hasPoint == 0 && result.Exponent < clipExponent)
                                result.Exponent++;
                        }
                        else
                        {
                            if (hasPoint == 1 && result.Exponent > -clipExponent)
                                result.Exponent--;
                        }
                        hasDigit = 1;
                        break;
                    case '.':
                        if (hasPoint == 1) return 1;

                        hasPoint = 1;
                        break;
                    default:
                        goto EndReadMantissa;
                }

                index++;
            }

        EndReadMantissa:

            if (hasDigit == 0)
            {
                index = 0;
                return 0;
            }

            if ((index < text.Length) && (text[index] == 'e' || text[index] == 'E'))
            {
                int startIndexExponent = index;
                index++;

                long exponent = 0;
                int exponentSign = 1;

                switch (text[index])
                {
                    case '+':
                        index++;
                        break;
                    case '-':
                        exponentSign = -1;
                        index++;
                        break;
                }

                if ((text[index] >= '0' && text[index] <= '9'))
                {
                    while ((index < text.Length) && (text[index] >= '0' && text[index] <= '9'))
                    {
                        exponent = exponent * 10 + (text[index] - '0');
                        
                        if (exponent > clipExponent)
                            exponent = clipExponent;
                        
                        index++;
                    }
                }
                else
                {
                    index = startIndexExponent;
                    return 1;
                }

                result.Exponent += exponentSign * exponent;
            }

            return 1;
        }

        private static double FixedDecimalToDouble(FixedDecimal decimalValue)
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

            for (int i = 0; i < decimalValue.Count; i++)
            {
                if (number.Hi <= maxSafeHi)
                {
                    number.Hi = number.Hi * 10;
                    number.Hi = number.Hi + decimalValue.Digits[i];
                }
                else
                {
                    number = DoubleDoubleMul21(number, 10.0);
                    number = DoubleDoubleAdd21(number, decimalValue.Digits[i]);
                }
            }

            long exponent = decimalValue.Exponent - decimalValue.Count + 1;

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

            if (decimalValue.IsNegative != 0)
                result = -result;
            
            return result;
        }


        private static int ParseFloatSafe(string text, ref double value, ref int index)
        {
            FixedDecimal decimalResult = new();

            if (ReadSpecial(ref value, text, ref index) == 1) return 1;
            
            if (ReadTextToFixedDecimal(ref decimalResult, text, ref index) == 1)
            {
                value = FixedDecimalToDouble(decimalResult);

                return 1;
            }

            return 0;
        }

        [UnmanagedCallersOnly(EntryPoint = "ParseFloat")]
        public static unsafe int ParseFloat(byte* text, double* value, byte** textEnd)
        {
            double doubleValue = 0.0;
            int index = 0;

            int length = 0;
            while (text[length] != 0)
                length++;
            

            byte[] byteArray = new byte[length];
            for (int i = 0; i < length; i++)
                byteArray[i] = text[i];
            

            string textString = Encoding.ASCII.GetString(byteArray);

            int result = ParseFloatSafe(textString, ref doubleValue, ref index);

            *value = doubleValue;

            *textEnd = text + index;

            return result;
        }
    }
}