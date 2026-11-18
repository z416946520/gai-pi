@echo off
rem Launch the gai-pi desktop shell. Requires Godot 4.6.3 under .dependency\godot (see README).
setlocal
cd /d "%~dp0"
if not exist ".dependency\godot\Godot_v4.6.3-stable_win64.exe" (
	echo Godot 4.6.3 not found under .dependency\godot.
	echo See README "Environment" for the download step.
	pause
	exit /b 1
)
start "" ".dependency\godot\Godot_v4.6.3-stable_win64.exe" --path .
