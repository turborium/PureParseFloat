### Pure Parse Float Test App

**Params:**  
```-c``` - Enable "C" version of "pure" parser in pure_parse_float_c_32/64.dll, disabled by default  
```-parser <pure|delphi|microsoft>``` - Select parser for test, ```pure``` by default  
```-size <small|medium|large>``` - Select count of test cases, ```small``` by default  
```-benchmark``` - Run benchmark, you can add bench "C" version with use ```-c``` param  

For this application to work, two DLLs IeeeConvert64.dll and IeeeConvert32.dll are required, they provide reference values.  
This DLLs are already included in this repository, but you can build them yourself: https://github.com/turborium/IeeeConvertDynamicLibrary  

To check the "C" version of the parser you need to build pure_parse_float_c_32.dll and pure_parse_float_c_64.dll.
