./build.ps1 -tasks minibuild
$version = dotnet-gitversion /showvariable MajorMinorPatch /nocache
$ModuleFile = ".\output\module\PSHeic\$version\PSHeic.psd1"
Import-Module $ModuleFile
