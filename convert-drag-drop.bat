@echo off
echo.
echo ===========================================
echo  Markdown to Word Converter (Pandoc)
echo ===========================================
echo.

if "%~1" == "" goto :no_file

set "INPUT_FILE=%~1"
set "OUTPUT_FILE=%~dpn1.docx"

echo Converting:
echo Input:  %INPUT_FILE%
echo Output: %OUTPUT_FILE%
echo.

pandoc "%INPUT_FILE%" -o "%OUTPUT_FILE%" --from markdown+pipe_tables+fenced_code_blocks+backtick_code_blocks+definition_lists --to docx --highlight-style tango --standalone

if %ERRORLEVEL% EQU 0 goto :success
goto :error

:no_file
echo [ERROR] No file was provided.
echo Drag and drop a .md file onto this batch file to convert it.
echo.
pause
exit /b

:success
echo.
echo [SUCCESS] File converted successfully.
echo The Word file was saved next to the source file.
echo.
pause
exit /b

:error
echo.
echo [ERROR] Pandoc conversion failed.
echo.
pause
exit /b
