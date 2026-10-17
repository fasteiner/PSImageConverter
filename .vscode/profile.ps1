./build.ps1 -tasks minibuild
$version = dotnet-gitversion /showvariable MajorMinorPatch /nocache
$ModuleFile = ".\output\module\PSImageConverter\$version\PSImageConverter.psd1"
Import-Module $ModuleFile
