@echo off
REM Runs the loom_app test suite. Pass-through args let you scope a run:
REM   test                                    -> everything (unit + widget + integration)
REM   test test\unit                          -> just unit tests
REM   test test\widget\interface_tab_test.dart -> one file
REM   test --name "round-trip"                -> by test name regex
pushd "%~dp0"
flutter test %*
popd
