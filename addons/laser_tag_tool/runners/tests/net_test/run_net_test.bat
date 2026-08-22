@echo off
rem Three-process ENet replication test for the destructible proxy.
rem Run from the lasertag project root. Godot must be on PATH, or set GODOT.
rem Expect three PASS lines: HOST PASS, CLIENT PASS, LATE PASS.
if "%GODOT%"=="" set GODOT=godot
start "lt_net_host" /b %GODOT% --headless --path . -s res://addons/laser_tag_tool/runners/tests/net_test/net_host.gd
timeout /t 4 /nobreak >nul
start "lt_net_client" /b %GODOT% --headless --path . -s res://addons/laser_tag_tool/runners/tests/net_test/net_client.gd
timeout /t 7 /nobreak >nul
%GODOT% --headless --path . -s res://addons/laser_tag_tool/runners/tests/net_test/net_late.gd
