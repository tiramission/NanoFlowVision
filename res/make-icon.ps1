# Draws the app icon and packs it into res/app.ico.
# The look is the app's own: amber on paper, a photograph of mountains.

Add-Type -AssemblyName System.Drawing

$size = 256
$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# The amber tile.
$sq = RoundRect 8 8 240 240 56
$amber = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point(0, 256)),
    [System.Drawing.Color]::FromArgb(255, 0xF2, 0xB7, 0x5C),
    [System.Drawing.Color]::FromArgb(255, 0xC7, 0x7D, 0x20))
$g.FillPath($amber, $sq)

# The photograph on it: paper, a sun, two mountains.
$card = RoundRect 52 66 152 124 18
$paper = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0xFA, 0xF8, 0xF3))
$g.FillPath($paper, $card)

$g.SetClip($card)
$sun = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0xE8, 0xA3, 0x3D))
$g.FillEllipse($sun, 148, 82, 32, 32)
$hill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0x8A, 0x6B, 0x3A))
$dark = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0x2A, 0x25, 0x1C))
$darker = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0x16, 0x14, 0x0F))
$far = @([System.Drawing.PointF]::new(52, 190), [System.Drawing.PointF]::new(104, 112), [System.Drawing.PointF]::new(156, 190))
$g.FillPolygon($hill, $far)
$left = @([System.Drawing.PointF]::new(60, 190), [System.Drawing.PointF]::new(126, 104), [System.Drawing.PointF]::new(192, 190))
$g.FillPolygon($dark, $left)
$right = @([System.Drawing.PointF]::new(140, 190), [System.Drawing.PointF]::new(190, 126), [System.Drawing.PointF]::new(240, 190))
$g.FillPolygon($darker, $right)
$g.ResetClip()
$g.Dispose()

# A plain PNG for the README, beside the sizes.
$bmp.Save("$PWD\res\icon.png", [System.Drawing.Imaging.ImageFormat]::Png)

# The .ico: PNG entries, one per size.
$sizes = @(256, 128, 64, 48, 32, 16)
$pngs = @()
foreach ($s in $sizes) {
    $small = New-Object System.Drawing.Bitmap($s, $s)
    $sg = [System.Drawing.Graphics]::FromImage($small)
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $sg.DrawImage($bmp, (New-Object System.Drawing.Rectangle(0, 0, $s, $s)))
    $sg.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $small.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += , @($s, $ms.ToArray())
    $small.Dispose()
}
$bmp.Dispose()

$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($out)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count)
$offset = 6 + 16 * $pngs.Count
foreach ($e in $pngs) {
    $s = $e[0]; $data = $e[1]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$data.Length); $bw.Write([uint32]$offset)
    $offset += $data.Length
}
foreach ($e in $pngs) { $bw.Write($e[1]) }
$bw.Flush()
[System.IO.File]::WriteAllBytes("$PWD\res\app.ico", $out.ToArray())
Write-Host ("res/app.ico: " + (Get-Item "$PWD\res\app.ico").Length + " bytes, " + $pngs.Count + " sizes")
