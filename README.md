# Mopidy Container

A production-ready containerized [Mopidy](https://mopidy.com/) music server with comprehensive plugin support and Icecast streaming capabilities.

## Features

- **Multiple Music Sources**: Spotify, YouTube Music, SomaFM, Podcasts, and local files
- **Streaming Output**: MP3 streaming to Icecast server
- **Multiple Interfaces**: HTTP API (port 6680) and MPD protocol (port 6600)
- **Web Interface**: Built-in Muse web client
- **Flexible Configuration**: Environment variable-based configuration with sensible defaults
- **Security**: Runs as non-root user (UID 1000)
- **Modern Stack**: Ubuntu 25.04 base with latest Mopidy plugins

## Included Plugins

- **Mopidy-MPD**: MPD (Music Player Daemon) protocol support
- **Mopidy-Muse**: Modern web-based music player interface
- **Mopidy-Spotify**: Spotify integration (requires credentials)
- **Mopidy-YTMusic**: YouTube Music support
- **Mopidy-SomaFM**: Internet radio stations
- **Mopidy-Podcast**: Podcast support via OPML feeds

## Quick Start

### Using Docker

```bash
docker run -d \
  --name mopidy \
  -p 6680:6680 \
  -p 6600:6600 \
  -e SPOTIFY_CLIENT_ID=your_client_id \
  -e SPOTIFY_CLIENT_SECRET=your_client_secret \
  -e SPOTIFY_ENABLED=true \
  -e ICECAST_SOURCE_PASSWORD=your_icecast_password \
  registry.kube.sea.fudo.link/mopidy-server:latest
```

Access the web interface at http://localhost:6680/muse

### Using Docker Compose

See [docker-compose.yml](docker-compose.yml) for a complete example with volume mounts and all configuration options.

### Using Nix Flakes

Build the container image:
```bash
nix run .#build
```

Push to registry:
```bash
nix run .#push
```

Build and push in one command:
```bash
nix run
```

## Configuration

All configuration is done through environment variables. The entrypoint script processes these variables and generates the Mopidy configuration file at runtime.

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_HOST` | `0.0.0.0` | HTTP interface bind address |
| `HTTP_PORT` | `6680` | HTTP interface port |
| `MPD_ENABLED` | `true` | Enable MPD protocol support |
| `MPD_HOST` | `0.0.0.0` | MPD interface bind address |
| `MPD_PORT` | `6600` | MPD interface port |

### Spotify Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SPOTIFY_ENABLED` | `false` | Enable Spotify support |
| `SPOTIFY_CLIENT_ID` | _(empty)_ | Spotify API client ID |
| `SPOTIFY_CLIENT_SECRET` | _(empty)_ | Spotify API client secret |
| `SPOTIFY_BITRATE` | `320` | Audio quality (96, 160, 320) |

Get Spotify credentials from [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).

### Other Music Sources

| Variable | Default | Description |
|----------|---------|-------------|
| `SOMAFM_ENABLED` | `false` | Enable SomaFM internet radio |
| `YTMUSIC_ENABLED` | `false` | Enable YouTube Music |
| `PODCASTS_ENABLED` | `false` | Enable podcast support |

### Icecast Streaming

| Variable | Default | Description |
|----------|---------|-------------|
| `MOPIDY_ICECAST_HOST` | `icecast.mopidy.svc.cluster.local` | Icecast server hostname |
| `MOPIDY_ICECAST_PORT` | `8000` | Icecast server port |
| `ICECAST_MOUNT` | `/mopidy` | Mount point on Icecast server |
| `ICECAST_USER` | `source` | Icecast source username |
| `ICECAST_SOURCE_PASSWORD` | _(empty)_ | Icecast source password (required) |

### XDG Directories

| Variable | Default | Description |
|----------|---------|-------------|
| `XDG_CACHE_HOME` | `/var/lib/mopidy/.cache` | Cache directory |
| `XDG_CONFIG_HOME` | `/var/lib/mopidy/.config` | Configuration directory |
| `XDG_DATA_HOME` | `/var/lib/mopidy/.local/share` | Data directory |
| `XDG_MUSIC_DIR` | `/var/lib/mopidy/music` | Local music files directory |

## Volume Mounts

For persistent data and local music, mount these directories:

```bash
docker run -d \
  -v /path/to/music:/var/lib/mopidy/music:ro \
  -v mopidy-cache:/var/lib/mopidy/.cache \
  -v mopidy-data:/var/lib/mopidy/.local/share \
  ...
```

### Recommended Mounts

- `/var/lib/mopidy/music` - Local music files (read-only)
- `/var/lib/mopidy/.cache` - Mopidy cache (read-write)
- `/var/lib/mopidy/.local/share` - Mopidy data (read-write)
- `/var/lib/mopidy/ytmusic/auth.json` - YouTube Music authentication (if using YTMusic)
- `/etc/mopidy/podcast/Podcasts.opml` - Podcast feed list (if using podcasts)

## Architecture

### Build Process

The container uses a two-layer approach for dependencies:

1. **System Packages** (via apt): GStreamer, GObject Introspection, Cairo
2. **Python Packages** (via pip in venv): Mopidy and its extensions

This approach ensures compatibility between GStreamer and Python bindings while keeping Python packages isolated.

### Runtime Flow

1. Container starts with `docker-entrypoint.sh`
2. Environment variables are set with defaults
3. `mopidy.conf.tmpl` is processed with `envsubst` to generate final config
4. Mopidy launches with verbose logging (`-vv`)

### Audio Pipeline

```
Mopidy → audioconvert → audioresample → lamemp3enc → shout2send → Icecast
```

Audio is converted, resampled, encoded to MP3 (320kbps by default), and streamed to the configured Icecast server.

## Development

### Prerequisites

- [Nix with flakes enabled](https://nixos.org/download.html)
- Docker or Podman for testing

### Building Locally

```bash
# Build the image
nix run .#build

# Test the image
docker run --rm -it \
  -e ICECAST_SOURCE_PASSWORD=test \
  registry.kube.sea.fudo.link/mopidy-server:latest
```

### Modifying Configuration

Edit `mopidy.conf.tmpl` to add new configuration sections or modify existing ones. Use `${VARIABLE_NAME}` syntax for environment variable substitution.

Update `docker-entrypoint.sh` to add new environment variables with defaults.

## Deployment

### Kubernetes

Example deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mopidy
spec:
  selector:
    matchLabels:
      app: mopidy
  template:
    metadata:
      labels:
        app: mopidy
    spec:
      containers:
      - name: mopidy
        image: registry.kube.sea.fudo.link/mopidy-server:latest
        ports:
        - containerPort: 6680
          name: http
        - containerPort: 6600
          name: mpd
        env:
        - name: SPOTIFY_ENABLED
          value: "true"
        - name: SPOTIFY_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: mopidy-secrets
              key: spotify-client-id
        - name: SPOTIFY_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: mopidy-secrets
              key: spotify-client-secret
        - name: ICECAST_SOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mopidy-secrets
              key: icecast-password
        volumeMounts:
        - name: music
          mountPath: /var/lib/mopidy/music
          readOnly: true
        - name: cache
          mountPath: /var/lib/mopidy/.cache
      volumes:
      - name: music
        persistentVolumeClaim:
          claimName: music-library
      - name: cache
        emptyDir: {}
```

## Troubleshooting

### Mopidy won't start

Check that `ICECAST_SOURCE_PASSWORD` is set. Without it, the shout2send plugin will fail.

### Spotify not working

1. Verify credentials are correct
2. Ensure `SPOTIFY_ENABLED=true`
3. Check Mopidy logs for authentication errors
4. Verify your Spotify account is Premium (required for streaming)

### No audio streaming to Icecast

1. Verify Icecast server is reachable
2. Check `ICECAST_SOURCE_PASSWORD` matches your Icecast configuration
3. Verify mount point is configured in Icecast
4. Check Icecast logs for connection attempts

### Permission errors

The container runs as UID 1000. Ensure mounted volumes are writable by this user:

```bash
chown -R 1000:1000 /path/to/mopidy/data
```

## License

[Add your license here]

## Contributing

Contributions are welcome! Please open an issue or pull request.

## Resources

- [Mopidy Documentation](https://docs.mopidy.com/)
- [Mopidy Extensions](https://mopidy.com/ext/)
- [GStreamer Documentation](https://gstreamer.freedesktop.org/documentation/)
- [Icecast Documentation](https://icecast.org/docs/)
