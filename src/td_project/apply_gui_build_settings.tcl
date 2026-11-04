# Persist the CLI-proven settings in the GUI project (.al).
# Run with: td_commands_prompt.exe apply_gui_build_settings.tcl
import_device eagle_s20.db -package EG4S20BG256
set proj_dir [file dirname [info script]]
open_project [file join $proj_dir lab_ex5_i2s_v1.0.al]
set_param gate map_mode auto -run syn_1 -projmngr
set_user_params -run syn_1 -params {
    {gate mapmacro_opt_timing high}
    {gate map_opt_area high}
    {gate add_map_lut_struct high}
    {gate multi_thread_mapping partition}
    {gate merge_tiny_lut on}
}
set_param gate opt_area high -run syn_1 -projmngr
set_param gate pack_effort high -run syn_1 -projmngr
set_param place seed 51 -run phy_1 -projmngr
set_param place effort high -run phy_1 -projmngr
set_param route fix_hold on -run phy_1 -projmngr
set_seed_param -num 1 -init 51 -step 1 -jobs 1 -save 1 -endStep bitgen -rwns 0 -pwns 0 -congestion 100 -filter off
set_user_params -run phy_1 -params {
    {place opt_timing high}
    {place ofv 70}
    {place opt_max_density 50}
    {place target_density 0.6}
    {place target_density_pp 0.7}
    {place aggressive_opt 20}
    {place enhanced_beeline_opt 2}
    {place enhanced_gp on}
    {place non_crit_opt on}
    {place post_place_opt high}
    {place enable_congestion_recovery on}
    {route post_route_opt high}
    {route swap_pin off}
}
close_project
puts "GUI_BUILD_SETTINGS_SAVED"
