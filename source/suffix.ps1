
# Load the bundled Magick.NET library when the module is imported.
Initialize-PSHeicMagickNet -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
