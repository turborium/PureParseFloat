use std::ffi::{c_int, c_char, c_double};

// Safe wrapper for null terminated string
#[derive(Clone)]
struct Reader(*const u8, usize);

impl Reader {
    fn from_raw_ptr(text: *const u8) -> Self {
        Reader(text, 0)
    }

    #[allow(dead_code)]
    fn from_str(text: &str) -> Self {
        Reader(text.as_ptr(), 0)
    }

    fn get(&self) -> u8 {
        unsafe { *self.0.add(self.1) }
    }

    // before using, make sure Reader is not ended
    fn advance(&mut self) {
        self.1 += 1;
    }

    fn ended(&self) -> bool {
        self.get() == 0
    }
}

// 31 digits garantee, with (exp^10 >= -291) or (exp^2 >= -968)
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

impl std::ops::Add<f64> for DoubleDouble {
    type Output = Self;

    // The DWPlusFP algorithm [1]
    fn add(self, rhs: f64) -> Self::Output {
        let result = Self::add(self.hi, rhs);
        Self::fast_add(result.hi, result.lo + self.lo)
    }
}

impl std::ops::Mul<f64> for &DoubleDouble {
    type Output = DoubleDouble;

    // The "DWTimesFP1" algorithm [1]
    fn mul(self, rhs: f64) -> Self::Output {
        let c = DoubleDouble::mul(self.hi, rhs);

        let result = DoubleDouble::fast_add(c.hi, self.lo * rhs);
        DoubleDouble::fast_add(result.hi, result.lo + c.lo)
    }
}

impl std::ops::MulAssign<f64> for DoubleDouble {
    fn mul_assign(&mut self, rhs: f64) {
        *self = &*self * rhs;
    }
}

impl std::ops::Div<f64> for &DoubleDouble {
    type Output = DoubleDouble;

    // The "DWDivFP2" algorithm [1]
    fn div(self, rhs: f64) -> Self::Output {
        let hi = self.hi / rhs;

        let p = DoubleDouble::mul(hi, rhs);

        let dhi = self.hi - p.hi;
        let d = DoubleDouble{
            hi: dhi,
            lo: dhi - p.lo,
        };

        let result = DoubleDouble{
            hi,
            lo: (d.lo + self.lo) / rhs,
        };

        return DoubleDouble::fast_add(result.hi, result.lo);
    }
}

impl std::ops::DivAssign<f64> for DoubleDouble {
    fn div_assign(&mut self, rhs: f64) {
        *self = &*self / rhs;
    }
}

impl DoubleDouble {
    // Add two f64 values, condition: |A| >= |B|
    // The "Fast2Sum" algorithm (Dekker 1971) [1]
    fn fast_add(a: f64, b: f64) -> Self {
        let hi = a + b;

        Self{
            hi,
            lo: b - (hi - a),
        }
    }

    // The "2Sum" algorithm [1]
    fn add(a: f64, b: f64) -> Self {
        let hi = a + b;

        let ah = hi - b;
        let bh = hi - ah;

        Self{
            hi,
            lo: (a - ah) + (b - bh),
        }
    }

    // Multiply two f64 values
    // The "TWO-PRODUCT" algorithm [5]
    fn mul(a: f64, b: f64) -> Self {
        let hi = a * b;

        Self{
            hi,
            lo: a.mul_add(b, -hi),
        }
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

impl Into<f64> for &FixedDecimal {
    fn into(self) -> f64 {
        const LAST_ACCURACY_EXPONENT_10: isize = 22; // for Double
        const LAST_ACCURACY_POWER_10: f64 = 1e22; // for Double
        const MAX_SAFE_INT: f64 = 9007199254740991.0; // (2^53−1) for Double
        const MAX_SAFE_HI: f64 = (MAX_SAFE_INT - 9.) / 10.; // for X * 10 + 9
        const POWER_OF_10: [f64; 1+LAST_ACCURACY_EXPONENT_10 as usize] = [
            1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
            1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
        ];

        let mut number: DoubleDouble = 0.0.into();
        // set mantissa
        for &digit in &self.digits[..self.count as usize] {
            if number.hi <= MAX_SAFE_HI {
                number.hi = number.hi * 10.0 + digit as f64;
            } else {
                number = &number * 10.0 + digit as f64;
            }
        };

        let mut exponent = self.exponent - self.count + 1;
        match exponent {
        _ if exponent > 0 => {
            while exponent > LAST_ACCURACY_EXPONENT_10 {
                number *= LAST_ACCURACY_POWER_10; // * e22
                // overflow break
                if number.hi.is_infinite() {
                    break;
                }
                exponent -= LAST_ACCURACY_EXPONENT_10;
            }
            number *= POWER_OF_10[exponent as usize]; // * eX
        }
        _ if exponent < 0 => {
            while exponent < -LAST_ACCURACY_EXPONENT_10 {
                number /= LAST_ACCURACY_POWER_10; // / e22
                // underflow break
                if number.hi == 0.0 {
                    break;
                }
                exponent += LAST_ACCURACY_EXPONENT_10;
            }
            number /= POWER_OF_10[-exponent as usize]; // / eX
        }
        _ => {}
        }

        if self.is_negative { -number.hi } else { number.hi }
    }
}

fn read_inf_or_nan(mut p: Reader) -> Option<(f64, usize)> {
    fn common_prefix_length(mut text: Reader, prefix: &[u8]) -> usize {
        let mut i: usize = 0;
        for &c in prefix {
            if text.ended() || text.get().to_ascii_lowercase() != c {
                break;
            }
            i += 1;
            text.advance();
        }
        return i;
    }

    let is_negative = match p.get() {
        b'+' => { p.advance(); false }
        b'-' => { p.advance(); true }
        _ => false
    };

    match p.get() {
    b'I' | b'i' => {
        let len = common_prefix_length(p.clone(), "infinity".as_bytes());
        if len == 3 || len == 8 {
            let res = if is_negative { f64::NEG_INFINITY } else { f64::INFINITY };
            return Some((res, p.1 + len));
        }
    }
    b'N' | b'n' => {
        let len = common_prefix_length(p.clone(), "nan".as_bytes());
        if len == 3 {
            let res = if is_negative { -f64::NAN } else { f64::NAN };
            return Some((res, p.1 + len ));
        }
    }
    _ => {},
    }

    None
}

fn read_fixed_decimal(mut p: Reader) -> Option<(FixedDecimal, usize)> {
    const CLIP_EXPONENT: isize = 1000000;

    // read sign
    let is_negative = match p.get() {
        b'+' => { p.advance(); false }
        b'-' => { p.advance(); true },
        _ => false,
    };

    let mut decimal = FixedDecimal{
        count: 0,
        digits: [0; FIXED_DECIMAL_DIGITS],
        exponent: -1,
        is_negative,
    };

    // read mantissa
    let mut has_digit = false; // has read any digit (0..9)
    let mut has_point = false; // has read decimal point
    'read_mantissa_loop: while !p.ended() {
        match p.get() {
        b'0'..=b'9' => {
            if decimal.count != 0 || p.get() != b'0' {
                // save digit
                if decimal.count < FIXED_DECIMAL_DIGITS as isize {
                    decimal.digits[decimal.count as usize] = p.get() - b'0';
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
                return Some((decimal, p.1));
            }
            has_point = true;
        },
        _ => {
            break 'read_mantissa_loop;
        },
        }
        p.advance();
    }

    if !has_digit {
        return None;
    }

    // read exponenta
    if matches!(p.get(), b'e' | b'E') {
        let p_start_exponent = p.1;
        p.advance();

        let mut exponent: isize = 0;
        let exponent_sign: isize = match p.get() {
            b'+' => { p.advance(); 1 },
            b'-' => { p.advance(); -1 },
            _ => 1,
        };

        // read
        if matches!(p.get(), b'0'..=b'9') {
            while matches!(p.get(), b'0'..=b'9') {
                exponent = (exponent * 10 + (p.get() - b'0') as isize).min(CLIP_EXPONENT);
                p.advance();
            }
        } else {
            return Some((decimal, p_start_exponent));
        }

        // fix
        decimal.exponent = decimal.exponent + exponent_sign * exponent;
    }

    Some((decimal, p.1))
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
fn parse_float_impl(text: Reader) -> Option<(f64, usize)> {
    if let res@Some(_) = read_inf_or_nan(text.clone()) {
        return res
    } else if let Some((decimal, count)) = read_fixed_decimal(text) {
        Some(((&decimal).into(), count))
    } else {
        None
    }
}

#[no_mangle]
unsafe extern fn parse_float(text: *const c_char, value: *mut c_double, text_end: *mut *const c_char) -> c_int {
    match parse_float_impl(Reader::from_raw_ptr(text as *const u8)) {
    Some((res, end)) => {
        *value = res;
        *text_end = text.add(end);
        1
    }
    None => 0
    }
}

#[cfg(test)]
mod tests {
    use crate::{parse_float_impl, Reader};

    #[test]
    fn pi() {
        let (result, _) = parse_float_impl(Reader::from_str("3.14159265")).unwrap();
        assert_eq!(result, 3.14159265);
    }

    #[test]
    fn exponent() {
        let (result, _) = parse_float_impl(Reader::from_str("-1234e10")).unwrap();
        assert_eq!(result, -1234e10);
    }

    #[test]
    fn nan() {
        let (result, _) = parse_float_impl(Reader::from_str("nan")).unwrap();
        assert!(f64::is_nan(result));
    }

    #[test]
    fn minus_nan() {
        let (result, _) = parse_float_impl(Reader::from_str("-nan")).unwrap();
        assert!(f64::is_nan(result));
    }

    #[test]
    fn minus_nan_uppercase() {
        let (result, _) = parse_float_impl(Reader::from_str("-NaN")).unwrap();
        assert!(f64::is_nan(result));
    }
}
