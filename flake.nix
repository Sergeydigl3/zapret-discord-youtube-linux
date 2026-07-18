{
  description = "zapret-discord-youtube-linux — DPI bypass for Discord/YouTube";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    nixosModules.default = import ./nix/module.nix;
  };
}
