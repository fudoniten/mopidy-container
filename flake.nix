{
  description = "Mopidy music server running in a container.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        # ----- Mopidy config template (INI) -----
        defaultConfig = pkgs.writeText "mopidy.conf.tmpl"
          (lib.generators.toINI { } {
            http = {
              hostname = "0.0.0.0";
              port = 6680;
            };
            mpd = {
              enabled = true;
              hostname = "0.0.0.0";
              port = 6600;
            };

            iris.enabled = true;
            muse.enabled = true;
            somafm.enabled = true;

            spotify = {
              enabled = "\${SPOTIFY_ENABLED}";
              client_id = "\${SPOTIFY_CLIENT_ID}";
              client_secret = "\${SPOTIFY_CLIENT_SECRET}";
              bitrate = 320;
            };

            ytmusic = {
              enabled = "\${YOUTUBE_MUSIC_ENABLED}";
              auth_json = "/var/lib/mopidy/ytmusic/auth.json";
            };

            podcast = {
              enabled = "\${PODCASTS_ENABLED}";
              browse_root = "/etc/mopidy/podcast/Podcasts.opml";
            };

            musicbox_webclient = {
              enabled = true;
              on_track_click = "PLAY_NOW";
            };

            logging.verbosity = "2";

            audio.output = lib.concatStringsSep " " [
              "audioconvert"
              "!"
              "audioresample"
              "!"
              "lamemp3enc"
              "!"
              "shout2send"
              "async=false"
              "mount=/mopidy"
              "port=8000"
              "ip=icecast"
              "username=source"
              "password=\${ICECAST_SOURCE_PASSWORD}"
            ];
          });

        # ----- Paths for GI typelibs and GStreamer plugins -----
        gst = pkgs.gst_all_1;
        gstPlugins = with gst; [
          gst-plugins-base
          gst-plugins-good
          gst-plugins-bad
          gst-plugins-ugly
          gst-libav
          gst-plugins-rs # includes spotifyaudiosrc
        ];

        giPath = lib.makeSearchPathOutput "out" "lib/girepository-1.0"
          ([ pkgs.glib gst.gstreamer ] ++ gstPlugins);

        gstPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" gstPlugins;

        # Python/site-packages that Mopidy (wrapper) should see at runtime.
        # Keep this minimal: only extras not already in the Mopidy/extension drv closures.
        pyExtras = with pkgs.python3Packages; [
          cachetools
          pytube
          uritools
          ytmusicapi
        ];

        # Build a proper PYTHONPATH over the out paths' site-packages
        pyPath = lib.makeSearchPathOutput "out"
          "lib/${pkgs.python3.libPrefix}/site-packages" ([
            pkgs.mopidy
            pkgs.mopidy-mpd
            pkgs.mopidy-spotify
            pkgs.mopidy-iris
            pkgs.mopidy-somafm
            pkgs.mopidy-podcast
            pkgs.mopidy-ytmusic
            pkgs.mopidy-muse
          ] ++ pyExtras);

        etcLayer = pkgs.runCommand "etc-mopidy" { } ''
          mkdir -p $out/etc/mopidy
          cp ${defaultConfig} $out/etc/mopidy/mopidy.conf.tmpl
        '';

        entrypoint = pkgs.writeShellScriptBin "start-mopidy" ''
          set -euo pipefail
          # ---- TLS / HTTPS for GLib ----
          export GIO_EXTRA_MODULES='${pkgs.glib-networking}/lib/gio/modules'
          export SSL_CERT_FILE='${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt'
          export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"
          export G_TLS_CA_FILE="$SSL_CERT_FILE"

          # ---- GStreamer + GI (for Mopidy’s Python) ----
          export GI_TYPELIB_PATH='${giPath}'
          export GST_PLUGIN_SYSTEM_PATH_1_0='${gstPluginPath}'
          export GST_PLUGIN_SYSTEM_PATH="$GST_PLUGIN_SYSTEM_PATH_1_0"
          export GST_PLUGIN_SCANNER_1_0='${gst.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner'
          export GST_PLUGIN_SCANNER="$GST_PLUGIN_SCANNER_1_0"

          # ---- Python path for Mopidy extensions that need extra deps ----
          export PYTHONPATH='${pyPath}':"${"PYTHONPATH:-"}"

          # ---- XDG dirs for caches ----
          export XDG_CACHE_HOME=/var/lib/mopidy/.cache
          export XDG_CONFIG_HOME=/var/lib/mopidy/.config
          export XDG_DATA_HOME=/var/lib/mopidy/.local/share

          # Render config template
          ${pkgs.gettext}/bin/envsubst < /etc/mopidy/mopidy.conf.tmpl > /etc/mopidy/mopidy.conf || true

          exec mopidy --config /etc/mopidy/mopidy.conf -vv
        '';

        # ----- Docker image -----
        mopidyContainer = pkgs.dockerTools.buildLayeredImage {
          name = "registry.kube.sea.fudo.link/mopidy-server";
          tag = "0.0.1";

          contents = [
            etcLayer
            entrypoint

            # Mopidy + extensions (binaries + their site-packages)
            pkgs.mopidy
            pkgs.mopidy-mpd
            pkgs.mopidy-spotify
            pkgs.mopidy-iris
            pkgs.mopidy-moped
            pkgs.mopidy-musicbox-webclient
            pkgs.mopidy-somafm
            pkgs.mopidy-podcast
            pkgs.mopidy-ytmusic
            pkgs.mopidy-muse

            # GStreamer core + plugins
            gst.gstreamer
          ] ++ gstPlugins ++ [
            # TLS & GI deps
            pkgs.cacert
            pkgs.glib
            pkgs.glib-networking
            pkgs.gobject-introspection

            # Minimal tools/fonts (optional)
            pkgs.coreutils
            pkgs.bashInteractive
            pkgs.fontconfig
            pkgs.dejavu_fonts

            # Python-only extras needed at runtime (e.g., uritools for podcast)
            # (their site-packages are exposed via PYTHONPATH above)
          ] ++ pyExtras;

          enableFakechroot = true;
          fakeRootCommands = ''
            ${pkgs.dockerTools.shadowSetup}
            groupadd -g 1000 mopidy
            useradd -u 1000 -g mopidy -d /var/lib/mopidy -M -r mopidy

            mkdir -p /var/lib/mopidy/.cache /var/lib/mopidy/.config /var/lib/mopidy/.local/share
            mkdir -p /var/lib/ytmusic
            mkdir -p /var/cache/fontconfig

            chown -R mopidy:mopidy /var/lib/mopidy
            chown -R mopidy:mopidy /var/cache/fontconfig

            mkdir -p /etc/mopidy
            chown mopidy:mopidy /etc/mopidy

            ln -s ${pkgs.fontconfig.out}/etc/fonts /etc/fonts || true
          '';

          config = {
            User = "mopidy";
            WorkingDir = "/var/lib/mopidy";
            ExposedPorts."6680/tcp" = { };
            ExposedPorts."6600/tcp" = { };
            Env = [
              "PYTHONUNBUFFERED=1"
              "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
              # App-level envs (filled by your Deployment/Secret/ConfigMap)
              "SPOTIFY_ENABLED=" # "true"/"false"
              "SPOTIFY_CLIENT_ID="
              "SPOTIFY_CLIENT_SECRET="
              "YOUTUBE_MUSIC_ENABLED="
              "PODCASTS_ENABLED="
              "ICECAST_SOURCE_PASSWORD="
            ];
            Volumes = {
              "/var/lib/mopidy" = { };
              "/var/lib/ytmusic" = { };
            };
            Entrypoint = [ "/bin/start-mopidy" ];
          };
        };

        # ----- skopeo-based pusher app -----
        deployContainer = let
          policyJson = pkgs.writeText "containers-policy.json"
            (builtins.toJSON {
              default = [{ type = "reject"; }];
              transports = {
                docker = { "" = [{ type = "insecureAcceptAnything"; }]; };
                docker-archive = {
                  "" = [{ type = "insecureAcceptAnything"; }];
                };
              };
            });
        in pkgs.writeShellApplication {
          name = "deployContainer";
          runtimeInputs = [ pkgs.skopeo pkgs.coreutils pkgs.git pkgs.jq ];
          text = ''
            set -euo pipefail
            TAR=${self.packages.${system}.mopidyContainer}
            DEST="docker://registry.kube.sea.fudo.link/mopidy-server"
            LATEST="docker://registry.kube.sea.fudo.link/mopidy-server:latest"
            echo "pushing $TAR -> $DEST ..."
            skopeo copy --policy ${policyJson} --all docker-archive:"$TAR" "$DEST"
            skopeo copy --policy ${policyJson} --all docker-archive:"$TAR" "$LATEST"
            echo "done."
          '';
        };

      in {
        packages.default = mopidyContainer;
        packages.mopidyContainer = mopidyContainer;
        packages.deployContainer = deployContainer;

        apps.default = {
          type = "app";
          program = "${deployContainer}/bin/deployContainer";
        };
        apps.deployContainer = {
          type = "app";
          program = "${deployContainer}/bin/deployContainer";
        };
      });
}
