#!/bin/bash
# Builds the release in _build/prod/rel/fourcards
set -euo pipefail

export MIX_ENV=prod

mix local.hex --force
mix local.rebar --force
mix release
