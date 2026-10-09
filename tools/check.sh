#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --editor --import
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_match_engine.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_progress.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_objectives.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_generated_number.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_generated_frame.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_board_contour.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_ui_pool.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --audio-driver Dummy --script res://tests/test_content.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_colony.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_colony_map.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_expeditions.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_heroes.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --script res://tests/test_city_management.gd
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --audio-driver Dummy -- --smoke
