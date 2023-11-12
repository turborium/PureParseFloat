# Float Parser on .NET with NativeAOT Unsafe Version

- Install **.NET 7** or **8** [from here](https://dotnet.microsoft.com/en-us/download)

- Build project

```bash
dotnet publish -f net7.0 -c Release -r win-x64 -p:PublishAot=true -p:NativeLib=Shared -p:SelfContained=true
```

