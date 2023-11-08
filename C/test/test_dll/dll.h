#ifndef _DLL_H_
#define _DLL_H_

#include <stdbool.h>

#if BUILDING_DLL
#define DLLIMPORT __declspec(dllexport)
#else
#define DLLIMPORT __declspec(dllimport)
#endif

DLLIMPORT bool pure_parse_float(const char *text, double *value, char **text_end);

#endif
