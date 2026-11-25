#!/bin/bash
G="C:/Users/berk/tools/godot/Godot_v4.7.2-stable_win64_console.exe"
for p in low medium high; do
  "$G" --path "C:/Users/berk/car race/game" --resolution 1920x1080 --position 40,40 res://devtools/capture_boot.tscn -- --capture=city_presets --preset=$p --timeout=600 > "C:/Users/berk/car race/evidence/logs/city_presets_opt_$p.log" 2>&1
  echo "$p exit=$?" >> "C:/Users/berk/car race/evidence/logs/opt_run_presets_status.txt"
done
echo done >> "C:/Users/berk/car race/evidence/logs/opt_run_presets_status.txt"
