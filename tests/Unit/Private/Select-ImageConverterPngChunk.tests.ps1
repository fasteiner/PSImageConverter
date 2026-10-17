BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    function Select-Chunk
    {
        param ([System.Byte[]] $Data, [System.String[]] $Keyword)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ PngData = $Data; Keyword = $Keyword } {
            $selected = Select-ImageConverterPngChunk -Data $PngData -ExcludeTextKeyword $Keyword
            # The comma keeps the byte array in one piece on its way out of the script block.
            , $selected
        }
    }

    # Returns the chunk types of a PNG file, text chunks with their keyword, e.g. 'zTXt:Raw profile type icc'.
    function Get-ChunkName
    {
        param ([System.Byte[]] $Data)

        $position = 8
        while ($position + 12 -le $Data.Length)
        {
            $length = ([System.Int64] $Data[$position] -shl 24) -bor ([System.Int64] $Data[$position + 1] -shl 16) -bor ([System.Int64] $Data[$position + 2] -shl 8) -bor [System.Int64] $Data[$position + 3]
            $type = [System.Text.Encoding]::ASCII.GetString($Data, $position + 4, 4)

            if ($type -cin @('tEXt', 'zTXt'))
            {
                $keywordEnd = [System.Array]::IndexOf($Data, [System.Byte] 0, $position + 8)
                $type = '{0}:{1}' -f $type, [System.Text.Encoding]::ASCII.GetString($Data, $position + 8, $keywordEnd - $position - 8)
            }

            $type
            $position += 12 + $length
        }
    }

    $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#4080C0'), 8, 8)
    try
    {
        $image.SetProfile([ImageMagick.ColorProfiles]::AdobeRGB1998)
        $image.Comment = 'kept comment'
        $script:png = $image.ToByteArray([ImageMagick.MagickFormat]::Png)
    }
    finally
    {
        $image.Dispose()
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Select-ImageConverterPngChunk' {
    It 'Should start from a PNG that has the ICC profile twice' {
        Get-ChunkName -Data $script:png | Should -Contain 'iCCP'
        Get-ChunkName -Data $script:png | Should -Contain 'zTXt:Raw profile type icc'
    }

    It 'Should leave out the text chunk with the keyword and keep every other chunk' {
        $result = Select-Chunk -Data $script:png -Keyword 'Raw profile type icc', 'Raw profile type icm'

        $result.GetType() | Should -Be ([System.Byte[]])
        $expected = Get-ChunkName -Data $script:png | Where-Object -FilterScript { $_ -ne 'zTXt:Raw profile type icc' }
        Get-ChunkName -Data $result | Should -Be $expected
        Get-ChunkName -Data $result | Should -Contain 'tEXt:comment'
    }

    It 'Should return a PNG that reads with the same profile and pixels' {
        $result = Select-Chunk -Data $script:png -Keyword 'Raw profile type icc'

        $original = [ImageMagick.MagickImage]::new($script:png)
        $filtered = [ImageMagick.MagickImage]::new($result)
        try
        {
            $filtered.GetColorProfile().ToByteArray() | Should -Be $original.GetColorProfile().ToByteArray()
            $filtered.Compare($original, [ImageMagick.ErrorMetric]::Absolute) | Should -Be 0
        }
        finally
        {
            $original.Dispose()
            $filtered.Dispose()
        }
    }

    It 'Should return data that is not a PNG unchanged' {
        $data = [System.Text.Encoding]::ASCII.GetBytes('GIF89a not a png')

        $result = Select-Chunk -Data $data -Keyword 'Raw profile type icc'

        $result | Should -Be $data
    }

    It 'Should keep a damaged last chunk unchanged' {
        # A tEXt chunk that announces 4096 bytes of data but ends after 5.
        $damaged = [System.Byte[]] @(0x00, 0x00, 0x10, 0x00, 0x74, 0x45, 0x58, 0x74, 0x41, 0x42, 0x43, 0x00, 0x44)
        $data = [System.Byte[]] ($script:png + $damaged)
        $withoutCopy = Select-Chunk -Data $script:png -Keyword 'Raw profile type icc'

        $result = Select-Chunk -Data $data -Keyword 'Raw profile type icc'

        $result | Should -Be ([System.Byte[]] ($withoutCopy + $damaged))
    }
}
