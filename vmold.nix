let

  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-22.11";

  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };

in pkgs.nixosTest {
  name = "it runs";
  nodes.oldGrafana = { config, pkgs, ... }: {
    networking.firewall.allowedTCPPorts = [ 3500 ];
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = 3500;
          domain = "your.domain";
          root_url = "https://your.domain/grafana/";
        };
      };
    };
    services.nginx.virtualHosts."your.domain" = {
      locations."/grafana/" = {
        proxyPass = "http://${
            toString config.services.grafana.settings.server.http_addr
          }:${toString config.services.grafana.settings.server.http_port}/";
        proxyWebsockets = true;
      };
    };
  };

  nodes.newGrafana = { config, pkgs, ... }: {
    networking.firewall.allowedTCPPorts = [ 3000 ];

    services.grafana = {
      enable = true;
      settings = { server = { http_port = 3000; }; };
    };
    services.nginx.virtualHosts."your.domain" = {
      locations."/grafana/" = {
        proxyPass = "http://${
            toString config.services.grafana.settings.server.http_addr
          }:${toString config.services.grafana.settings.server.http_port}/";
        proxyWebsockets = true;
      };
    };
  };

  nodes.client = { config, pkgs, ... }: {
    imports = [ ];
    environment.systemPackages = with pkgs; [ curl jq ];
  };

  testScript = ''
    start_all()
    oldGrafana.wait_for_open_port(3500)
    newGrafana.wait_for_open_port(3000)
    newGrafana.wait_for_unit("grafana.service")
    oldGrafana.wait_for_unit("grafana.service")
    oldGrafana.sleep(3)
    newGrafana.sleep(3)

    client.succeed("curl http://newGrafana:3000")
    client.succeed("curl http://oldGrafana:3500")
  '';
}
