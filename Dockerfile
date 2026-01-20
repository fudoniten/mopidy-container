# Mopidy Music Server Container
# Base: Ubuntu 25.04 with GStreamer and Python bindings
FROM docker.io/library/ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies for Mopidy and GStreamer
# - Python 3 with GObject Introspection and Cairo bindings (for GStreamer)
# - GStreamer core and plugins (base, good, bad, ugly, libav)
# - Network support and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gettext-base \
      python3 python3-venv python3-gi python3-cairo \
      gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 \
      gstreamer1.0-tools gstreamer1.0-plugins-base \
      gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
      gstreamer1.0-plugins-ugly gstreamer1.0-libav \
      glib-networking fonts-dejavu \
  && rm -rf /var/lib/apt/lists/*

# Create a Python virtual environment with access to system site-packages
# This allows pip-installed Mopidy to use system GStreamer bindings
RUN python3 -m venv --system-site-packages /opt/mopidy-venv
ENV PATH="/opt/mopidy-venv/bin:${PATH}"

# Install Mopidy and extensions via pip
# Using --pre for Mopidy-Spotify 5.x (pre-release version required for latest features)
# Installed extensions:
# - Mopidy-MPD: MPD protocol support
# - Mopidy-Muse: Modern web interface
# - Mopidy-Podcast: Podcast support
# - Mopidy-SomaFM: Internet radio
# - Mopidy-YTMusic: YouTube Music integration
# - Mopidy-Spotify: Spotify integration
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir --pre \
      mopidy Mopidy-MPD Mopidy-Muse \
      Mopidy-Podcast Mopidy-SomaFM Mopidy-YTMusic Mopidy-Spotify

# Install GStreamer Spotify plugin (binary package for amd64)
# This provides the gst-plugin-spotify element for direct Spotify streaming
ADD https://github.com/kingosticks/gst-plugins-rs-build/releases/download/gst-plugin-spotify_0.15.0-alpha.1-2/gst-plugin-spotify_0.15.0.alpha.1-2_amd64.deb /tmp/spotify.deb
RUN apt-get update && apt-get install -y /tmp/spotify.deb && rm -rf /var/lib/apt/lists/* /tmp/spotify.deb

# Switch to non-root user for security
# UID/GID 1000 is common for the first user on most systems
USER 1000:1000
ENV HOME=/home/mopidy
WORKDIR /home/mopidy

# Copy configuration template and entrypoint script
# The entrypoint script renders the template with environment variables at runtime
COPY --chown=1000:1000 mopidy.conf.tmpl /etc/mopidy/mopidy.conf.tmpl
COPY --chown=1000:1000 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose ports:
# - 6680: HTTP interface (web UI and API)
# - 6600: MPD protocol
EXPOSE 6680 6600

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
