#!/bin/bash
G="C:/Users/berk/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
"$G" --path "C:/Users/berk/car race/game" --resolution 1920x1080 --position 40,40 res://devtools/capture_boot.tscn -- --capture=race_city --preset=high --timeout=600 > "C:/Users/berk/car race/evidence/logs/race_city_opt_high.log" 2>&1
echo "race_city exit=$?" >> "C:/Users/berk/car race/evidence/logs/opt_run_final_status.txt"
"$G" --headless --fixed-fps 60 --path "C:/Users/berk/car race/game" -s res://tests/run_tests.gd > "C:/Users/berk/car race/evidence/logs/opt_tests_full.log" 2>&1
echo "suite exit=$?" >> "C:/Users/berk/car race/evidence/logs/opt_run_final_status.txt"
echo done >> "C:/Users/berk/car race/evidence/logs/opt_run_final_status.txt"
