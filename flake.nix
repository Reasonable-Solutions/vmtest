{
  description = "A very basic flake";
  inputs = { nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; };
  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;
    packages.x86_64-linux.default = self.packages.x86_64-linux.hello;

    checks.x86_64-linux = let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      inherit (import ./vm-test.nix {
        makeTest = import (nixpkgs + "/nixos/tests/make-test-python.nix");
        inherit pkgs;
        myHello = pkgs.hello;
      })
        test;
    };
  };
}
