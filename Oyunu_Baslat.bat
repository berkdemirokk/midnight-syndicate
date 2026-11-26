@echo off
rem Midnight Syndicate: starts the game from the project with the Godot 4.7.2 binary on this PC.
rem (The exported .exe is unsigned and Windows Smart App Control blocks it; this start needs no export.)
set GODOT=C:\Users\berk\tools\godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot bulunamadi: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0game"
