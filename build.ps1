# Builds reading_focus_overlay.exe with the local V toolchain.
#   .\build.ps1            release build (windowed, no console) -> reading_focus_overlay.exe
#   .\build.ps1 -Console   same, but keeps a console window (prints --help / --demo output)
#   .\build.ps1 -Test      run the unit tests instead of building
param(
    [switch]$Console,
    [switch]$Test,
    [string]$V = 'C:\git\v\v.exe',
    [string]$Out = 'reading_focus_overlay.exe'
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
# vraster / vfonts / vfa_icons live in the shared lib folder
$path = 'C:\git\v_projects\lib|@vlib|@vmodules'
if ($Test) {
    & $V -cc gcc -path $path test .
    exit $LASTEXITCODE
}
$subsystem = if ($Console) { 'console' } else { 'windows' }
& $V -cc gcc -prod -subsystem $subsystem -path $path -o $Out .
$code = $LASTEXITCODE
Remove-Item -ErrorAction SilentlyContinue "$Out.manifest"
exit $code
