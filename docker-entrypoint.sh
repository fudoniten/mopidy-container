#!/usr/bin/env sh
# Docker entrypoint for Mopidy container
# This script sets up environment variables with sensible defaults,
# renders the Mopidy configuration from a template, and starts Mopidy.

set -eu  # Exit on error and undefined variables
set -a   # Automatically export all variables for envsubst

# Set sensible defaults for all configuration variables
# Note: envsubst doesn't support ${VAR:-default} syntax, so we set defaults here
## HTTP and MPD Interface Configuration
: "${HTTP_HOST:=0.0.0.0}"
: "${HTTP_PORT:=6680}"
: "${MPD_ENABLED:=true}"
: "${MPD_HOST:=0.0.0.0}"
: "${MPD_PORT:=6600}"

## Music Source Configuration
# Spotify (requires client_id and client_secret)
: "${SPOTIFY_ENABLED:=false}"
: "${SPOTIFY_CLIENT_ID:=}"
: "${SPOTIFY_CLIENT_SECRET:=}"
: "${SPOTIFY_BITRATE:=320}"

# Other music sources
: "${SOMAFM_ENABLED:=false}"
: "${YTMUSIC_ENABLED:=false}"
: "${PODCASTS_ENABLED:=false}"

## Icecast Streaming Configuration
# Default host assumes Kubernetes deployment with an Icecast service
: "${MOPIDY_ICECAST_HOST:=icecast.mopidy.svc.cluster.local}"
: "${MOPIDY_ICECAST_PORT:=8000}"
: "${ICECAST_MOUNT:=/mopidy}"
: "${ICECAST_USER:=source}"
: "${ICECAST_SOURCE_PASSWORD:=}"

## XDG Base Directory Specification
# These directories should be mounted as volumes for persistence
: "${XDG_CACHE_HOME:=/var/lib/mopidy/.cache}"
: "${XDG_CONFIG_HOME:=/var/lib/mopidy/.config}"
: "${XDG_DATA_HOME:=/var/lib/mopidy/.local/share}"
: "${XDG_MUSIC_DIR:=/var/lib/mopidy/music}"

## Generate Configuration and Start Mopidy
# Render the Mopidy configuration from template using environment variable substitution
envsubst < /etc/mopidy/mopidy.conf.tmpl > /etc/mopidy/mopidy.conf

# Start Mopidy with verbose logging (-vv)
# Using exec to replace the shell process (proper signal handling)
exec mopidy -vv --config /etc/mopidy/mopidy.conf
