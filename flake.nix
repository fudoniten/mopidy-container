{
  description = "Mopidy music server running in a container.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";

        defaultConfig = pkgs.writeText "mopidy.conf.tpml"
          (pkgs.lib.generators.toINI { } {
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
            audio.output = pkgs.lib.concatStringsSep " " [
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

      in {
        packages = with pkgs.lib; rec {
          default = mopidyContainer;
          mopidyContainer = let
            etcLayer = pkgs.runCommand "etc-mopidy" { } ''
              mkdir -p $out/etc/mopidy
              cp ${defaultConfig} $out/etc/mopidy/mopidy.conf.tmpl
            '';
            pyPkgs = with pkgs.python3Packages; [
              cachetools
              configobj
              pygobject3
              pycairo
              pytube
              ytmusicapi
              uritools
            ];
            pyRoots = with pkgs;
              [
                mopidy
                mopidy-mpd
                mopidy-spotify
                mopidy-iris
                mopidy-moped
                mopidy-musicbox-webclient
                mopidy-somafm
                mopidy-podcast
                mopidy-ytmusic
                mopidy-muse
              ] ++ pyPkgs;
            pyPath = makeSearchPathOutput "site-packages"
              "lib/${pkgs.python3.libPrefix}/site-packages" pyRoots;
            gstPlugins = with pkgs.gst_all_1; [
              gst-plugins-base
              gst-plugins-good
              gst-plugins-bad
              gst-plugins-ugly
              gst-libav
            ];
            giPath = pkgs.lib.makeSearchPath "lib/gstreamer-1.0" [
              pkgs.glib
              pkgs.gst_all_1.gstreamer
            ] ++ gstPlugins;

            gstPluginPath = concatStringsSep ":"
              (map (plugin: "${plugin}/lib/gstreamer-1.0") gstPlugins);
            entrypoint = let
              entrypointEnvVars = rec {
                GST_PLUGIN_SYSTEM_PATH_1_0 = gstPluginPath;
                GST_PLUGIN_SCANNER_1_0 =
                  "${pkgs.gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner";
                GST_PLUGIN_SCANNER = GST_PLUGIN_SCANNER_1_0;
                GST_PLUGIN_SYSTEM_PATH = GST_PLUGIN_SYSTEM_PATH_1_0;
                GIO_EXTRA_MODULES = "${pkgs.glib-networking}/lib/gio/modules";
                XDG_CACHE_HOME = "/var/lib/mopidy/.cache";
                XDG_CONFIG_HOME = "/var/lib/mopidy/.config";
                XDG_DATA_HOME = "/var/lib/mopidy/.local/share";
                GI_TYPELIB_PATH = giPath;
                SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
              };
              setEnvVars = concatStringsSep "\n"
                (mapAttrsToList (var: val: "export ${var}=${val}")
                  entrypointEnvVars);
            in pkgs.writeShellScriptBin "start-mopidy" ''
              set -euo pipefail
              ${setEnvVars}
              ${pkgs.gettext}/bin/envsubst < /etc/mopidy/mopidy.conf.tmpl > /etc/mopidy/mopidy.conf
              mopidy --config /etc/mopidy/mopidy.conf
            '';
          in pkgs.dockerTools.buildLayeredImage {
            name = "registry.kube.sea.fudo.link/mopidy-server";
            tag = "0.0.1";
            contents = with pkgs;
              [
                etcLayer
                entrypoint

                coreutils
                bashInteractive
                ca-certificates

                mopidy
                mopidy-mpd
                mopidy-spotify
                mopidy-iris
                mopidy-moped
                mopidy-musicbox-webclient
                mopidy-somafm
                mopidy-podcast
                mopidy-ytmusic
                mopidy-muse

                gst_all_1.gstreamer

                fontconfig
                dejavu_fonts

                glib
                gobject-introspection
                glib-networking

                python3Packages.pygobject3
              ] ++ pyPkgs ++ gstPlugins;

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
              ExposedPorts = {
                "6680/tcp" = { };
                "6600/tcp" = { };
              };
              Env = [
                "PYTHONPATH=${pyPath}"
                "PYTHONUNBUFFERED=1"
                "SPOTIFY_CLIENT_ID="
                "SPOTIFY_CLIENT_SECRET="
                "ICECAST_PASSWD="
                "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "GIO_EXTRA_MODULES=${pkgs.glib-networking}/lib/gio/modules"
                "GST_PLUGIN_SYSTEM_PATH_1_0=${gstPluginPath}"
                "GI_TYPELIB_PATH=${giPath}"
              ];
              Volumes = {
                "/var/lib/mopidy" = { };
                "/var/lib/ytmusic" = { };
              };
              Entrypoint = [ "/bin/start-mopidy" ];
            };
          };

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
            runtimeInputs = with pkgs; [ skopeo coreutils git jq ];
            text = ''
              set -euo pipefail
              TAR=${self.packages."${system}".mopidyContainer}
              DEST="docker://registry.kube.sea.fudo.link/mopidy-server"
              LATEST="docker://registry.kube.sea.fudo.link/mopidy-server:latest"
              echo "pushing $TAR -> $DEST ..."
              skopeo copy --policy ${policyJson} --all docker-archive:"$TAR" "$DEST"
              skopeo copy --policy ${policyJson} --all docker-archive:"$TAR" "$LATEST"
              echo "done."
            '';
          };
        };

        apps = rec {
          default = deployContainer;

          deployContainer = {
            type = "app";
            program = "${
                self.packages."${system}".deployContainer
              }/bin/deployContainer";
          };
        };
      });
}
