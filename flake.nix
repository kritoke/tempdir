{
  description = "Tempdir Spoke - crystal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    openspec.url = "github:Fission-AI/OpenSpec";
  };

  outputs = { self, nixpkgs, openspec }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Try to import a local crystal module if present; if not, fall back to
      # the system-provided Crystal from nixpkgs. Nix flakes require files that
      # are referenced by path to be tracked by Git, so the fallback prevents
      # evaluation errors when the local module is not present in the repo.
      crystal_1_18_2_mod =
        if builtins.pathExists ./nix/modules/crystal-1-18-2.nix then
          import ./nix/modules/crystal-1-18-2.nix { inherit pkgs; }
        else
          { crystal_1_18_2 = pkgs.crystal; };
      # Local package aliases (none by default)

      # Read a local flake.private.nix if present. We wrap it in a guard so
      # Nix evaluation doesn't error when the file is missing. This is evaluated
      # in the outer let so it's visible when constructing the devShell below.
      private_hook = builtins.tryEval (if builtins.pathExists ./flake.private.nix then builtins.readFile ./flake.private.nix else "");

    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [ ] ++ [ crystal_1_18_2_mod.crystal_1_18_2 ] ++ pwLibs;

        # Use a local, untracked `flake.private.nix` to inject any personal shellHook
        # or environment glue. This keeps personal workspace-specific logic out of
        # the repository. If `flake.private.nix` exists it should export a shell
        # snippet; otherwise a minimal shellHook runs.
        shellHook = ''${if private_hook.success then private_hook.value else ""}
          echo "tempdir DevShell Active"
        '';
      };
    };
}
