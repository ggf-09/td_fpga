param(
    [string]$Iverilog = 'D:/app/34_iverilog/iverilog/bin/iverilog.exe',
    [string]$Vvp = 'D:/app/34_iverilog/iverilog/bin/vvp.exe'
)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    python ./make_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Vector generation failed' }
    python ./prepare_startup_test.py
    if ($LASTEXITCODE -ne 0) { throw 'Startup connection extraction failed' }
    python ./prepare_sequence_integration.py
    if ($LASTEXITCODE -ne 0) { throw 'Playback state machine extraction failed' }
    python ./make_equalizer_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Equalizer reference generation failed' }
    $hdl = '../../src/user_source/hdl_source'
    $cases = @{
        test_lrc_loader = @("$hdl/audio/fat_lrc_loader.v")
        test_overlay = @("$hdl/audio/runtime_lyric_overlay.v")
        test_manager = @("$hdl/audio/runtime_lyric_manager.v", "$hdl/audio/fat_lrc_loader.v", "$hdl/SD/fat32_file_streamer.v", "$hdl/reset_sync.v")
        test_manager_banked = @("$hdl/audio/runtime_lyric_manager.v", "$hdl/audio/fat_lrc_loader.v", "$hdl/SD/fat32_file_streamer.v", "$hdl/reset_sync.v")
        test_spectrum = @("$hdl/promax_audio_spectrum.v", "$hdl/video_timing_ctrl.v")
        test_audio_fifo = @("$hdl/audio/fat_wav_player.v")
        test_video_startup = @("$hdl/video_timing_ctrl.v", "$hdl/osd_overlay_24.v", "$hdl/status_osd_overlay.v", "$hdl/rgb_video_adapter.v", "$hdl/video_rgb_to_axis_640x480.v")
        test_playback_controls = @("$hdl/playback_controls.v")
        test_volume_switch = @("$hdl/playback_controls.v")
        test_equalizer_controls = @("$hdl/playback_controls.v")
        test_music_equalizer = @("$hdl/audio/music_equalizer.v")
        test_clip_timeout = @("$hdl/audio/music_equalizer.v")
        test_equalizer_osd = @("$hdl/param_osd_overlay.v", "$hdl/video_timing_ctrl.v")
        test_playback_volume = @("$hdl/playback_controls.v")
        test_playback_sequence = @("$hdl/playback_sequence.v")
        test_sequence_integration = @("$hdl/playback_sequence.v", 'sequence_top_fragment.v')
    }
    foreach ($name in @('test_lrc_loader','test_overlay','test_manager','test_manager_banked','test_spectrum','test_audio_fifo','test_video_startup','test_playback_controls','test_volume_switch','test_equalizer_controls','test_music_equalizer','test_clip_timeout','test_equalizer_osd','test_playback_volume','test_playback_sequence','test_sequence_integration')) {
        $testFile = if ($name -eq 'test_playback_volume') { 'test_playback_controls.v' } else { "$name.v" }
        & $Iverilog -g2012 -s $name -o "$name.vvp" $testFile @($cases[$name])
        if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $name" }
        & $Vvp "$name.vvp"
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $name" }
    }
    & ./run_refresh.ps1 -Iverilog $Iverilog -Vvp $Vvp
    & ./run_arbitration.ps1 -Iverilog $Iverilog -Vvp $Vvp
    python ./check_equalizer_response.py
    if ($LASTEXITCODE -ne 0) { throw 'Equalizer frequency response failed' }
} finally { Pop-Location }
