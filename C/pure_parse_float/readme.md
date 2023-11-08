Before using the parser, make sure to set the FPU precision to "double" and the rounding mode to "nearest".  
When using GCC on x86, make sure to use the -ffloat-store option, otherwise GCC will generate incorrect code: https://gcc.gnu.org/wiki/FloatingPointMath
