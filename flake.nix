# MuseScore flake - currently macOS only
#
# Development shell: `nix develop`
# Build production app: `nix build .#production`
# Build dev app: `nix build`
# To run a debug build with symbols under lldb, run eg: `lldb -- result/mscore.app/Contents/MacOS/.mscore-wrapped --debug`
{
  description = "MuseScore macOS flake";

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
            {
              buildMode,
              cmakeBuildType,
              debugSymbols ? false,
            }:
            pkgs.stdenv.mkDerivation {
              pname = "musescore";
              version = "unstable";
              src = self;

              nativeBuildInputs =
                (with pkgs; [
                  cmake
                  ninja
                  pkg-config
                  python311
                  qt6.wrapQtAppsHook
                ])
                ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.cctools ];

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
                "-DCMAKE_BUILD_TYPE=${cmakeBuildType}"
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

              dontStrip = debugSymbols;
              separateDebugInfo = debugSymbols;

              NIX_CFLAGS_COMPILE = pkgs.lib.optionalString debugSymbols "-g -O0";
              NIX_CXXFLAGS_COMPILE = pkgs.lib.optionalString debugSymbols "-g -O0";

              postFixup =
                pkgs.lib.optionalString debugSymbols ''
                  appPath="$out/mscore.app/Contents/MacOS"
                  bin="$appPath/.mscore-wrapped"
                  if [ ! -e "$bin" ]; then
                    bin="$appPath/mscore"
                  fi
                  rm -rf "$appPath/mscore.dSYM" "$bin.dSYM"
                  dsymutil "$bin" -o "$bin.dSYM"
                  # Provide the traditional name alongside the wrapped binary.
                  ln -snf "$(basename "$bin").dSYM" "$appPath/mscore.dSYM"
                '';

              enableParallelBuilding = true;
            };
        in {
          default = mkPackage {
            buildMode = "dev";
            cmakeBuildType = "Debug";
            debugSymbols = true;
          };
          production = mkPackage {
            buildMode = "release";
            cmakeBuildType = "Release";
          };
        }
      );
    };
}
