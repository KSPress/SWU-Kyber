@echo off
rem Play on phones/tablets on the same Wi-Fi.
cd /d "%~dp0"
where py >nul 2>nul && (py -3 play.py --lan & goto :eof)
where python >nul 2>nul && (python play.py --lan & goto :eof)
echo Python 3 is needed: https://www.python.org/downloads/
pause
