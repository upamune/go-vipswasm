{
  description = "CGO-free Go bindings for a libvips WebAssembly core";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/68a8af93ff4297686cb68880845e61e5e2e41d92";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f:
        builtins.listToAttrs (map (system: {
          name = system;
          value = f system;
        }) systems);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.go_1_25
              pkgs.buf
              pkgs.protobuf
              pkgs.pkg-config
              pkgs.binaryen
              pkgs.cmake
              pkgs.meson
              pkgs.ninja
              pkgs.glib
              pkgs.gettext
              pkgs.git
            ];

            shellHook = ''
              export PATH="$HOME/go/bin:$PATH"
              export WASMIFY_NON_INTERACTIVE=1
            '';
          };
        });
    };
}
