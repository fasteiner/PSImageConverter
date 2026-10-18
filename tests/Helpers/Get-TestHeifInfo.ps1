function Get-TestHeifInfo
{
    <#
        .SYNOPSIS
        Reads the boxes of a HEIF file that the HEIC tests check and Magick.NET does not report.

        .DESCRIPTION
        Returns the type of the primary item, its nclx colour box (primaries, transfer, matrix, full
        range; $null when it has none), whether it has an ICC profile (colr prof), the types of all
        items, the number and sizes in bytes of the coded slices (HEVC VCL NAL units) of its coded
        image, or of the first tile when the primary item is a grid, the number of iloc extents of
        that coded image and the numbers of extents of all HEVC items (hvc1: the coded images, tiles
        and an alpha image) in the order of their item IDs. Only what the encoders of this module
        write is read: boxes with 32-bit sizes inside meta, items in the file (construction method 0)
        or in idat (1).

        .PARAMETER Path
        The HEIF file to read.

        .EXAMPLE
        (Get-TestHeifInfo -Path 'C:\Temp\photo.heic').Nclx.Matrix

        Returns 1 for a file whose primary item signals the BT.709 matrix.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $data = [System.IO.File]::ReadAllBytes($Path)

    function Read-Number
    {
        param ([System.Int64] $Position, [System.Int32] $Size)

        $value = [System.UInt64] 0
        for ($i = 0; $i -lt $Size; $i++)
        {
            $value = ($value -shl 8) -bor $data[$Position + $i]
        }

        $value
    }

    function Get-Box
    {
        param ([System.Int64] $Start, [System.Int64] $End)

        $position = $Start
        while ($position + 8 -le $End)
        {
            $size = [System.Int64] (Read-Number -Position $position -Size 4)
            $header = 8
            if ($size -eq 1)
            {
                $size = [System.Int64] (Read-Number -Position ($position + 8) -Size 8)
                $header = 16
            }
            elseif ($size -eq 0)
            {
                $size = $End - $position
            }

            [PSCustomObject] @{ Type = [System.Text.Encoding]::ASCII.GetString($data, $position + 4, 4); Start = $position; Size = $size; Body = $position + $header }
            $position += $size
        }
    }

    $meta = Get-Box -Start 0 -End $data.Length | Where-Object -Property Type -EQ 'meta'
    $children = Get-Box -Start ($meta.Body + 4) -End ($meta.Start + $meta.Size)
    $box = @{}
    foreach ($child in $children)
    {
        $box[$child.Type] = $child
    }

    $primary = if ($data[$box.pitm.Body] -eq 0) { Read-Number -Position ($box.pitm.Body + 4) -Size 2 } else { Read-Number -Position ($box.pitm.Body + 4) -Size 4 }

    # iinf: the type of every item.
    $types = @{}
    $countSize = if ($data[$box.iinf.Body] -eq 0) { 2 } else { 4 }
    foreach ($entry in Get-Box -Start ($box.iinf.Body + 4 + $countSize) -End ($box.iinf.Start + $box.iinf.Size))
    {
        $idSize = if ($data[$entry.Body] -ge 3) { 4 } else { 2 }
        $types[[System.UInt64] (Read-Number -Position ($entry.Body + 4) -Size $idSize)] = [System.Text.Encoding]::ASCII.GetString($data, $entry.Body + 4 + $idSize + 2, 4)
    }

    # iloc: the bytes and the number of extents of every item.
    $location = @{}
    $extents = @{}
    $version = $data[$box.iloc.Body]
    $position = $box.iloc.Body + 4
    $offsetSize = $data[$position] -shr 4
    $lengthSize = $data[$position] -band 15
    $baseSize = $data[$position + 1] -shr 4
    $indexSize = if ($version -ge 1) { $data[$position + 1] -band 15 } else { 0 }
    $idSize = if ($version -lt 2) { 2 } else { 4 }
    $position += 2
    $itemCount = Read-Number -Position $position -Size $idSize
    $position += $idSize
    for ($item = 0; $item -lt $itemCount; $item++)
    {
        $id = Read-Number -Position $position -Size $idSize
        $position += $idSize
        $method = 0
        if ($version -ge 1)
        {
            $method = $data[$position + 1] -band 15
            $position += 2
        }

        $position += 2
        $base = Read-Number -Position $position -Size $baseSize
        $position += $baseSize
        $extentCount = Read-Number -Position $position -Size 2
        $position += 2
        $bytes = [System.IO.MemoryStream]::new()
        for ($extent = 0; $extent -lt $extentCount; $extent++)
        {
            $position += $indexSize
            $offset = Read-Number -Position $position -Size $offsetSize
            $position += $offsetSize
            $length = Read-Number -Position $position -Size $lengthSize
            $position += $lengthSize
            $start = if ($method -eq 1) { $box.idat.Body + $base + $offset } else { $base + $offset }
            $bytes.Write($data, $start, $length)
        }

        $location[[System.UInt64] $id] = $bytes.ToArray()
        $extents[[System.UInt64] $id] = [System.Int32] $extentCount
    }

    # ipco and ipma: the property boxes of every item.
    $iprpChildren = Get-Box -Start ($box.iprp.Body) -End ($box.iprp.Start + $box.iprp.Size)
    $ipco = $iprpChildren | Where-Object -Property Type -EQ 'ipco'
    $ipma = $iprpChildren | Where-Object -Property Type -EQ 'ipma'
    $properties = @(Get-Box -Start $ipco.Body -End ($ipco.Start + $ipco.Size))
    $associations = @{}
    $version = $data[$ipma.Body]
    $wide = ($data[$ipma.Body + 3] -band 1) -ne 0
    $position = $ipma.Body + 4
    $entryCount = Read-Number -Position $position -Size 4
    $position += 4
    for ($entry = 0; $entry -lt $entryCount; $entry++)
    {
        $idSize = if ($version -lt 1) { 2 } else { 4 }
        $id = Read-Number -Position $position -Size $idSize
        $position += $idSize
        $count = $data[$position]
        $position++
        $associations[[System.UInt64] $id] = @(
            for ($index = 0; $index -lt $count; $index++)
            {
                if ($wide)
                {
                    (Read-Number -Position $position -Size 2) -band 0x7FFF
                    $position += 2
                }
                else
                {
                    $data[$position] -band 0x7F
                    $position++
                }
            }
        )
    }

    function Get-HeifItemProperty
    {
        param ([System.UInt64] $Id, [System.String] $Type)

        foreach ($index in $associations[$Id])
        {
            if ($properties[$index - 1].Type -eq $Type)
            {
                $properties[$index - 1]
            }
        }
    }

    $nclx = $null
    $hasProfile = $false
    foreach ($colr in Get-HeifItemProperty -Id $primary -Type 'colr')
    {
        $colorType = [System.Text.Encoding]::ASCII.GetString($data, $colr.Body, 4)
        if ($colorType -eq 'nclx')
        {
            $nclx = [PSCustomObject] @{
                Primaries = [System.Int32] (Read-Number -Position ($colr.Body + 4) -Size 2)
                Transfer  = [System.Int32] (Read-Number -Position ($colr.Body + 6) -Size 2)
                Matrix    = [System.Int32] (Read-Number -Position ($colr.Body + 8) -Size 2)
                FullRange = ($data[$colr.Body + 10] -band 0x80) -ne 0
            }
        }
        elseif ($colorType -in @('prof', 'rICC'))
        {
            $hasProfile = $true
        }
    }

    # The coded image: the primary item, or the first tile of a grid (iref dimg).
    $coded = [System.UInt64] $primary
    if ($types[$coded] -eq 'grid')
    {
        $irefVersion = $data[$box.iref.Body]
        $refIdSize = if ($irefVersion -eq 0) { 2 } else { 4 }
        foreach ($reference in Get-Box -Start ($box.iref.Body + 4) -End ($box.iref.Start + $box.iref.Size))
        {
            if ($reference.Type -eq 'dimg' -and (Read-Number -Position $reference.Body -Size $refIdSize) -eq $primary)
            {
                $coded = [System.UInt64] (Read-Number -Position ($reference.Body + $refIdSize + 2) -Size $refIdSize)
            }
        }
    }

    # HEVC NAL units in the item are prefixed with their length (hvcC lengthSizeMinusOne + 1 bytes); types 0-31 are slices.
    $hvcC = Get-HeifItemProperty -Id $coded -Type 'hvcC' | Select-Object -First 1
    $nalLengthSize = ($data[$hvcC.Body + 21] -band 3) + 1
    $stream = $location[$coded]
    $sliceSizes = [System.Collections.Generic.List[System.Int64]]::new()
    $position = 0
    while ($position + $nalLengthSize -lt $stream.Length)
    {
        $length = 0
        for ($i = 0; $i -lt $nalLengthSize; $i++)
        {
            $length = ($length -shl 8) -bor $stream[$position + $i]
        }

        if ((($stream[$position + $nalLengthSize] -shr 1) -band 0x3F) -lt 32)
        {
            $sliceSizes.Add($length)
        }

        $position += $nalLengthSize + $length
    }

    [PSCustomObject] @{
        PrimaryType      = $types[[System.UInt64] $primary]
        ItemTypes        = @($types.Keys | Sort-Object | ForEach-Object -Process { $types[$_] })
        Nclx             = $nclx
        HasProfile       = $hasProfile
        SliceCount       = $sliceSizes.Count
        SliceSizes       = $sliceSizes.ToArray()
        ExtentCount      = $extents[$coded]
        HevcExtentCounts = @($types.Keys | Sort-Object | Where-Object -FilterScript { $types[$_] -eq 'hvc1' } | ForEach-Object -Process { $extents[$_] })
    }
}
