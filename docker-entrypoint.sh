#!/usr/bin/env sh
set -eu
set -a

# sensible defaults (envsubst doesn’t do ${VAR:-default}, so set them here)
: "${HTTP_HOST:=0.0.0.0}"
: "${HTTP_PORT:=6680}"
: "${MPD_ENABLED:=true}"
: "${MPD_HOST:=0.0.0.0}"
: "${MPD_PORT:=6600}"

: "${SPOTIFY_ENABLED:=false}"
: "${SPOTIFY_CLIENT_ID:=}"
: "${SPOTIFY_CLIENT_SECRET:=}"
: "${SPOTIFY_BITRATE:=320}"

: "${SOMAFM_ENABLED:=false}"
: "${YTMUSIC_ENABLED:=false}"
: "${PODCASTS_ENABLED:=false}"

: "${MOPIDY_ICECAST_HOST:=icecast.mopidy.svc.cluster.local}"
: "${MOPIDY_ICECAST_PORT:=8000}"
: "${ICECAST_MOUNT:=/mopidy}"
: "${ICECAST_USER:=source}"
: "${ICECAST_SOURCE_PASSWORD:=}"

: "${XDG_CACHE_HOME:=/var/lib/mopidy/.cache}"
: "${XDG_CONFIG_HOME:=/var/lib/mopidy/.config}"
: "${XDG_DATA_HOME:=/var/lib/mopidy/.local/share}"
: "${XDG_MUSIC_DIR:=/var/lib/mopidy/music}"

# render config from template
envsubst < /etc/mopidy/mopidy.conf.tmpl > /etc/mopidy/mopidy.conf

# run Mopidy
exec mopidy -vv --config /etc/mopidy/mopidy.conf
