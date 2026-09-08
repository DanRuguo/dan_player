. (Join-Path $PSScriptRoot 'validation_receipt.ps1')

function Get-AuthenticodeIntegrity([string] $Path, [string] $ExpectedThumbprint, [bool] $RequireTimestamp) {
    if (-not ('DanPlayerReleaseTrust' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DanPlayerReleaseTrust {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct FileInfo { public UInt32 size; public IntPtr path, file, known; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct TrustData {
    public UInt32 size; public IntPtr policy, sip; public UInt32 ui, revocation, choice;
    public IntPtr file; public UInt32 action; public IntPtr state, url;
    public UInt32 flags, context;
  }
  [DllImport("wintrust.dll", ExactSpelling=true, CharSet=CharSet.Unicode)]
  static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref TrustData data);
  public static UInt32 Verify(string path) {
    IntPtr name=Marshal.StringToCoTaskMemUni(path), info=IntPtr.Zero;
    var data=new TrustData();
    var action=new Guid("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");
    try {
      var file=new FileInfo {size=(UInt32)Marshal.SizeOf(typeof(FileInfo)), path=name};
      info=Marshal.AllocCoTaskMem(Marshal.SizeOf(typeof(FileInfo)));
      Marshal.StructureToPtr(file,info,false);
      data.size=(UInt32)Marshal.SizeOf(typeof(TrustData)); data.ui=2;
      data.choice=1; data.file=info; data.action=1; data.flags=0x1000;
      return unchecked((UInt32)WinVerifyTrust(new IntPtr(-1),ref action,ref data));
    } finally {
      if(data.state!=IntPtr.Zero) { data.action=2; WinVerifyTrust(new IntPtr(-1),ref action,ref data); }
      if(info!=IntPtr.Zero) Marshal.FreeCoTaskMem(info);
      Marshal.FreeCoTaskMem(name);
    }
  }
}
'@
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $result = [ordered]@{ Accepted=$false; Status=[string]$signature.Status; TrustCode=''; TimestampThumbprint=''; SignerThumbprint='' }
    if (-not $signature.SignerCertificate) { return [pscustomobject]$result }
    $certificate = $signature.SignerCertificate
    $result.SignerThumbprint = $certificate.Thumbprint
    if ($certificate.Thumbprint -cne $ExpectedThumbprint -or
        $signature.Status -notin @('Valid', 'UnknownError', 'NotTrusted')) { return [pscustomobject]$result }
    if ($signature.TimeStamperCertificate) { $result.TimestampThumbprint = $signature.TimeStamperCertificate.Thumbprint }
    if ($RequireTimestamp -and -not $signature.TimeStamperCertificate) { return [pscustomobject]$result }
    $trust = [DanPlayerReleaseTrust]::Verify($Path)
    $result.TrustCode = $trust.ToString('X8')
    if ($trust -eq 0 -and $signature.Status -eq 'Valid') { $result.Accepted = $true }
    elseif ($result.TrustCode -eq '800B0109' -and $certificate.Subject -ceq $certificate.Issuer) {
        # A self-issued certificate is allowed only when chain verification
        # identifies *solely* that exact root as untrusted. Other trust errors,
        # including a broken file digest, expiration or timestamp, never pass.
        $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
        try {
            $chain.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $null = $chain.Build($certificate)
            $statuses = @($chain.ChainStatus | ForEach-Object { $_.Status.ToString() })
            $result.Accepted = $statuses.Count -eq 1 -and $statuses[0] -ceq 'UntrustedRoot' -and $chain.ChainElements.Count -eq 1
        } finally { $chain.Dispose() }
    }
    return [pscustomobject]$result
}

function Test-SignatureReceipt($Receipt, [string] $Sha256, [string] $Thumbprint, [string] $TimestampServer, $Integrity) {
    try {
        return $null -ne $Receipt -and $Receipt.Schema -eq 1 -and $Receipt.Verified -eq $true -and
          $Receipt.Sha256 -ceq $Sha256 -and $Receipt.Thumbprint -ceq $Thumbprint -and
          $Receipt.TimestampServer -ceq $TimestampServer -and $Integrity.Accepted -eq $true -and
          $Receipt.TimestampThumbprint -ceq $Integrity.TimestampThumbprint
    } catch { return $false }
}
