{
  description = "Taiga Backend – Nix packaging and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    devshell.url = "github:numtide/devshell";
    taiga-back = {
      url = "github:taigaio/taiga-back/6.10.0";
      flake = false;
    };
    flake-taiga-front = {
      url = "path:/home/pion/work/dev/flake-taiga-front";
    };
  };

  outputs = { self, nixpkgs, flake-utils, devshell, taiga-back, flake-taiga-front }:
    let
      nixosModule = { config, lib, pkgs, ... }@moduleArgs:
        let
          pkg = self.packages.${pkgs.system}.default;
        in
        {
          imports = [ (import ./nixos-module.nix moduleArgs) ];
          services.taiga.package = lib.mkDefault pkg;
        };

    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        devshellLib = import devshell { nixpkgs = pkgs; };

        inherit (import ./python-packages.nix { inherit pkgs; }) python pythonEnv;

        src = builtins.path {
          path = "${taiga-back}";
          name = "taiga-back-src";
          filter = path: type:
            let
              base = baseNameOf path;
            in
              !(
                (type == "directory" && base == ".git") ||
                base == "__pycache__" ||
                base == "result" || base == "result-"
              );
        };

        taigaBack = import ./package.nix {
          inherit pkgs pythonEnv python src;
        };

      in
      {
        packages = {
          default = taigaBack;
          taiga-back = taigaBack;
        };

        apps = {
          default = {
            type = "app";
            program = "${taigaBack}/bin/gunicorn";
          };
        };

        devShells.default = import ./devshell.nix {
          inherit pkgs devshell devshellLib python pythonEnv taigaBack;
          projectRoot = "${taiga-back}";
          devConfig = ./dev-config.py;
          taigaFront = flake-taiga-front.packages.${system}.default;
        };
      }
    ) // {
      nixosModules.default = nixosModule;
      nixosModule = nixosModule;
    };
}
