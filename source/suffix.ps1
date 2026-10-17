
# Load the bundled Magick.NET library when the module is imported.
Initialize-ImageConverterMagickNet -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
