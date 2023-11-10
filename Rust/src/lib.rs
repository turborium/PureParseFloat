use std::ffi::{c_int, c_char, c_double};

// Check value is +Inf or -Inf
fn is_infinity(value: f64) -> bool {
    value == f64::INFINITY || value == -f64::NEG_INFINITY
}

// 31 digits garantee, with (exp^10 >= -291) or (exp^2 >= -968)
#[derive(Clone, Copy)]
struct DoubleDouble {
    hi: f64,
    lo: f64,
}

impl Into<DoubleDouble> for f64 {
    fn into(self) -> DoubleDouble {
        DoubleDouble{
            hi: self,
            lo: 0.0,
        }
    }
}

impl From<DoubleDouble> for f64 {
    fn from(value: DoubleDouble) -> Self {
        value.hi
    }
}

impl DoubleDouble {
    // Add two Double1 value, condition: |A| >= |B|
    // The "Fast2Sum" algorithm (Dekker 1971) [1]
    fn fast_add11(a: f64, b: f64) -> Self {
        let hi = a + b;

        // infinity check
        if is_infinity(hi) {
            return hi.into();
        }

        Self{
            hi,
            lo: b - (hi - a),
        }
    }

    // The "2Sum" algorithm [1]
    fn add11(a: f64, b: f64) -> Self {
        let hi = a + b;

        // infinity check
        if is_infinity(hi) {
            return hi.into();
        }

        let ah = hi - b;
        let bh = hi - ah;

        Self{
            hi: hi,
            lo: (a - ah) + (b - bh),
        }
    }

    // The "Veltkamp Split" algorithm [2] [3] [4]
    // See "Splitting into Halflength Numbers" and ALGOL procedure "mul12" in Appendix in [2]
    fn split1(a: f64) -> Self {
        // The Splitter should be chosen equal to 2^trunc(t - t / 2) + 1,
        // where t is the number of binary digits in the mantissa.
        const SPLITTER: f64 = 134217729.0;// = 2^(53 - 53 div 2) + 1 = 2^27 + 1
        // Just make sure we don't have an overflow for Splitter,
        // InfinitySplit is 2^(e - (t - t div 2))
        // where e is max exponent, t is number of binary digits.
        const INFINITY_SPLIT: f64 = 6.69692879491417e+299;// = 2^(1023 - (53 - 53 div 2)) = 2^996
        // just multiply by the next lower power of two to get rid of the overflow
        // 2^(+/-)27 + 1 = 2^(+/-)28
        const INFINITY_DOWN: f64 = 3.7252902984619140625e-09;// = 2^-(27 + 1) = 2^-28
        const INFINITY_UP: f64 = 268435456.0;// = 2^(27 + 1) = 2^28

        if a > INFINITY_SPLIT || a < -INFINITY_SPLIT {
            // down
            let a = a * INFINITY_DOWN;
            // mul
            let temp = SPLITTER * a;
            let hi = temp + (a - temp);
            let lo = a - hi;
            // up
            return Self{
                hi: hi * INFINITY_UP,
                lo: lo * INFINITY_UP,
            };
        }

        let temp = SPLITTER * a;
        let hi = temp + (a - temp);
        Self{
            hi: hi,
            lo: a - hi,
        }
    }

    // Multiplication two Double1 value
    // The "TWO-PRODUCT" algorithm [5]
    fn mul11(a: f64, b: f64) -> Self {
        let hi = a * b;

        // infinity check
        if is_infinity(hi) {
            return hi.into();
        }

        let a2 = Self::split1(a);
        let b2 = Self::split1(b);

        let err1 = hi - a2.hi * b2.hi;
        let err2 = err1 - a2.lo * b2.hi;
        let err3 = err2 - a2.hi * b2.lo;

        Self{
            hi: hi,
            lo: a2.lo * b2.lo - err3,
        }
    }

    // Multiplication Double2 by Double1
    // The "DWTimesFP1" algorithm [1]
    fn mul21(a: Self, b: f64) -> Self {
        let c = Self::mul11(a.hi, b);

        // infinity check
        if is_infinity(c.hi) {
            return c.hi.into();
        }

        let result = Self::fast_add11(c.hi, a.lo * b);
        Self::fast_add11(result.hi, result.lo + c.lo)
    }

    // Division Double2 by Double1
    // The "DWDivFP2" algorithm [1]
    fn div21(a: Self, b: f64) -> Self {
        let hi = a.hi / b;

        // infinity check
        if is_infinity(hi) {
            return hi.into();
        }

        let p = Self::mul11(hi, b);

        let dhi = a.hi - p.hi;
        let d = Self{
            hi: dhi,
            lo: dhi - p.lo,
        };

        let result = Self{
            hi: hi,
            lo: (d.lo + a.lo) / b,
        };

        return Self::fast_add11(result.hi, result.lo);
    }

    // Addition Double2 and Double1
    // The DWPlusFP algorithm [1]
    fn add21(a: Self, b: f64) -> Self {
        let mut result = Self::add11(a.hi, b);

        // infinity check
        if is_infinity(result.hi) {
            return result.hi.into();
        }

        result.lo = result.lo + a.lo;
        Self::fast_add11(result.hi, result.lo)
    }
}


// ---

const FIXED_DECIMAL_DIGITS: usize = 17 * 2;
struct FixedDecimal {
    count: isize,
    exponent: isize,
    is_negative: bool,
    digits: [u8; FIXED_DECIMAL_DIGITS], // Max digits in Double value * 2
}

unsafe fn text_prefix_length(text: *const u8, prefix: *const u8) -> isize {
    let mut i: isize = 0;
    while {
        let texti = *text.offset(i);
        let prefixi = *prefix.offset(i);
        texti == prefixi || texti >= b'A' && texti <= b'Z' && texti + 32 == prefixi
    } {
        if *text.offset(i) == b'\0' {
            break;
        }
        i += 1;
    }
    return i;
}

unsafe fn read_special(text: *const u8) -> Result<(f64, *const u8), ()> {
    // clean
    let mut is_negative: bool = false;

    // read from start
    let mut p: *const u8 = text;

    // read sign
    match *p {
    b'+' => p = p.offset(1),
    b'-' => {
        is_negative = true;
        p = p.offset(1);
    },
    _ => {},
    }

    // special
    match *p {
    b'I' | b'i' => {
        let len = text_prefix_length(p, "infinity".as_ptr());
        if len == 3 || len == 8 {
            let mut res = f64::INFINITY;
            if is_negative {
                res = -res;
            }
            return Ok((res, p.offset(len)));
        }
    }
    b'N' | b'n' => {
        let len = text_prefix_length(p, "nan".as_ptr());
        if len == 3 {
            let mut res = f64::NAN;
            if is_negative {
                res = -res;
            }
            return Ok((res, p.offset(len)));
        }
    }
    _ => {},
    }

    Err(())
}

unsafe fn read_text_to_fixed_decimal(text: *const u8) -> Result<(FixedDecimal, *const u8), ()> {
    const CLIP_EXPONENT: isize = 1000000;

    // clean
    let mut decimal = FixedDecimal{
        count: 0,
        digits: [0; FIXED_DECIMAL_DIGITS],
        exponent: -1,
        is_negative: false,
    };

    // read from start
    let mut p: *const u8 = text;

    // read sign
    match *p {
    b'+' => p = p.offset(1),
    b'-' => {
        decimal.is_negative = true;
        p = p.offset(1);
    },
    _ => {},
    }

    // read mantissa
    let mut has_digit = false; // has read any digit (0..9)
    let mut has_point = false; // has read decimal point
	'end_read_mantissa: while *p != b'\0' {
		match *p {
        b'0' | b'1' | b'2' | b'3' | b'4' | b'5' | b'6' | b'7' | b'8' | b'9' => {
            if decimal.count != 0 || *p != b'0' {
                // save digit
                if decimal.count < FIXED_DECIMAL_DIGITS as isize {
                    decimal.digits[decimal.count as usize] = *p - b'0';
                    decimal.count += 1;
                }
                // inc exponenta
                if !has_point && decimal.exponent < CLIP_EXPONENT {
                    decimal.exponent += 1;
                }
            } else {
                // skip zero (dec exponenta)
                if has_point && (decimal.exponent > -CLIP_EXPONENT) {
                    decimal.exponent -= 1;
                }
            }
            has_digit = true;
        },
        b'.' => {
            if has_point {
                return Ok((decimal, p)); // make
            }
            has_point = true;
        },
        _ => {
			break 'end_read_mantissa;
        },
		}
        p = p.offset(1);
	}

    if !has_digit {
        return Err(());
    }

    // read exponenta
    if *p == b'e' || *p == b'E' {
        let p_start_exponent = p;
        p = p.offset(1);

        let mut exponent: isize = 0;
        let mut exponent_sign: isize = 1;

        // check sign
        match *p {
        b'+' => p = p.offset(1),
        b'-' => {
            exponent_sign = -1;
            p = p.offset(1);
        },
        _ => {},
        }

        // read
        if *p >= b'0' && *p <= b'9' {
            while *p >= b'0' && *p <= b'9' {
                exponent = exponent * 10 + (*p - b'0') as isize;
                if exponent > CLIP_EXPONENT {
                    exponent = CLIP_EXPONENT;
                }
                p = p.offset(1);
            }
        } else {
            return Ok((decimal, p_start_exponent)); // Make
        }

        // fix
        decimal.exponent = decimal.exponent + exponent_sign * exponent;
    }

    Ok((decimal, p)) // Make
}

fn fixed_decimal_to_double(decimal: &FixedDecimal) -> f64 {
    const LAST_ACCURACY_EXPONENT_10: isize = 22; // for Double
    const LAST_ACCURACY_POWER_10: f64 = 1e22; // for Double
    const MAX_SAFE_INT: f64 = 9007199254740991.0; // (2^53−1) for Double
    const MAX_SAFE_HI: f64 = (MAX_SAFE_INT - 9.) / 10.; // for X * 10 + 9
    const POWER_OF_10: [f64; 1+LAST_ACCURACY_EXPONENT_10 as usize] = [
        1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
        1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
    ];

    let mut result: f64;
    let mut number: DoubleDouble;

    number = 0.0.into();

    // set mantissa
    for i in 0..decimal.count as usize {
        if number.hi <= MAX_SAFE_HI {
            number.hi = number.hi * 10.0;
            number.hi = number.hi + decimal.digits[i] as f64; // + Digit
        } else {
            number = DoubleDouble::mul21(number, 10.0); // * 10
            number = DoubleDouble::add21(number, decimal.digits[i] as f64); // + Digit
        }
    };

    // set exponent
    let mut exponent = decimal.exponent - decimal.count + 1;

    // positive exponent
    while exponent > 0 {
        if exponent > LAST_ACCURACY_EXPONENT_10 {
            // * e22
            number = DoubleDouble::mul21(number, LAST_ACCURACY_POWER_10);
            // overflow break
            if is_infinity(number.into()) {
                break;
            }
            exponent = exponent - LAST_ACCURACY_EXPONENT_10;
        } else {
            // * eX
            number = DoubleDouble::mul21(number, POWER_OF_10[exponent as usize]);
            break;
        }
    }

    // negative exponent
    while exponent < 0 {
        if exponent < -LAST_ACCURACY_EXPONENT_10 {
            // / e22
            number = DoubleDouble::div21(number, LAST_ACCURACY_POWER_10);
            // underflow break
            if <DoubleDouble as Into<f64>>::into(number) == 0.0 {
                break;
            }
            exponent = exponent + LAST_ACCURACY_EXPONENT_10;
        } else {
            // / eX
            number = DoubleDouble::div21(number, POWER_OF_10[-exponent as usize]);
            break;
        }
    }

    // make result
    result = number.into();

    // fix sign
    if decimal.is_negative {
        result = -result;
    }
    return result;
}


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
unsafe fn parse_float_impl(text: *const u8) -> Result<(f64, *const u8), ()> {
    // Try read inf/nan
    read_special(text)
        .or_else(|_| {
            // Try read number
            read_text_to_fixed_decimal(text)
                // Convert Decimal to Double
                .map(|(decimal, text_end)|
                    (fixed_decimal_to_double(&decimal), text_end))
        })
}

#[no_mangle]
unsafe extern fn parse_float(text: *const c_char, value: *mut c_double, text_end: *mut *const c_char) -> c_int {
    match parse_float_impl(text as *const u8) {
    Ok((res, end)) => {
        *value = res;
        *text_end = end as *const c_char;
        1
    },
    Err(_) => {
        0
    },
    }
}

#[cfg(test)]
mod tests {
    use crate::parse_float_impl;

    #[test]
    fn pi() {
        let (result, _) = unsafe { parse_float_impl("3.14159265".as_ptr()).unwrap() };
        assert_eq!(result, 3.14159265);
    }

    #[test]
    fn exponent() {
        let (result, _) = unsafe { parse_float_impl("-1234e10".as_ptr()).unwrap() };
        assert_eq!(result, -1234e10);
    }

    #[test]
    fn nan() {
        let (result, _) = unsafe { parse_float_impl("nan".as_ptr()).unwrap() };
        assert!(f64::is_nan(result));
    }

    #[test]
    fn minus_nan() {
        let (result, _) = unsafe { parse_float_impl("-nan".as_ptr()).unwrap() };
        assert!(f64::is_nan(result));
    }
}
