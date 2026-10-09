#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --editor --import
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_match_engine.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_progress.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --audio-driver Dummy -- --smoke
