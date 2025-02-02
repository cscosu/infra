{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    utils,
    ...
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "terraform"
            ];
        };
      in rec {
        devShells.default = pkgs.mkShell {
          name = "infra-devshell";
          packages = with pkgs; [
            awscli
            terraform
            terraform-ls
            go-task
            infracost
          ];
        };
      }
    );
}
