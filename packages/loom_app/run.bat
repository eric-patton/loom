@echo off
REM Launches the Loom desktop editor on Windows.
REM Any extra args (e.g. --profile, --release) are forwarded to flutter.
pushd "%~dp0"
flutter run -d windows %*
popd
