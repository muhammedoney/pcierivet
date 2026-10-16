@echo off
setlocal EnableExtensions
rem Zip the repo with .git, leaving regenerable files out.
rem   scripts\zip_project.cmd
rem   scripts\zip_project.cmd D:\rivet-src.zip

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0zip_project.ps1" %*
exit /b %ERRORLEVEL%
