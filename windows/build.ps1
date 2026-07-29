[CmdletBinding()]
param(
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$WindowsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir = Join-Path $WindowsDir ".venv"

if (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
    & $Python -m venv $VenvDir
}

$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
& $VenvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed" }
& $VenvPython -m pip install -r (Join-Path $WindowsDir "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "dependency installation failed" }

Push-Location $WindowsDir
try {
    $env:PYTHONPATH = Join-Path $WindowsDir "app"
    & $VenvPython -m unittest discover -s "tests" -v
    if ($LASTEXITCODE -ne 0) { throw "tests failed" }
    & $VenvPython -m PyInstaller --noconfirm --clean "WhisperKey.spec"
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed" }

    $Version = & $VenvPython -c "import whisperkey; print(whisperkey.__version__)"
    if ($LASTEXITCODE -ne 0) { throw "version lookup failed" }
    $Archive = Join-Path $WindowsDir "dist\WhisperKey-Windows-x64-$Version.zip"
    if (Test-Path $Archive) {
        Remove-Item -LiteralPath $Archive
    }
    Compress-Archive -Path (Join-Path $WindowsDir "dist\WhisperKey\*") -DestinationPath $Archive
    Write-Host "Built $Archive"
}
finally {
    Pop-Location
}
