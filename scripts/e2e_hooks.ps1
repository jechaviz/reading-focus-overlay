# End-to-end check of the three "distraction" features that rely on hooks or
# a topmost window: click block (mouse hook), Alt+Tab block (keyboard hook) and
# the taskbar blur.
#
# A probe process-side pair of low-level hooks is installed BEFORE the app, so
# the app's hooks run first: whatever the app swallows never reaches the probe.
#
#   .\scripts\e2e_hooks.ps1 [-Exe .\reading_focus_overlay.exe] [-OutDir C:\Temp\rfo_hooks]
param(
    [string]$Exe = (Join-Path $PSScriptRoot '..\reading_focus_overlay.exe'),
    [string]$OutDir = (Join-Path $env:TEMP 'rfo_hooks')
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Probe {
  public delegate IntPtr Proc(int code, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, Proc p, IntPtr mod, uint tid);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int c, IntPtr w, IntPtr l);
  [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static int Clicks = 0, AltTabs = 0, AltF15 = 0;
  static Proc mp = MouseProc, kp = KeyProc;
  static IntPtr mh, kh;
  public static void Install() {
    mh = SetWindowsHookEx(14, mp, GetModuleHandle(null), 0);
    kh = SetWindowsHookEx(13, kp, GetModuleHandle(null), 0);
  }
  static IntPtr MouseProc(int c, IntPtr w, IntPtr l) {
    if (c >= 0 && (int)w == 0x201) Clicks++;
    return CallNextHookEx(mh, c, w, l);
  }
  static IntPtr KeyProc(int c, IntPtr w, IntPtr l) {
    if (c >= 0 && ((int)w == 0x104 || (int)w == 0x100)) {
      int vk = Marshal.ReadInt32(l, 0); int flags = Marshal.ReadInt32(l, 8);
      if ((flags & 0x20) != 0) { if (vk == 0x09) AltTabs++; if (vk == 0x7E) AltF15++; }
    }
    return CallNextHookEx(kh, c, w, l);
  }
}
'@
[void][Probe]::SetProcessDPIAware()
[Probe]::Install()
$results = New-Object System.Collections.Generic.List[string]
$failed = $false
function Check([string]$name, [bool]$ok, [string]$detail) {
    $script:results.Add(("{0,-4} {1}  {2}" -f ($(if ($ok) { 'PASS' } else { 'FAIL' })), $name, $detail))
    if (-not $ok) { $script:failed = $true }
}
function Pump([int]$ms) {
    $end = [DateTime]::Now.AddMilliseconds($ms)
    while ([DateTime]::Now -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 15 }
}
function Key([byte[]]$mods, [byte]$vk) {
    foreach ($m in $mods) { [Probe]::keybd_event($m, 0, 0, [UIntPtr]::Zero) }
    [Probe]::keybd_event($vk, 0, 0, [UIntPtr]::Zero); [Probe]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
    [array]::Reverse($mods)
    foreach ($m in $mods) { [Probe]::keybd_event($m, 0, 2, [UIntPtr]::Zero) }
    Pump 450
}
function ClickAt([int]$x, [int]$y) {
    [Probe]::SetCursorPos($x, $y); Pump 150
    [Probe]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Pump 60
    [Probe]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Pump 250
}
function TaskbarShot([string]$name) {
    $r = New-Object Probe+RECT
    [void][Probe]::GetWindowRect([Probe]::FindWindow('Shell_TrayWnd', $null), [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save((Join-Path $OutDir "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    return $bmp
}
function MeanDiff($a, $b) {
    $sum = 0.0; $n = 0
    for ($y = 0; $y -lt $a.Height; $y += 2) { for ($x = 0; $x -lt $a.Width; $x += 3) {
        $p = $a.GetPixel($x, $y); $q = $b.GetPixel($x, $y)
        $sum += [math]::Abs($p.R - $q.R) + [math]::Abs($p.G - $q.G) + [math]::Abs($p.B - $q.B); $n++ } }
    return $sum / ($n * 3)
}

$CTRL = 0x11; $SHIFT = 0x10; $ALT = 0x12; $TAB = 0x09; $F15 = 0x7E
$VK_B = 0x42; $VK_D = 0x44; $VK_Q = 0x51; $VK_QUOTE = 0x78 # F9: the real default (^+') is layout dependent
$sw = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
$cx = [int]($sw / 2); $cy = 4 # a window's title-bar edge: a harmless place for a control click

$ini = Join-Path $OutDir "hooks.ini"
Set-Content -Path $ini -Value "[Shortcuts]`nHOTKEY_TOGGLE_ALTTAB=^+F9`n"
$proc = Start-Process -FilePath $Exe -ArgumentList @("--config", $ini) -PassThru
try {
    Pump 2500
    Check 'process alive' (-not $proc.HasExited) "pid $($proc.Id)"

    # click block
    $c0 = [Probe]::Clicks
    ClickAt $cx $cy
    $c1 = [Probe]::Clicks
    Check 'probe sees a normal click' ($c1 -gt $c0) "clicks $c0 -> $c1"
    Key @($CTRL, $SHIFT) $VK_B
    ClickAt $cx $cy; ClickAt $cx $cy
    $c2 = [Probe]::Clicks
    Check 'click-block swallows clicks' ($c2 -eq $c1) "clicks $c1 -> $c2"
    Key @($CTRL, $SHIFT) $VK_B
    ClickAt $cx $cy
    $c3 = [Probe]::Clicks
    Check 'clicks flow again after unblock' ($c3 -gt $c2) "clicks $c2 -> $c3"

    # Alt+Tab block (control chord Alt+F15 proves the probe sees Alt+key normally)
    Key @($ALT) $F15
    Check 'probe sees Alt+F15 (control)' ([Probe]::AltF15 -ge 1) "altF15=$([Probe]::AltF15)"
    Key @($CTRL, $SHIFT) $VK_QUOTE
    $f0 = [Probe]::AltF15
    Key @($ALT) $F15
    Check 'other Alt chords pass once blocking is on' ([Probe]::AltF15 -gt $f0) "altF15 $f0 -> $([Probe]::AltF15)"
    Key @($ALT) $TAB
    Pump 500
    Check 'Alt+Tab swallowed while blocked' ([Probe]::AltTabs -eq 0) "altTabs=$([Probe]::AltTabs)"
    $f1 = [Probe]::AltF15
    Key @($ALT) $F15
    Check 'other Alt chords still pass after a swallowed Alt+Tab' ([Probe]::AltF15 -gt $f1) "altF15 $f1 -> $([Probe]::AltF15)"
    Key @($CTRL, $SHIFT) $VK_QUOTE

    # taskbar blur
    $t0 = TaskbarShot 'taskbar_0'
    Key @($CTRL, $SHIFT) $VK_D
    $t1 = TaskbarShot 'taskbar_blurred'
    Key @($CTRL, $SHIFT) $VK_D
    $t2 = TaskbarShot 'taskbar_restored'
    $dBlur = MeanDiff $t0 $t1; $dBack = MeanDiff $t0 $t2
    Check 'blur changes the taskbar' ($dBlur -gt 1.0) ("mean diff {0:N2}" -f $dBlur)
    Check 'blur off restores the taskbar' ($dBack -lt $dBlur / 2) ("mean diff {0:N2}" -f $dBack)
}
catch { $results.Add("ERR  $($_.Exception.Message)"); $failed = $true }
finally {
    if ($proc -and -not $proc.HasExited) {
        Pump 800 # let the probe hooks drain after the long pixel loops
        Key @($CTRL, $SHIFT) $VK_Q
        if (-not $proc.WaitForExit(8000)) { $proc.Kill(); $results.Add('WARN quit hotkey failed; killed') }
        else { $results.Add('PASS Ctrl+Shift+Q quits the app') }
    }
}
$results | ForEach-Object { Write-Output $_ }
Write-Output "evidence: $OutDir"
if ($failed) { exit 1 }
