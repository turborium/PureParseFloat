#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "..\pure_parse_float\pure_parse_float.h"

uint32_t test_rand_seed = 0;

void set_test_seed(const uint32_t seed)
{
    test_rand_seed = seed;
}

int32_t test_random(const int32_t max)
{
    int32_t result;
    result = (int32_t)test_rand_seed * 0x08088405 + 1;
    test_rand_seed = result;
    result = ((uint64_t)((uint32_t)max) * (uint64_t)((uint32_t)result)) >> 32;
}

typedef union {
    double value;
    uint16_t array[4];
    int64_t bin;
} number;

int main(int argc, char *argv[]) 
{
    const int test_count = 1000000;
    int i;
    int one_ulp_error_count;
    int fatal_error_count;
    number source, a, b;
    char *a_end, *b_end;
    char buffer[200];
    
    printf("Testing, please wait...\n");
    
    set_test_seed(404);
    one_ulp_error_count = 0;
    fatal_error_count = 0;
    for (i = 0; i < test_count; i++) {
        // make
        source.array[0] = test_random(0xFFFF + 1);
        source.array[1] = test_random(0xFFFF + 1);
        source.array[2] = test_random(0xFFFF + 1);
        source.array[3] = test_random(0xFFFF + 1);
        if (test_random(2) == 0) {
            sprintf(buffer, "%.15lg\n", source.value);
        } else {
            sprintf(buffer, "%lg\n", source.value);
        }
      
        // convert
        a.value = 0.0;
        parse_float(buffer, &(a.value), &a_end);
        b.value = strtod(buffer, &b_end);

        // reading count
        if (a_end != b_end) {
            fatal_error_count++;
            continue;
        }
  
        // ulp fail
        if (a.bin != b.bin) {
            if ((a.bin + 1 != b.bin) && (a.bin - 1 != b.bin)) {
                fatal_error_count++;
                continue;         
            }
            one_ulp_error_count++;
        }
    }
    
    if (fatal_error_count == 0) {
        printf("Tests OK\n"); 
    } else {
        printf("Tests FAIL\n");      
    }

    printf("Test count: %i\n", test_count);    
    printf("Fatal error count: %i\n", fatal_error_count);
    printf("One ulp error count: %i (%.3f%%)\n", one_ulp_error_count, 100.0 * ((double)one_ulp_error_count / (double)test_count));
        
    return 0;
}