param(
    [string]$Iverilog = 'D:/app/34_iverilog/iverilog/bin/iverilog.exe',
    [string]$Vvp = 'D:/app/34_iverilog/iverilog/bin/vvp.exe'
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    & $Iverilog -g2012 -s test_refresh_arbitration -o test_refresh_arbitration.vvp test_refresh_arbitration.v behavioral_video_fifo.v ../../src/user_source/hdl_source/sdram_refresh_guard.v ../../src/user_source/hdl_source/media_sdram_write_cdc.v ../../src/user_source/hdl_source/media_frame_reader.v ../../src/user_source/hdl_source/fifo_prefetch_2.v
    if ($LASTEXITCODE -ne 0) { throw 'Arbitration test compilation failed' }
    & $Vvp test_refresh_arbitration.vvp
    if ($LASTEXITCODE -ne 0) { throw 'Arbitration test failed' }
} finally { Pop-Location }
