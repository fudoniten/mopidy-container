FROM docker.io/library/ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive

# System Python + GI/Cairo + GStreamer runtime (no building needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gettext-base \
      python3 python3-venv python3-gi python3-cairo \
      gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 \
      gstreamer1.0-tools gstreamer1.0-plugins-base \
      gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
      gstreamer1.0-plugins-ugly gstreamer1.0-libav \
      glib-networking fonts-dejavu \
  && rm -rf /var/lib/apt/lists/*

# Venv that can import the system site-packages (so gi/pycairo come from apt)
RUN python3 -m venv --system-site-packages /opt/mopidy-venv
ENV PATH="/opt/mopidy-venv/bin:${PATH}"

# Pip-only things go into the venv; Mopidy-Spotify 5.x is pre-release -> use --pre
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir --pre \
      mopidy Mopidy-MPD Mopidy-Muse \
      Mopidy-Podcast Mopidy-SomaFM Mopidy-YTMusic Mopidy-Spotify

# Spotify GStreamer source plugin (.deb) – adjust arch if not amd64
ADD https://github.com/kingosticks/gst-plugins-rs-build/releases/download/gst-plugin-spotify_0.15.0-alpha.1-2/gst-plugin-spotify_0.15.0.alpha.1-2_amd64.deb /tmp/spotify.deb
RUN apt-get update && apt-get install -y /tmp/spotify.deb && rm -rf /var/lib/apt/lists/* /tmp/spotify.deb


# Non-root user
USER 1000:1000
ENV HOME=/home/mopidy
WORKDIR /home/mopidy

# Config template + entrypoint
COPY --chown=1000:1000 mopidy.conf.tmpl /etc/mopidy/mopidy.conf.tmpl
COPY --chown=1000:1000 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 6680 6600
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
