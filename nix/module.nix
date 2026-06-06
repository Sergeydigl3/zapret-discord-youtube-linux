{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.zapret-discord-youtube;
in {
  options.services.zapret-discord-youtube = {
    enable = mkEnableOption "zapret-discord-youtube DPI bypass";

    directory = mkOption {
      type = types.path;
      description = "Path to the zapret-discord-youtube-linux checkout";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.bash;
      description = "Package providing bash (for ExecStart)";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.zapret_discord_youtube = {
      description = "zapret-discord-youtube DPI bypass service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        WorkingDirectory = cfg.directory;
        User = "root";
        ExecStart = "${cfg.package}/bin/bash ${cfg.directory}/service.sh daemon";
        ExecStop = "${cfg.package}/bin/bash ${cfg.directory}/service.sh kill";
        ExecStopPost = "${cfg.package}/bin/bash -c 'echo Сервис завершён'";
        PIDFile = "/run/zapret_discord_youtube.pid";
        Restart = "on-failure";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
