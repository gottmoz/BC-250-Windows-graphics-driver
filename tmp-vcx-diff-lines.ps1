$patterns = 'WindowsTargetPlatformVersion|PlatformToolset|AdditionalIncludeDirectories|AdditionalLibraryDirectories|Driver|TargetVersion|NTDDI|_WIN32_WINNT|ConfigurationType|Spectre|ControlFlowGuard|BufferSecurityCheck|WholeProgramOptimization|EntryPointSymbol|SubSystem'
'=== BC250 vcxproj ==='
Select-String -Path 'C:\Dev\BC250-windowsDriverTest\amdbc250kmd.vcxproj' -Pattern $patterns | ForEach-Object { $_.Line }
''
'=== KMDOD vcxproj ==='
Select-String -Path 'C:\Dev\windows-driver-samples\video\KMDOD\Sample\SampleDisplay.vcxproj' -Pattern $patterns | ForEach-Object { $_.Line }
