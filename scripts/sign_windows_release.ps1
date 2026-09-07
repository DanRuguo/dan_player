[CmdletBinding()]
param(
    [string[]] $Path,
    [string] $Subject = 'CN=RCEIT.Inc',
    [string] $Thumbprint = $env:RCEIT_SIGNING_THUMBPRINT,
    [string] $TimestampServer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot

function Test-CodeSigningUsage($Certificate) {
    foreach ($extension in $Certificate.Extensions) {
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($usage in $extension.EnhancedKeyUsages) {
                if ($usage.Value -eq '1.3.6.1.5.5.7.3.3') { return $true }
            }
        }
    }
    return $false
}

if (-not $Path -or $Path.Count -eq 0) {
    $Path = @(
        (Join-Path $repositoryRoot 'build\windows\x64\runner\Release\Dan Player.exe'),
        (Join-Path $repositoryRoot 'build\windows\x64\runner\Release\rust_lib_dan_player.dll')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
}

if (-not $Path -or $Path.Count -eq 0) {
    throw 'No Dan Player release artifacts were found. Build the Windows release first or pass -Path.'
}

$certificate = $null
if ($Thumbprint) {
    $normalizedThumbprint = $Thumbprint.Replace(' ', '').ToUpperInvariant()
    $certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$normalizedThumbprint" -ErrorAction SilentlyContinue
} else {
    $certificate = Get-ChildItem -Path 'Cert:\CurrentUser\My' |
        Where-Object {
            $_.Subject -eq $Subject -and
            $_.HasPrivateKey -and
            $_.NotBefore -le (Get-Date) -and
            $_.NotAfter -gt (Get-Date) -and
            (Test-CodeSigningUsage $_)
        } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
}

if (-not $certificate) {
    throw "No valid code-signing certificate was found for $Subject in Cert:\CurrentUser\My."
}
if (-not $certificate.HasPrivateKey -or
    $certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -le (Get-Date) -or
    -not (Test-CodeSigningUsage $certificate)) {
    throw 'The selected certificate must be current, have a private key, and permit code signing.'
}

Write-Host "Signing as $($certificate.Subject)"
Write-Host "Certificate: $($certificate.Thumbprint)"
Write-Host "Valid until: $($certificate.NotAfter.ToString('yyyy-MM-dd HH:mm:ss zzz'))"

foreach ($candidate in $Path) {
    $resolvedPath = (Resolve-Path -LiteralPath $candidate).Path
    $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
    if ($extension -notin @('.exe', '.dll', '.msix', '.msixbundle')) {
        throw "Refusing to Authenticode-sign unsupported file type: $resolvedPath"
    }

    $signingParameters = @{
        FilePath      = $resolvedPath
        Certificate   = $certificate
        HashAlgorithm = 'SHA256'
    }
    if ($TimestampServer) {
        $signingParameters.TimestampServer = $TimestampServer
    }

    $null = Set-AuthenticodeSignature @signingParameters
    $signature = Get-AuthenticodeSignature -LiteralPath $resolvedPath
    if (-not $signature.SignerCertificate -or
        $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint -or
        $signature.Status -in @('HashMismatch', 'NotSigned', 'NotSupportedFileFormat', 'Incompatible')) {
        throw "The signature could not be verified on $resolvedPath"
    }

    Write-Host "Signed: $resolvedPath"
    Write-Host "  Local trust status: $($signature.Status)"
}
