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

#include "pure_parse_float.h"

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
//
// https://learn.microsoft.com/en-us/cpp/porting/visual-cpp-change-history-2003-2015?view=msvc-170
// https://stackoverflow.com/questions/21349847/positive-vs-negative-nans

typedef struct {
    double hi, lo; // 31 digits garantee, with (exp^10 >= -291) or (exp^2 >= -968)
} doubledouble;

// Make doubledouble from double
static doubledouble double_to_doubledouble(double value) 
{
    doubledouble result;
    
    result.hi = value;
    result.lo = 0;
    return result;
}

// Make double from doubledouble
static double doubledouble_to_double(const doubledouble value) 
{
    return value.hi;
}

// Check value is +Inf or -Inf
static int is_infinity(double value) 
{
    return (value == 1.0 / 0.0) || (value == -1.0 / 0.0);
}

// Add two Double1 value, condition: |A| >= |B|
// The "Fast2Sum" algorithm (Dekker 1971) [1]
static doubledouble doubledouble_fast_add11(double a, double b) 
{
    doubledouble result;
     
    result.hi = a + b;
    
    // infinity check
    if (is_infinity(result.hi)) {
        return double_to_doubledouble(result.hi);
    }
    
    result.lo = (b - (result.hi - a));
    return result;
}

// The "2Sum" algorithm [1]
static doubledouble doubledouble_add11(double a, double b) 
{
    doubledouble result; 
    double ah, bh;

    result.hi = a + b;

    // infinity check
    if (is_infinity(result.hi)) {
        return double_to_doubledouble(result.hi);
    }
    
    ah = result.hi - b;
    bh = result.hi - ah;
    
    result.lo = (a - ah) + (b - bh);
    return result;
}

// The "Veltkamp Split" algorithm [2] [3] [4]
// See "Splitting into Halflength Numbers" and ALGOL procedure "mul12" in Appendix in [2]
static doubledouble doubledouble_split1(double a) 
{
    // The Splitter should be chosen equal to 2^trunc(t - t / 2) + 1,
    // where t is the number of binary digits in the mantissa.
    const double splitter = 134217729.0;// = 2^(53 - 53 div 2) + 1 = 2^27 + 1
    // Just make sure we don't have an overflow for Splitter,
    // InfinitySplit is 2^(e - (t - t div 2))
    // where e is max exponent, t is number of binary digits.
    const double infinity_split = 6.69692879491417e+299;// = 2^(1023 - (53 - 53 div 2)) = 2^996
    // just multiply by the next lower power of two to get rid of the overflow
    // 2^(+/-)27 + 1 = 2^(+/-)28
    const double infinity_down = 3.7252902984619140625e-09;// = 2^-(27 + 1) = 2^-28
    const double infinity_up = 268435456.0;// = 2^(27 + 1) = 2^28
    
    doubledouble result; 
    double temp;

    if ((a > infinity_split) || (a < -infinity_split)) {
        // down
        a = a * infinity_down;
        // mul
        temp = splitter * a;
        result.hi = temp + (a - temp);
        result.lo = a - result.hi;
        // up
        result.hi = result.hi * infinity_up;
        result.lo = result.lo * infinity_up;
    } else {
        temp = splitter * a;
        result.hi = temp + (a - temp);
        result.lo = a - result.hi;
    }
    return result;
}

// Multiplication two Double1 value
// The "TWO-PRODUCT" algorithm [5]
static doubledouble doubledouble_mul11(double a, double b) 
{
    doubledouble result; 
    doubledouble a2, b2;
    double err1, err2, err3;
    
    result.hi = a * b;
    
    // infinity check
    if (is_infinity(result.hi)) {
        return double_to_doubledouble(result.hi);   
    } 

    a2 = doubledouble_split1(a);
    b2 = doubledouble_split1(b);

    err1 = result.hi - (a2.hi * b2.hi);
    err2 = err1 - (a2.lo * b2.hi);
    err3 = err2 - (a2.hi * b2.lo);
    
    result.lo = (a2.lo * b2.lo) - err3;
    //result.hi = temp;
    //result.lo = ((a2.hi * b2.hi - temp) + a2.hi * b2.lo + a2.lo * b2.hi) + a2.lo * b2.lo;
    return result;
}

// Multiplication Double2 by Double1
// The "DWTimesFP1" algorithm [1]
static doubledouble doubledouble_mul21(const doubledouble a, double b)
{
    doubledouble result;
    doubledouble c;

    c = doubledouble_mul11(a.hi, b);

    // infinity check
    if (is_infinity(c.hi)) {
        return double_to_doubledouble(c.hi);
    }

    result = doubledouble_fast_add11(c.hi, a.lo * b);
    result = doubledouble_fast_add11(result.hi, result.lo + c.lo);
    return result;
}

// Division Double2 by Double1
// The "DWDivFP2" algorithm [1]
static doubledouble doubledouble_div21(const doubledouble a, double b)
{
    doubledouble result;
    doubledouble p, d;
    
    result.hi = a.hi / b;
    
    // infinity check
    if (is_infinity(result.hi)) {
        return double_to_doubledouble(result.hi);
    }
    
    p = doubledouble_mul11(result.hi, b);
    
    d.hi = a.hi - p.hi;
    d.lo = d.hi - p.lo;
    
    result.lo = (d.lo + a.lo) / b;
    
    result = doubledouble_fast_add11(result.hi, result.lo);
    return result;
}

// Addition Double2 and Double1
// The DWPlusFP algorithm [1]
static doubledouble doubledouble_add21(const doubledouble a, double b) 
{
    doubledouble result;
    
    result = doubledouble_add11(a.hi, b);
    
    // infinity check
    if (is_infinity(result.hi)) {
        return double_to_doubledouble(result.hi);
    }
    
    result.lo = result.lo + a.lo;
    result = doubledouble_fast_add11(result.hi, result.lo);
    return result;
}

// ---

typedef struct 
{
    int count;
    long int exponent;
    int is_negative;
    unsigned char digits[17 * 2];// Max digits in Double value * 2
} fixed_decimal;
  
static int text_prefix_length(const char *text, const char *prefix) 
{
    int i;
    
    i = 0;
    while ((text[i] == prefix[i]) ||
        ((text[i] >= 'A') && (text[i] <= 'Z') && ((text[i] + 32) == prefix[i]))) {
            
        if (text[i] == '\0') {
            break;
        }
        i++;
    }
    
    return i;
}

static int read_special(double *number, const char *text, char **text_end)
{
    char *p;
    int is_negative;
    int len;
    
    // clean
    is_negative = 0;
    
    // read from start
    p = (char*)text;
    
    // read sign
    switch (*p) {  
    case '+':
        p++;
        break;
    case '-':
        is_negative = 1;
        p++;
        break;
    }

    // special
    switch (*p) {
    case 'I':
    case 'i':
        len = text_prefix_length(p, "infinity");
        if ((len == 3) || (len == 8)) {
            *number = 1.0 / 0.0;
            if (is_negative) {
                *number = -*number;
            }
            p = p + len;
            *text_end = p;
            return 1;
        }
        break;
    case 'N':
    case 'n':
        len = text_prefix_length(p, "nan");
        if (len == 3) {
            *number = -(0.0 / 0.0);
            if (is_negative) {
                *number = -*number;
            }
            p = p + len;
            *text_end = p;
            return 1;
        }
        break;
    }

    // fail
    *text_end = (char*)text;
    return 0;
}

int read_text_to_fixed_decimal(fixed_decimal *decimal, const char *text, char **text_end)
{
    const long int clip_exponent = 1000000;
    
    char *p, *p_start_exponent;
    int has_point, has_digit;
    int exponent_sign;
    long int exponent;
    
    // clean
    decimal->count = 0;
    decimal->is_negative = 0;
    decimal->exponent = -1;
    
    // read from start
    p = (char*)text;

    // read sign
    switch (*p) {
    case '+':
        p++;
        break;
    case '-':
        decimal->is_negative = 1;
        p++;
        break;
    }

    // read mantissa
    has_digit = 0;// has read any digit (0..9)
    has_point = 0;// has read decimal point
	while (*p != '\0') {
		switch (*p) {
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
            if ((decimal->count != 0) || (*p != '0')) {
                // save digit
                if (decimal->count < (sizeof(decimal->digits) / sizeof(decimal->digits[0]))) {
                    decimal->digits[decimal->count] = *p - '0';
                    decimal->count++;
                }
                // inc exponenta
                if ((!has_point) && (decimal->exponent < clip_exponent)) {
                    decimal->exponent++;
                }
            } else {
                // skip zero (dec exponenta)
                if (has_point && (decimal->exponent > -clip_exponent)) {
                    decimal->exponent--;
                }
            }
            has_digit = 1;
            break;
        case '.': 
            if (has_point) {
                *text_end = p; 
                return 1;// make
            }
            has_point = 1;
			break;
		default:
			goto end_read_mantissa;
		}
        p++;
	} 

end_read_mantissa:

    if (!has_digit) {
        *text_end = (char*)text;
        return 0;// fail
    }

    // read exponenta
    if ((*p == 'e') || (*p == 'E')) {
        p_start_exponent = p;
        p++;
    
        exponent = 0;
        exponent_sign = 1;
    
        // check sign
        switch (*p) {
        case '+':
            p++;
            break;
        case '-':
            exponent_sign = -1;
            p++;
            break;
        }
    
        // read
        if ((*p >= '0') && (*p <= '9')) {
            while ((*p >= '0') && (*p <= '9')) {
                exponent = exponent * 10 + (*p - '0');
                if (exponent > clip_exponent) {
                    exponent = clip_exponent;
                }
                p++;
            }
        } else {
            *text_end = p_start_exponent;// revert
            return 1;// Make
        }
    
        // fix
        decimal->exponent = decimal->exponent + exponent_sign * exponent;
    }

    *text_end = p;
    return 1;// Make
}

double fixed_decimal_to_double(fixed_decimal *decimal)
{
    const int last_accuracy_exponent_10 = 22;// for Double
    const double last_accuracy_power_10 = 1e22;// for Double
    const long long int max_safe_int = 9007199254740991;// (2^53−1) for Double
    const long long max_safe_hi = (max_safe_int - 9) / 10;// for X * 10 + 9
    const double power_of_10[] = {
        1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
        1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
    };
    
    double result;
    int i;
    doubledouble number;
    long int exponent;

    number = double_to_doubledouble(0.0);

    // set mantissa
    for (i = 0; i < decimal->count; i++) {
        if (number.hi <= max_safe_hi) {
            number.hi = number.hi * 10;// * 10
            number.hi = number.hi + decimal->digits[i];// + Digit
        } else {
            number = doubledouble_mul21(number, 10.0);// * 10
            number = doubledouble_add21(number, decimal->digits[i]);// + Digit
        }
    }

    // set exponent
    exponent = decimal->exponent - decimal->count + 1;

    // positive exponent
    while (exponent > 0) {
        if (exponent > last_accuracy_exponent_10) {
            // * e22
            number = doubledouble_mul21(number, last_accuracy_power_10);
            // overflow break
            if (is_infinity(doubledouble_to_double(number))) {
                break;
            }
            exponent = exponent - last_accuracy_exponent_10;
        } else {
            // * eX
            number = doubledouble_mul21(number, power_of_10[exponent]);
            break;
        }
    }

    // negative exponent
    while (exponent < 0) {
        if (exponent < -last_accuracy_exponent_10) {
            // / e22
            number = doubledouble_div21(number, last_accuracy_power_10);
            // underflow break
            if (doubledouble_to_double(number) == 0.0) {
                break;
            }
            exponent = exponent + last_accuracy_exponent_10;
        } else {
            // / eX
            number = doubledouble_div21(number, power_of_10[-exponent]);
            break;
        }
    }

    // make result
    result = doubledouble_to_double(number);

    // fix sign
    if (decimal->is_negative) {
        result = -result;
    }
    return result;
}

// ---

// -------------------------------------------------------------------------------------------------
// ParseFloat parse chars with float point pattern to Double and stored to Value param.
// If no chars match the pattern then Value is unmodified, else the chars convert to
// float point value which will be is stored in Value.
// On success, EndPtr points at the first char not matching the float point pattern.
// If there is no pattern match, EndPtr equals with TextPtr.
//
// If successful function return 1 else 0.
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
// Text,      TextEnd,    Value = 1984,        Result = True
//
//
//   "+123.45e-22 abc\0"  -- read to end of float number
//    ^          ^
// Text,       TextEnd,   Value = 123.45e-22,  Result = True
//
//
//   "aboba\0"            -- invalid float point
//    ^----------
// Text,       TextEnd,   Value = dont change, Result = False
//
//
//   "AAA.99\0"           -- read with leading dot notation
//    ---^  ^-----
// Text,       TextEnd,   Value = 0.99,        Result = True
//
//
//   "500e\0"             -- read correct part of input
//    ^  ^--------
// Text,       TextEnd,   Value = 500,         Result = True
//
// -------------------------------------------------------------------------------------------------

int parse_float(const char *text, double *value, char **text_end)
{
    fixed_decimal decimal;
    char *dummy; 
  
    if (!text_end) {
        text_end = &dummy;
    }

    // Try read inf/nan
    if (read_special(value, text, text_end)) {
        // Read done
        return 1;
    }

    // Try read number
    if (read_text_to_fixed_decimal(&decimal, text, text_end)) {
        // Convert Decimal to Double
        *value = fixed_decimal_to_double(&decimal);
    
        // Read done
        return 1;
    }

    // Fail
    return 0;
}