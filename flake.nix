{
  description = "MuseScore macOS development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkContext =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          deploymentTarget =
            if system == "aarch64-darwin"
            then "11.0"
            else "10.15";
          qtPackages =
            with pkgs.qt6; [
              qtbase
              qtdeclarative
              qttools
              qtsvg
              qtnetworkauth
              qtshadertools
              qt5compat
              qtscxml
            ];
          qtPluginPath = pkgs.lib.makeSearchPath "lib/qt6/plugins" qtPackages;
          qtQmlPath = pkgs.lib.makeSearchPath "lib/qt6/qml" [
            pkgs.qt6.qtdeclarative
          ];
        in
        {
          inherit pkgs system deploymentTarget qtPackages qtPluginPath qtQmlPath;
        };
    in {
      devShells = forAllSystems (
        system:
        let
          ctx = mkContext system;
          inherit (ctx) pkgs deploymentTarget qtPackages qtPluginPath qtQmlPath;
        in {
          default = pkgs.mkShell {
            packages =
              (with pkgs; [
                cmake
                ninja
                git
                pkg-config
                python311
                ccache
                nasm
              ])
              ++ qtPackages;

            shellHook = ''
              export MACOSX_DEPLOYMENT_TARGET=${deploymentTarget}
              export CMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET

              if command -v xcrun >/dev/null 2>&1; then
                export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
              fi

              export PATH=${pkgs.qt6.qtbase}/bin:$PATH

              export QT_PLUGIN_PATH=${qtPluginPath}''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}
              export QML2_IMPORT_PATH=${qtQmlPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}
            '';
          };
        }
      );

      packages = forAllSystems (
        system:
        let
          ctx = mkContext system;
          inherit (ctx) pkgs deploymentTarget qtPackages;
          arch =
            if system == "aarch64-darwin"
            then "arm64"
            else "x86_64";
          mkPackage =
            buildMode:
            pkgs.stdenv.mkDerivation {
              pname = "musescore";
              version = "unstable";
              src = self;

              nativeBuildInputs =
                with pkgs; [
                  cmake
                  ninja
                  pkg-config
                  python311
                  qt6.wrapQtAppsHook
                ];

              buildInputs =
                qtPackages
                ++ (with pkgs; [
                  ffmpeg
                  flac
                  freetype
                  harfbuzz
                  libogg
                  libopusenc
                  libsndfile
                  libvorbis
                  libopus
                  zlib
                ]);

              MACOSX_DEPLOYMENT_TARGET = deploymentTarget;
              CMAKE_OSX_DEPLOYMENT_TARGET = deploymentTarget;

              cmakeFlags = [
                "-GNinja"
                "-DCMAKE_BUILD_TYPE=Release"
                "-DCMAKE_OSX_ARCHITECTURES=${arch}"
                "-DMUE_DOWNLOAD_SOUNDFONT=OFF"
                "-DMUE_INSTALL_SOUNDFONT=OFF"
                "-DMUSE_COMPILE_USE_COMPILER_CACHE=OFF"
                "-DMUE_COMPILE_USE_SYSTEM_FLAC=ON"
                "-DMUE_COMPILE_USE_SYSTEM_FREETYPE=ON"
                "-DMUE_COMPILE_USE_SYSTEM_HARFBUZZ=ON"
                "-DMUE_COMPILE_USE_SYSTEM_OPUS=ON"
                "-DMUE_COMPILE_USE_SYSTEM_OPUSENC=ON"
                "-DMUSE_APP_BUILD_MODE=${buildMode}"
              ];

              enableParallelBuilding = true;
            };
        in {
          default = mkPackage "dev";
          production = mkPackage "release";
        }
      );
    };
}
