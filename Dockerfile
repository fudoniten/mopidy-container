FROM debian:bookworm-slim

# Base libs + GStreamer + TLS + Mopidy runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl python3 python3-pip python3-gi gir1.2-gstreamer-1.0 \
      gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
      gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav \
      glib-networking fonts-dejavu && \
    rm -rf /var/lib/apt/lists/*

# Mopidy + plugins (pip is simplest here)
RUN pip3 install --no-cache-dir \
      mopidy \
      Mopidy-MPD \
      Mopidy-Iris \
      Mopidy-Muse \
      Mopidy-Podcast \
      Mopidy-SomaFM \
      Mopidy-YouTubeMusic \
      Mopidy-Spotify

# Spotify GStreamer plugin (.deb) — check the latest release/tag & arch first
ADD https://github.com/kingosticks/gst-plugins-rs-build/releases/download/gst-plugin-spotify_0.15.0-alpha.1-2/gst-plugin-spotify_0.15.0~alpha.1-2_amd64.deb /tmp/spotify.deb
RUN apt-get update && apt-get install -y /tmp/spotify.deb && rm -rf /var/lib/apt/lists/* /tmp/spotify.deb

# Non-root user
RUN useradd -m -u 1000 mopidy
USER mopidy
WORKDIR /home/mopidy

COPY mopidy.conf.tmpl /etc/mopidy/mopidy.conf.tmpl
COPY docker-entrypoint.sh /bin/docker-entrypoint.sh
RUN chmod +x /bin/docker-entrypoint.sh

# Minimal config (or mount yours)
EXPOSE 6680 6600
ENTRYPOINT ["/bin/docker-entrypoint.sh"]
