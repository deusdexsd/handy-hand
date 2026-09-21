#!/bin/zsh
# Buduje i odpala kod dowodowy Fazy 0. Uruchamiaj z terminala (nie przez `open`):
# odpalony z terminala dziedziczy uprawnienia terminala i loguje do Phase0/logs.
cd "$(dirname "$0")"
./build-app.sh > /dev/null && exec ~/Library/Caches/MidniteDockBuild/MidniteDockPhase0.app/Contents/MacOS/Phase0Spike
