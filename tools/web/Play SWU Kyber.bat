@echo off
rem Starts a local web server for the SWU Kyber browser build and opens it.
cd /d "%~dp0"
where py >nul 2>nul && (py -3 play.py & goto :eof)
where python >nul 2>nul && (python play.py & goto :eof)
echo Python 3 is needed to run the local web server: https://www.python.org/downloads/
pause
