[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $LightSource,
    [Parameter(Mandatory=$true)][string] $DarkSource,
    [string] $OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\branding')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$drawingReferences = @([Drawing.Bitmap].Assembly.Location, [Drawing.Color].Assembly.Location)
$drawingReferences += @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
    $_.FullName -match '^System.Private.Windows.(GdiPlus|Core),'
} | Select-Object -ExpandProperty Location)
Add-Type -ReferencedAssemblies $drawingReferences -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;

public static class BrandingAlpha {
  public static string Extract(string input, string output, bool whiteInk) {
    using (var source = new Bitmap(input))
    using (var matte = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb)) {
      int left = source.Width, top = source.Height, right = -1, bottom = -1;
      for (int y = 0; y < source.Height; y++) {
        for (int x = 0; x < source.Width; x++) {
          var pixel = source.GetPixel(x, y);
          // Both originals are monochrome marks. Convert luminance to alpha,
          // never redraw, rescale or move any stroke. Remove only the very faint
          // paper/background texture and unmatte RGB to prevent edge halos.
          double luminance = .2126 * pixel.R + .7152 * pixel.G + .0722 * pixel.B;
          double coverage = whiteInk ? luminance : 255 - luminance;
          int alpha = (int)Math.Round(Math.Max(0, Math.Min(255, (coverage - 10) * 255 / 235)));
          alpha = alpha * pixel.A / 255;
          int ink = whiteInk ? 255 : 0;
          matte.SetPixel(x, y, Color.FromArgb(alpha, ink, ink, ink));
          if (alpha > 0) {
            left = Math.Min(left, x); top = Math.Min(top, y);
            right = Math.Max(right, x); bottom = Math.Max(bottom, y);
          }
        }
      }
      if (right < left) throw new InvalidOperationException("No visible logo pixels in input.");
      int width = right - left + 1, height = bottom - top + 1;
      int padding = Math.Max(24, (int)Math.Ceiling(Math.Max(width, height) * .045));
      using (var cropped = new Bitmap(width + padding * 2, height + padding * 2, PixelFormat.Format32bppArgb)) {
        using (var graphics = Graphics.FromImage(cropped)) {
          graphics.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
          graphics.Clear(Color.Transparent);
          graphics.DrawImage(matte, new Rectangle(padding, padding, width, height),
            new Rectangle(left, top, width, height), GraphicsUnit.Pixel);
        }
        cropped.Save(output, ImageFormat.Png);
        return String.Format("{0}: {1}x{2}; source crop {3},{4},{5},{6}; transparent RGBA", output,
          cropped.Width, cropped.Height, left, top, width, height);
      }
    }
  }
}
'@

$sources = @((Resolve-Path -LiteralPath $LightSource).Path, (Resolve-Path -LiteralPath $DarkSource).Path)
$originalHashes = @($sources | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$outputs = @((Join-Path $OutputDirectory 'danruguo_light.png'), (Join-Path $OutputDirectory 'danruguo_dark.png'))
foreach ($output in $outputs) {
    if (Test-Path -LiteralPath $output) { throw "Refusing to overwrite an existing derived asset: $output" }
}
[BrandingAlpha]::Extract($sources[0], $outputs[0], $false)
[BrandingAlpha]::Extract($sources[1], $outputs[1], $true)
for ($index = 0; $index -lt $sources.Count; $index++) {
    if ((Get-FileHash -LiteralPath $sources[$index] -Algorithm SHA256).Hash -ne $originalHashes[$index]) {
        throw 'Source file changed during read-only extraction.'
    }
}
Write-Host 'Source hashes unchanged; generated only new project assets.'
