#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh Tests/run.sh
sh Tests/run-notes.sh
sh Tests/run-shelf.sh
sh Tests/run-actions.sh
sh Tests/run-media.sh
sh Tests/run-settings.sh
sh Tests/run-tasks.sh
