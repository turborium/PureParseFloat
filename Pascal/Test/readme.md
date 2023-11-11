### Pure Parse Float Test App

**Params:**  
```-c``` - Enable "C" version of "pure" parser in pure_parse_float_c_32/64.dll, disabled by default  
```-parser <pure|delphi|microsoft>``` - Select parser for test, ```pure``` by default  
```-size <small|medium|large>``` - Select count of test cases, ```small``` by default  
```-benchmark``` - Run benchmark, you can add bench "C" version with use ```-c``` param  

```-dll <dll name>``` - Test your DLL  
```-function <function name>``` - Chose ParseFloat function from DLL  
  (The function MUST corresponds to standart DLL Pascal/C FFI interface - see C version)

For this application to work, two DLLs IeeeConvert64.dll and IeeeConvert32.dll are required, they provide reference values.  
This DLLs are already included in this repository, but you can build them yourself: https://github.com/turborium/IeeeConvertDynamicLibrary  

To check the "C" version of the parser you need to build pure_parse_float_c_32.dll and pure_parse_float_c_64.dll. 

**For example:**  
Check:```Test.32.exe -size medium -parser pure```  
Benchmark:```Test.32.exe -benchmark```  
Benchmark with C version:```Test.32.exe -benchmark -c```   

To check your DLL place DLL and set ```-dll``` and ```-name``` params.  
**For example:**  
Check *rust32.dll*: ```Test.32.exe -size medium -dll rust32.dll -function parse_float```  
Check *rust64.dll*: ```Test.64.exe -size medium -dll rust64.dll -function parse_float```  
Benchmark *rust32.dll*: ```Test.32.exe -benchmark -dll rust32.dll -function parse_float```  
Benchmark *rust64.dll*: ```Test.64.exe -benchmark -dll rust64.dll -function parse_float```  

