@echo off
chcp 65001 > nul
echo.
echo ===========================================
echo  DP-800 -- Build Study Guide DOCX
echo ===========================================
echo.

set PYTHONIOENCODING=utf-8

python scripts/build_docx.py %*

if %ERRORLEVEL% EQU 0 (
    echo.
    echo DOCX build completed. See the path printed above.
) else (
    echo.
    echo ERROR: DOCX build failed. See the log above.
)

echo.
pause
