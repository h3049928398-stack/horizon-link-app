@echo off
cd /d "%~dp0"
if not exist "flutter_app\build\web\main.dart.js" (
  echo Build the Flutter preview first: cd flutter_app and run ..\flutter.ps1 build web --no-pub --no-web-resources-cdn
  pause
  exit /b 1
)
echo Horizon Link Flutter preview: http://localhost:5180/
python -m http.server 5180 --bind 127.0.0.1 --directory flutter_app/build/web
pause
