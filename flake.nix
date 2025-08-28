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
            mopify.enabled = true;
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
              browse_root = "Podcasts.opml";
            };
          });

      in {
        packages = with pkgs.lib; rec {
          default = mopidyContainer;
          mopidyContainer = let
            etcLayer = pkgs.runCommand "etc-mopidy" { } ''
              mkdir -p $out/etc/mopidy
              cp ${defaultConfig} $out/etc/mopidy/mopidy.conf.tmpl
            '';
            entrypoint = pkgs.writeShellScriptBin "start-mopidy" ''
              set -euo pipefail
              ${pkgs.gettext}/bin/envsubst < /etc/mopidy/mopidy.conf.tmpl > /etc/mopidy/mopidy.conf
              mopidy --config /etc/mopidy/mopidy.conf
            '';
          in pkgs.dockerTools.buildLayeredImage {
            name = "registry.kube.sea.fudo.link/mopidy-server";
            tag = "0.0.1";
            contents = with pkgs; [
              etcLayer
              entrypoint

              coreutils
              bashInteractive

              mopidy
              mopidy-mpd
              mopidy-spotify
              mopidy-iris
              mopidy-somafm
              mopidy-podcast
              mopidy-ytmusic
              mopidy-muse
              mopidy-mopify

              gst_all_1.gstreamer
              gst_all_1.gst-plugins-base
              gst_all_1.gst-plugins-good
              gst_all_1.gst-plugins-bad
              gst_all_1.gst-plugins-ugly
              gst_all_1.gst-libav
            ];

            enableFakechroot = true;
            fakeRootCommands = ''
              ${pkgs.dockerTools.shadowSetup}
              groupadd -g 1000 mopidy
              useradd -u 1000 -g mopidy -d /var/lib/mopidy -M -r mopidy
              mkdir -p /var/lib/mopidy/.cache /var/lib/mopidy/.config /var/lib/mopidy/.local/share
              chown -R mopidy:mopidy /var/lib/mopidy
              mkdir -p /etc/mopidy
              chown mopidy:mopidy /etc/mopidy
            '';

            config = {
              User = "mopidy";
              WorkingDir = "/var/lib/mopidy";
              ExposedPorts = {
                "6680/tcp" = { };
                "6600/tcp" = { };
              };
              Env = [
                "XDG_CACHE_HOME=/var/lib/mopidy/.cache"
                "XDG_CONFIG_HOME=/var/lib/mopidy/.config"
                "XDG_DATA_HOME=/var/lib/mopidy/.local/share"
                "PYTHONUNBUFFERED=1"
                "SPOTIFY_CLIENT_ID="
                "SPOTIFY_CLIENT_SECRET="
                "PODCASTS_ENABLED=false"
                "YOUTUBE_MUSIC_ENABLED=false"
                "SPOTIFY_ENABLED=false"
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
