/* Replace "dll.h" with the name of your header */
#include "dll.h"
#include <windows.h>
#include "..\..\pure_parse_float\pure_parse_float.h"

DLLIMPORT bool pure_parse_float(const char *text, double *value, char **text_end)
{
    return parse_float(text, value, text_end);
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL,DWORD fdwReason,LPVOID lpvReserved)
{
	/* Return TRUE on success, FALSE on failure */
	return TRUE;
}
