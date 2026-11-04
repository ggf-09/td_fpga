param(
    [string]$Iverilog = 'D:/app/34_iverilog/iverilog/bin/iverilog.exe',
    [string]$Vvp = 'D:/app/34_iverilog/iverilog/bin/vvp.exe'
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    python ./prepare_refresh_test.py
    if ($LASTEXITCODE -ne 0) { throw 'Refresh test setup failed' }
    & $Iverilog -g2012 -I . -s test_refresh -o test_refresh.vvp test_refresh.v sdr_init_ref_public.v
    if ($LASTEXITCODE -ne 0) { throw 'Refresh test compilation failed' }
    & $Vvp test_refresh.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Refresh test failed' }
} finally { Pop-Location }
