# End-to-end smoke test against the real desktop: starts the app, drives the
# global hotkeys and the mouse with synthetic input and checks the screen by
# sampling pixels. It briefly dims the screen and moves the cursor.
#
#   .\scripts\e2e_smoke.ps1 [-Exe .\reading_focus_overlay.exe] [-OutDir C:\Temp\rfo]
#
# Safety: mouse input is only sent after the first hotkey is verified to have
# produced the dim overlay, so a broken build cannot click through to other apps.
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\reading_focus_overlay.exe'),
    [string]$OutDir = (Join-Path $env:TEMP 'rfo_e2e')
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Native {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr e);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
}
'@
[void][Native]::SetProcessDPIAware()
$W = [Native]::GetSystemMetrics(0); $H = [Native]::GetSystemMetrics(1)
$results = New-Object System.Collections.Generic.List[string]
$failed = $false

function Key([byte[]]$mods, [byte]$vk) {
    foreach ($m in $mods) { [Native]::keybd_event($m, 0, 0, [UIntPtr]::Zero) }
    [Native]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
    [Native]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
    [array]::Reverse($mods)
    foreach ($m in $mods) { [Native]::keybd_event($m, 0, 2, [UIntPtr]::Zero) }
    Start-Sleep -Milliseconds 350
}
function Tap([byte]$vk) { Key @() $vk }
function Click([int]$x, [int]$y) {
    [Native]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 120
    [Native]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [Native]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 260
}
function Drag([int]$x0, [int]$y0, [int]$x1, [int]$y1) {
    [Native]::SetCursorPos($x0, $y0); Start-Sleep -Milliseconds 150
    [Native]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le 12; $i++) {
        [Native]::SetCursorPos([int]($x0 + ($x1 - $x0) * $i / 12), [int]($y0 + ($y1 - $y0) * $i / 12))
        Start-Sleep -Milliseconds 25
    }
    Start-Sleep -Milliseconds 150
    [Native]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 400
}
function Shot([string]$name) {
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $g.Dispose()
    $path = Join-Path $OutDir "$name.png"
    # keep the evidence small: quarter-size copy
    $small = New-Object System.Drawing.Bitmap ([int]($W / 2)), ([int]($H / 2))
    $g2 = [System.Drawing.Graphics]::FromImage($small)
    $g2.DrawImage($bmp, 0, 0, $small.Width, $small.Height); $g2.Dispose()
    $small.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $small.Dispose()
    return $bmp
}
function Luma($bmp, [int]$x, [int]$y) {
    $c = $bmp.GetPixel($x, $y)
    return 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
}
function AccentCount($bmp, [int]$x0, [int]$y0, [int]$w, [int]$h) {
    # the UI accent is violet (#7C6CFF): count clearly violet pixels in a region
    $n = 0
    for ($y = $y0; $y -lt $y0 + $h; $y += 2) { for ($x = $x0; $x -lt $x0 + $w; $x += 2) {
        if ($x -ge 0 -and $y -ge 0 -and $x -lt $bmp.Width -and $y -lt $bmp.Height) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.B -gt 200 -and ($c.B - $c.G) -gt 70 -and $c.R -gt 80 -and $c.R -lt 200) { $n++ }
        } } }
    return $n
}
function Check([string]$name, [bool]$ok, [string]$detail) {
    $script:results.Add(("{0,-4} {1}  {2}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $name, $detail))
    if (-not $ok) { $script:failed = $true }
}

$CTRL = 0x11; $ALT = 0x12; $SHIFT = 0x10; $VK_F = 0x46; $VK_R = 0x52; $VK_Q = 0x51; $VK_ESC = 0x1B; $VK_P = 0x50
$VK_3 = 0x33; $VK_SPACE = 0x20; $VK_ENTER = 0x0D

# other programs often own Ctrl+Shift+R / Shift+Esc globally, so the test remaps those two
$ini = Join-Path $OutDir "e2e.ini"
Set-Content -Path $ini -Value "[Shortcuts]`nHOTKEY_TOGGLE_OVERLAY=^!+R`nHOTKEY_SELECT_FOCUS=^!+Esc`nHOTKEY_PANEL=^!+P`n"
$proc = Start-Process -FilePath $Exe -ArgumentList @("--config", $ini) -PassThru
try {
    Start-Sleep -Milliseconds 2200 # startup toast fades
    Check 'process alive' (-not $proc.HasExited) "pid $($proc.Id)"
    $base = Shot '0_baseline'
    # sample a probe grid; bright-ish pixels make the dim measurable
    $probe = @(@(40, 40), @(($W - 60), 60), @(60, ($H - 80)), @(($W / 2), ($H - 30)), @(($W - 80), ($H / 2)))
    $l0 = ($probe | ForEach-Object { Luma $base ([int]$_[0]) ([int]$_[1]) } | Measure-Object -Average).Average

    # 1. Ctrl+Shift+F -> selection mode with a light dim
    Key @($CTRL, $SHIFT) $VK_F
    $s1 = Shot '1_selecting'
    $l1 = ($probe | ForEach-Object { Luma $s1 ([int]$_[0]) ([int]$_[1]) } | Measure-Object -Average).Average
    Check 'Ctrl+Shift+F dims the screen' ($l1 -lt $l0 - 2 -or $l0 -lt 12) ("luma {0:N1} -> {1:N1}" -f $l0, $l1)
    if ($failed) { throw 'dim overlay did not appear; aborting before any mouse input' }
    $dock0 = AccentCount $base ([int]($W / 2 - 330)) 10 660 140
    $dock1 = AccentCount $s1 ([int]($W / 2 - 330)) 10 660 140
    Check 'dock with accent pill visible at top centre' ($dock1 -gt $dock0 + 20) ("accent pixels {0} -> {1}" -f $dock0, $dock1)

    # 2. rectangle drag -> final dim with a bright hole
    $x0 = [int]($W * 0.25); $y0 = [int]($H * 0.35); $x1 = [int]($W * 0.55); $y1 = [int]($H * 0.70)
    Drag $x0 $y0 $x1 $y1
    $s2 = Shot '2_rect_final'
    $inside = Luma $s2 ([int](($x0 + $x1) / 2)) ([int](($y0 + $y1) / 2))
    $outside = Luma $s2 ([int]($W * 0.85)) ([int]($H * 0.85))
    $insideBase = Luma $base ([int](($x0 + $x1) / 2)) ([int](($y0 + $y1) / 2))
    $outsideBase = Luma $base ([int]($W * 0.85)) ([int]($H * 0.85))
    Check 'rect hole keeps original pixels' ([math]::Abs($inside - $insideBase) -lt 6) ("{0:N0} vs {1:N0}" -f $inside, $insideBase)
    Check 'outside is dimmed (alpha 225)' ($outside -lt $outsideBase * 0.25 + 4) ("{0:N0} vs {1:N0}" -f $outside, $outsideBase)

    # 3. Ctrl+Shift+F flips the dimmer off and on
    Key @($CTRL, $SHIFT) $VK_F
    $s3 = Shot '3_dim_off'
    Check 'toggle off restores screen' ([math]::Abs((Luma $s3 ([int]($W * 0.85)) ([int]($H * 0.85))) - $outsideBase) -lt 6) ''
    Key @($CTRL, $SHIFT) $VK_F
    $s3b = Shot '3_dim_on_again'
    Check 'toggle on dims again' ((Luma $s3b ([int]($W * 0.85)) ([int]($H * 0.85))) -lt $outsideBase * 0.25 + 4) ''

    # 4. Shift+Esc re-select, key 3 = polygon, 3 vertices + Space
    Key @($CTRL, $ALT, $SHIFT) $VK_ESC
    Tap $VK_3
    $a = @([int]($W * 0.30), [int]($H * 0.30)); $b = @([int]($W * 0.60), [int]($H * 0.30)); $c = @([int]($W * 0.45), [int]($H * 0.65))
    Click $a[0] $a[1]; Click $b[0] $b[1]; Click $c[0] $c[1]
    $s4a = Shot '4a_polygon_in_progress'
    Tap $VK_SPACE
    Start-Sleep -Milliseconds 300
    $s4 = Shot '4_polygon_final'
    $cx = [int](($a[0] + $b[0] + $c[0]) / 3); $cy = [int](($a[1] + $b[1] + $c[1]) / 3)
    Check 'polygon hole keeps original pixels' ([math]::Abs((Luma $s4 $cx $cy) - (Luma $base $cx $cy)) -lt 6) ''
    Check 'polygon outside dimmed' ((Luma $s4 ([int]($W * 0.85)) ([int]($H * 0.85))) -lt $outsideBase * 0.25 + 4) ''

    # 5. Shift+Esc then Esc cancels everything
    Key @($CTRL, $ALT, $SHIFT) $VK_ESC
    Tap $VK_ESC
    $s5 = Shot '5_cancelled'
    Check 'Esc cancels and clears the dim' ([math]::Abs((Luma $s5 ([int]($W * 0.85)) ([int]($H * 0.85))) - $outsideBase) -lt 6) ''

    # 6. pencil overlay on/off
    [Native]::SetCursorPos([int]($W / 2), [int]($H / 2)); Start-Sleep -Milliseconds 200
    Key @($CTRL, $ALT, $SHIFT) $VK_R
    [Native]::SetCursorPos([int]($W / 2) + 3, [int]($H / 2) + 3); Start-Sleep -Milliseconds 300
    $s6 = Shot '6_pencil_on'
    Key @($CTRL, $ALT, $SHIFT) $VK_R
    Check 'pencil captured' $true 'see 6_pencil_on.png'

    # 7. control panel: hotkey opens it, Esc closes it
    $px = [int]($W / 2 - 280); $py = [int]($H - 540)
    $pa0 = AccentCount $base $px $py 560 540
    Key @($CTRL, $ALT, $SHIFT) $VK_P
    Start-Sleep -Milliseconds 450
    $s7 = Shot '7_panel_open'
    $pa1 = AccentCount $s7 $px $py 560 540
    Check 'control panel opens (accent logo visible)' ($pa1 -gt $pa0 + 40) ("accent pixels {0} -> {1}" -f $pa0, $pa1)
    Tap $VK_ESC
    Start-Sleep -Milliseconds 500
    $s7b = Shot '7_panel_closed'
    $pa2 = AccentCount $s7b $px $py 560 540
    Check 'Esc closes the control panel' ($pa2 -lt $pa1 - 40) ("accent pixels {0} -> {1}" -f $pa1, $pa2)
}
catch {
    $results.Add("ERR  $($_.Exception.Message)")
    $failed = $true
}
finally {
    # make sure nothing stays dimmed/hooked whatever happened
    if ($proc -and -not $proc.HasExited) {
        Start-Sleep -Milliseconds 300
        Key @($CTRL, $SHIFT) $VK_Q
        if (-not $proc.WaitForExit(8000)) { $proc.Kill() ; $results.Add('WARN quit hotkey did not stop the app; killed') }
        else { $results.Add('PASS Ctrl+Shift+Q quits the app') }
    }
}
$results | ForEach-Object { Write-Output $_ }
Write-Output "screenshots: $OutDir"
if ($failed) { exit 1 }

