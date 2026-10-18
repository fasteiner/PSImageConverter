BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # Runs the helper in the module scope; the comma keeps a returned byte array in one piece.
    function Get-TrimmedProfile
    {
        param ([System.Byte[]] $Data)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ ProfileData = $Data } {
            $trimmed = Get-ImageConverterTrimmedColorProfile -Data $ProfileData
            if ($null -ne $trimmed)
            {
                , $trimmed
            }
        }
    }

    # Returns a copy of the profile with the declared size (big-endian, bytes 0 to 3) set to -Size.
    function Get-ProfileWithDeclaredSize
    {
        param ([System.Byte[]] $Data, [System.Int64] $Size)

        $copy = [System.Byte[]] $Data.Clone()
        $sizeBytes = [System.BitConverter]::GetBytes([System.UInt32] $Size)
        [System.Array]::Reverse($sizeBytes)
        $sizeBytes.CopyTo($copy, 0)
        , $copy
    }

    # Adobe RGB (1998): an ICC version 2 profile of 560 bytes whose header declares 560 bytes.
    $script:adobeRgb = [ImageMagick.ColorProfiles]::AdobeRGB1998.ToByteArray()
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterTrimmedColorProfile' {
    It 'Should start from a profile that ends where its header says' {
        $script:adobeRgb.Length | Should -Be 560
        $script:adobeRgb[0..3] | Should -Be @(0, 0, 2, 0x30)
    }

    It 'Should return the declared <Size> bytes of a profile that is followed by <Extra> more' -ForEach @(
        @{ Size = 560; Extra = 2 }
        @{ Size = 560; Extra = 1 }
        @{ Size = 560; Extra = 1000 }
    ) {
        $data = [System.Byte[]] ($script:adobeRgb + [System.Byte[]]::new($Extra))

        $result = Get-TrimmedProfile -Data $data

        $result.GetType() | Should -Be ([System.Byte[]])
        $result.Length | Should -Be $Size
        $result | Should -Be $script:adobeRgb
    }

    It 'Should leave the bytes after the declared size out whatever their value' {
        $data = [System.Byte[]] ($script:adobeRgb + [System.Byte[]] @(0xAB, 0xCD, 0xEF))

        $result = Get-TrimmedProfile -Data $data

        $result | Should -Be $script:adobeRgb
    }

    It 'Should start from a profile whose tag table of 10 tags ends at byte 252' {
        # The tag count is the big-endian value at byte 128; each entry of the table takes 12 bytes: 132 + 12 * 10.
        $script:adobeRgb[128..131] | Should -Be @(0, 0, 0, 10)
    }

    It 'Should return the declared 252 bytes when the declared size ends where the tag table does' {
        # The smallest size it cuts to: lcms skips the tags whose data lies after it, so it decides whether the profile can be used.
        $data = Get-ProfileWithDeclaredSize -Data $script:adobeRgb -Size 252

        $result = Get-TrimmedProfile -Data $data

        $result.Length | Should -Be 252
        $result | Should -Be $data[0..251]
    }

    It 'Should return nothing when the declared size of <Size> bytes ends <Case>' -ForEach @(
        @{ Case = 'inside the tag table, one byte before its end'; Size = 251 }
        @{ Case = 'inside the tag table'; Size = 200 }
        @{ Case = 'before the end of the tag count'; Size = 131 }
        @{ Case = 'with the 128-byte header'; Size = 128 }
    ) {
        # Cut there, the profile would have no complete tag table, which lcms reads from the data as given.
        $data = Get-ProfileWithDeclaredSize -Data ([System.Byte[]] ($script:adobeRgb + [System.Byte[]]::new(2))) -Size $Size

        Get-TrimmedProfile -Data $data | Should -BeNullOrEmpty
    }

    It 'Should return nothing for a tag count of <TagCount>, whose table ends after the declared size' -ForEach @(
        @{ TagCount = 36L }
        @{ TagCount = 0xFFFFFFFFL }
    ) {
        # 36 tags end at byte 564, after the 560 declared bytes; the largest count must not overflow.
        $data = [System.Byte[]] ($script:adobeRgb + [System.Byte[]]::new(2))
        $countBytes = [System.BitConverter]::GetBytes([System.UInt32] $TagCount)
        [System.Array]::Reverse($countBytes)
        $countBytes.CopyTo($data, 128)

        Get-TrimmedProfile -Data $data | Should -BeNullOrEmpty
    }

    It 'Should return nothing for a profile that ends where its header says' {
        Get-TrimmedProfile -Data $script:adobeRgb | Should -BeNullOrEmpty
    }

    It 'Should return nothing when the header declares <Case>' -ForEach @(
        @{ Case = 'a few more bytes than there are'; Size = 564 }
        @{ Case = 'far more bytes than there are'; Size = 0xFFFFFFFFL }
        @{ Case = 'less than the 128-byte header'; Size = 127 }
        @{ Case = '100 bytes'; Size = 100 }
        @{ Case = '0 bytes'; Size = 0 }
    ) {
        $data = Get-ProfileWithDeclaredSize -Data ([System.Byte[]] ($script:adobeRgb + [System.Byte[]]::new(2))) -Size $Size

        Get-TrimmedProfile -Data $data | Should -BeNullOrEmpty
    }

    It 'Should return nothing for data without the signature acsp at byte 36' {
        $data = [System.Byte[]] ($script:adobeRgb + [System.Byte[]]::new(2))
        [System.Text.Encoding]::ASCII.GetBytes('acsq').CopyTo($data, 36)

        Get-TrimmedProfile -Data $data | Should -BeNullOrEmpty
    }

    It 'Should compare the signature acsp case-sensitively' {
        $data = [System.Byte[]] ($script:adobeRgb + [System.Byte[]]::new(2))
        [System.Text.Encoding]::ASCII.GetBytes('ACSP').CopyTo($data, 36)

        Get-TrimmedProfile -Data $data | Should -BeNullOrEmpty
    }

    It 'Should return nothing for data of <Length> bytes, too short for a header with bytes after it' -ForEach @(
        @{ Length = 1 }
        @{ Length = 39 }
        @{ Length = 128 }
    ) {
        Get-TrimmedProfile -Data ([System.Byte[]] $script:adobeRgb[0..($Length - 1)]) | Should -BeNullOrEmpty
    }

    It 'Should not change the data it is given' {
        $data = [System.Byte[]] ($script:adobeRgb + [System.Byte[]]::new(2))

        $null = Get-TrimmedProfile -Data $data

        $data.Length | Should -Be 562
    }
}
