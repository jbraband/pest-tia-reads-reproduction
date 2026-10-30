# PowerShell version of repro.sh (Windows PowerShell 5.1 or PowerShell 7+).
# Shows the bug on stock Pest, then the same steps with patches/read-capture.patch applied.
# Needs PCOV or Xdebug (coverage mode), and a committed git working tree.
$ErrorActionPreference = 'Stop'

# Without a coverage driver Pest skips TIA and every --tia run is a full run.
if (-not ((& php -m) -match '^(pcov|xdebug)$')) {
    throw 'PCOV or Xdebug is not loaded (php -m), so Pest would skip TIA. Install one and re-run.'
}

if (-not (Test-Path (Join-Path $PSScriptRoot '.env'))) {
    Copy-Item (Join-Path $PSScriptRoot '.env.example') (Join-Path $PSScriptRoot '.env')
}

$Patch = 'patches/read-capture.patch'
$PestDir = 'vendor/pestphp/pest'
$View = 'resources/views/welcome.blade.php'
$ViewPath = Join-Path $PSScriptRoot $View
$patched = $false

function Invoke-Native {
    param([string] $Command, [string[]] $Arguments, [switch] $AllowFailure)

    & $Command @Arguments

    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw "$Command $($Arguments -join ' ') exited with $LASTEXITCODE"
    }
}

function Edit-View {
    $source = [IO.File]::ReadAllText($ViewPath)
    [IO.File]::WriteAllText($ViewPath, $source.Replace('<meta name="viewport"', '<meta name="x-viewport"'))
    Invoke-Native git '--no-pager', 'diff', '--', $View
}

Push-Location $PSScriptRoot

try {
    Write-Host '== BUG (stock Pest)'
    Write-Host '== 1. record a fresh baseline'
    Invoke-Native php 'vendor/bin/pest', '--tia', '--fresh'

    Write-Host "== 2. edit ${View}: rename the viewport meta tag"
    Edit-View

    Write-Host '== 3. --tia: expected ConventionsTest re-run and failed, actual it replays (1 affected, 2 replayed)'
    Invoke-Native php 'vendor/bin/pest', '--tia' -AllowFailure

    Write-Host '== 4. plain run: ConventionsTest fails'
    Invoke-Native php 'vendor/bin/pest' -AllowFailure

    Write-Host "== FIX ($Patch applied to $PestDir)"
    Invoke-Native git 'checkout', '-q', '--', $View
    Invoke-Native git 'apply', "--directory=$PestDir", $Patch
    $patched = $true

    Write-Host '== 5. record a fresh baseline'
    Invoke-Native php 'vendor/bin/pest', '--tia', '--fresh'

    Write-Host '== 6. same edit'
    Edit-View

    Write-Host '== 7. --tia: 2 affected, ConventionsTest fails'
    Invoke-Native php 'vendor/bin/pest', '--tia' -AllowFailure
}
finally {
    & git checkout -q -- $View

    if ($patched) {
        & git apply -R "--directory=$PestDir" $Patch
    }

    Pop-Location
}
