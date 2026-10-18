
# Load the helper assembly and the bundled Magick.NET library when the module is imported.
Initialize-ImageConverterAssembly -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
