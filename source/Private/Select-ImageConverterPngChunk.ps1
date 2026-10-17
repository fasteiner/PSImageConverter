function Select-ImageConverterPngChunk
{
    <#
        .SYNOPSIS
        Returns a PNG file without the text chunks that have one of the given keywords.

        .DESCRIPTION
        Copies the chunks of an encoded PNG file and leaves out every tEXt and zTXt chunk whose
        keyword is in -ExcludeTextKeyword. ImageMagick's PNG encoder writes an ICC profile as
        iCCP chunk and also as zTXt chunk 'Raw profile type icc'; only iCCP is standard, so the
        copy is dropped. Removing a chunk does not change the checksums of the other chunks,
        which cover only their own type and data. Data that does not start with the PNG
        signature is returned unchanged, and so is a damaged chunk at the end. Returns the bytes
        as one byte array.

        .PARAMETER Data
        The bytes of the encoded PNG file, e.g. from MagickImage.ToByteArray('Png').

        .PARAMETER ExcludeTextKeyword
        The keywords of the tEXt and zTXt chunks to leave out, e.g. 'Raw profile type icc'.

        .EXAMPLE
        Select-ImageConverterPngChunk -Data $png -ExcludeTextKeyword 'Raw profile type icc'

        Returns the PNG without the hex-encoded copy of its ICC profile.
    #>
    [CmdletBinding()]
    [OutputType([System.Byte[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Byte[]]
        $Data,

        [Parameter(Mandatory = $true)]
        [System.String[]]
        $ExcludeTextKeyword
    )

    $signature = [System.Byte[]] @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)

    if ($Data.Length -lt 8 -or -not [System.Linq.Enumerable]::SequenceEqual([System.Byte[]] $Data[0..7], $signature))
    {
        Write-Output -InputObject $Data -NoEnumerate
        return
    }

    $output = [System.IO.MemoryStream]::new($Data.Length)
    $output.Write($Data, 0, 8)
    $position = 8

    # A chunk is a 4-byte big-endian data length, the 4-byte type, the data and a 4-byte CRC.
    while ($position + 12 -le $Data.Length)
    {
        $length = ([System.Int64] $Data[$position] -shl 24) -bor ([System.Int64] $Data[$position + 1] -shl 16) -bor ([System.Int64] $Data[$position + 2] -shl 8) -bor [System.Int64] $Data[$position + 3]
        $end = $position + 12 + $length

        if ($end -gt $Data.Length)
        {
            break
        }

        $type = [System.Text.Encoding]::ASCII.GetString($Data, $position + 4, 4)
        $keep = $true

        if ($type -cin @('tEXt', 'zTXt'))
        {
            # The keyword (1-79 characters) is terminated by a zero byte at the start of the data.
            $keywordEnd = [System.Array]::IndexOf($Data, [System.Byte] 0, $position + 8, [System.Math]::Min($length, 80))
            if ($keywordEnd -gt $position + 8)
            {
                $keyword = [System.Text.Encoding]::Latin1.GetString($Data, $position + 8, $keywordEnd - $position - 8)
                $keep = $keyword -cnotin $ExcludeTextKeyword
            }
        }

        if ($keep)
        {
            $output.Write($Data, $position, $end - $position)
        }

        $position = $end
    }

    $output.Write($Data, $position, $Data.Length - $position)
    Write-Output -InputObject $output.ToArray() -NoEnumerate
}
