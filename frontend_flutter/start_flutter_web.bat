@echo off
cd /d "%~dp0"
flutter clean
flutter pub get
flutter run -d edge
pause
