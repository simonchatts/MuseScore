# MuseScore flake - currently macOS only
#
# Development shell: `nix develop`
# Build production app: `nix build .#production`
# Build dev app: `nix build`
# Build with unit tests: `nix build .#tests`
# To run a debug build with symbols under lldb, run eg: `lldb -- result/mscore.app/Contents/MacOS/.mscore-wrapped --debug`
# To run unit tests after building: `result/bin/run-tests` or `result/bin/muse_ui_tests`
{
  description = "MuseScore macOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/d7f52a7a640bc54c7bb414cca603835bf8dd4b10";
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
              enableSoundfont ? false,
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
                "-DMUSE_COMPILE_USE_COMPILER_CACHE=OFF"
                "-DMUE_COMPILE_USE_SYSTEM_FLAC=ON"
                "-DMUE_COMPILE_USE_SYSTEM_FREETYPE=ON"
                "-DMUE_COMPILE_USE_SYSTEM_HARFBUZZ=ON"
                "-DMUE_COMPILE_USE_SYSTEM_OPUS=ON"
                "-DMUE_COMPILE_USE_SYSTEM_OPUSENC=ON"
                "-DMUSE_APP_BUILD_MODE=${buildMode}"
              ]
              ++ pkgs.lib.optionals (!enableSoundfont) [
                "-DMUE_DOWNLOAD_SOUNDFONT=OFF"
                "-DMUE_INSTALL_SOUNDFONT=OFF"
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
            enableSoundfont = true;
          };
          tests = pkgs.stdenv.mkDerivation {
            pname = "musescore-tests";
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
              "-DCMAKE_BUILD_TYPE=Debug"
              "-DCMAKE_OSX_ARCHITECTURES=${arch}"
              "-DMUE_DOWNLOAD_SOUNDFONT=OFF"
              "-DMUE_INSTALL_SOUNDFONT=OFF"
              "-DMUSE_COMPILE_USE_COMPILER_CACHE=OFF"
              "-DMUE_COMPILE_USE_SYSTEM_FLAC=ON"
              "-DMUE_COMPILE_USE_SYSTEM_FREETYPE=ON"
              "-DMUE_COMPILE_USE_SYSTEM_HARFBUZZ=ON"
              "-DMUE_COMPILE_USE_SYSTEM_OPUS=ON"
              "-DMUE_COMPILE_USE_SYSTEM_OPUSENC=ON"
              "-DMUSE_APP_BUILD_MODE=dev"
              "-DMUSE_ENABLE_UNIT_TESTS=ON"
              "-DMUSESCORE_BUILD_CONFIGURATION=utest"
            ];

            dontStrip = true;
            separateDebugInfo = true;

            NIX_CFLAGS_COMPILE = "-g -O0";
            NIX_CXXFLAGS_COMPILE = "-g -O0";

            # Don't run tests during build, user will run them manually
            doCheck = false;

            # Install the test binaries and CTestTestfile.cmake
            installPhase = ''
              runHook preInstall

              mkdir -p $out/bin
              mkdir -p $out/lib

              # Copy all test executables
              find . -name '*_tests' -type f -executable | while read test; do
                cp "$test" $out/bin/
              done

              # Copy CTestTestfile.cmake and other ctest files for running tests
              cp -r . $out/lib/build

              # Create a helper script to run tests
              cat > $out/bin/run-tests <<EOF
              #!/bin/sh
              cd $out/lib/build
              export QT_QPA_PLATFORM=minimal:enable_fonts
              export ASAN_OPTIONS=detect_leaks=0:new_delete_type_mismatch=0
              ctest -V "\$@"
              EOF
              chmod +x $out/bin/run-tests

              runHook postInstall
            '';

            enableParallelBuilding = true;
          };
        }
      );
    };
}
