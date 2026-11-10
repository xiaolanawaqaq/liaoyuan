#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Godot 4 headless 语法检查和模拟烟测
if [[ "${1:-}" == "test" ]]; then
  godot --headless --path . --script scripts/test_sim.gd
  exit 0
fi

godot --editor --path .
