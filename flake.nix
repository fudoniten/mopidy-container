{
  description =
    "Build Ubuntu-based Mopidy image with latest plugins via nix run (buildah)";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Build context directory with the three files above
        dockerContext = pkgs.runCommand "mopidy-docker-context" { } ''
          mkdir -p $out
          cp ${./Dockerfile} $out/Dockerfile
          cp ${./docker-endpoint.sh} $out/docker-entrypoint.sh
          cp ${./mopidy.conf.tmpl} $out/mopidy.conf.tmpl
        '';

        # Image coordinates to build/push
        imageName = "registry.kube.sea.fudo.link/mopidy-server";
        imageTag = "latest";

        policyJson = pkgs.writeText "containers-policy.json" (builtins.toJSON {
          default = [{ type = "reject"; }];
          transports = {
            "docker" = { "" = [{ type = "insecureAcceptAnything"; }]; };
            "containers-storage" = {
              "" = [{ type = "insecureAcceptAnything"; }];
            };
          };
        });

        # Script to build with buildah (rootless-friendly) from our context
        buildScript = pkgs.writeShellApplication {
          name = "build-mopidy-image";
          runtimeInputs = with pkgs; [ buildah coreutils ];
          text = ''
            set -euo pipefail
            ctx="${dockerContext}"
            img="${imageName}:${imageTag}"
            echo "Building ${imageName}:${imageTag} from $ctx ..."
            buildah bud --pull --tag "$img" "$ctx"
            echo "Built $img"
          '';
        };

        # Script to push using buildah (or skopeo if you prefer)
        pushScript = pkgs.writeShellApplication {
          name = "push-mopidy-image";
          runtimeInputs = with pkgs; [ buildah coreutils ];
          text = ''
            set -euo pipefail
            img="${imageName}:${imageTag}"
            echo "Pushing $img ..."
            # If using an insecure registry, you may need: --tls-verify=false
            buildah push --policy ${policyJson} "$img" "docker://${imageName}:${imageTag}"
            echo "Pushed $img"
          '';
        };

        # Convenience: build and push in one go
        buildAndPush = pkgs.writeShellApplication {
          name = "build-and-push-mopidy";
          runtimeInputs = with pkgs; [ buildah coreutils ];
          text = ''
            set -euo pipefail
            "${buildScript}/bin/build-mopidy-image"
            "${pushScript}/bin/push-mopidy-image"
          '';
        };
      in {
        packages.dockerContext = dockerContext;

        apps.build = {
          type = "app";
          program = "${buildScript}/bin/build-mopidy-image";
        };
        apps.push = {
          type = "app";
          program = "${pushScript}/bin/push-mopidy-image";
        };
        apps.default = {
          type = "app";
          program = "${buildAndPush}/bin/build-and-push-mopidy";
        };
      });
}
