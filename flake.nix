{
  description = "Python devShell. Requires dirEnv.
  To activate run `direnv allow`";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # Hooks input
    git-hooks.url = "github:cachix/git-hooks.nix";
  };

  outputs =
    inputs@{ flake-parts, git-hooks, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      # Import the module
      imports = [ inputs.git-hooks.flakeModule ];

      perSystem =
        { pkgs, config, ... }:
        let
          pythonVersion = pkgs.python311;
          linter = pkgs.ruff;
          pkgManager = pkgs.uv;
          typeChecker = pkgs.basedpyright;
        in
        {
          formatter = pkgs.nixfmt-rfc-style; # Nix formatter

          # Hooks
          pre-commit.settings.hooks = {
            # Python checks
            ruff.enable = true; # Linting
            ruff-format.enable = true; # Formatting

            # Nix checks
            nixfmt-rfc-style.enable = true;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              pythonVersion
              pkgManager
              linter
              typeChecker # LSP
            ];

            env = {
              PYTHONDONTWRITEBYTECODE = "1";
              # LD_LIBRARY_PATH is primarily for Linux. This allows pip-installed wheels to find C libraries (like zlib or standard C++)
              LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
                pkgs.stdenv.cc.cc.lib # Standard C++ library
                pkgs.zlib # Compression library (common dependency)
                # pkgs.glib           # Sometimes needed for graphical libs
              ];
            };

            # 2. IMPORTANT: Install the hooks into .git/hooks automatically
            shellHook = ''
              ${config.pre-commit.installationScript}

              # 1. Create .venv if missing
              if [ ! -d ".venv" ]; then
                ${pkgs.uv}/bin/uv venv .venv
              fi
              source .venv/bin/activate

              # 2. Lockfile Management
              if [ -f requirements.txt ]; then
                 # Check if lockfile is missing OR if requirements.txt is newer
                 if [ ! -f requirements.lock ] || [ "requirements.txt" -nt "requirements.lock" ]; then
                    echo "🔒 Lockfile missing or outdated. Compiling now..."
                    # --refresh to prevent caching bug
                    ${pkgs.uv}/bin/uv pip compile requirements.txt -o requirements.lock --refresh
                 fi
              fi

              # 3. Sync
              if [ -f requirements.lock ]; then
                 echo "📦 Syncing dependencies..."
                 ${pkgs.uv}/bin/uv pip sync requirements.lock
              fi
            '';
          };
        };
    };
}
