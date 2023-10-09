{ flake ? builtins.getFlake (toString ./.)
, pkgs ? flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}
, makeTest ?
  pkgs.callPackage (flake.inputs.nixpkgs + "/nixos/tests/make-test-python.nix")
, myHello }:

let
  makeTest' = test:
    makeTest test {
      inherit pkgs;
      inherit (pkgs) system;
    };
in {
  test = makeTest' {
    name = "it runs";
    nodes.oldGrafana = { config, ... }: {
      networking.firewall.allowedTCPPorts = [ 3500 ];
      systemd.services.grafana = {
        after = [ "network-interfaces.target" ];
        wants = [ "network-interfaces.target" ];
      };
      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_port = 3500;
            http_addr = "";
            protocol = "http";
          };
        };
      };
    };
    nodes.newGrafana = { config, ... }: {
      networking.firewall.allowedTCPPorts = [ 3000 ];
      systemd.services.grafana = {
        after = [ "network-interfaces.target" ];
        wants = [ "network-interfaces.target" ];
      };
      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_port = 3000;
            http_addr = "";
            protocol = "http";
          };
        };
      };
    };

    nodes.client = { ... }: {
      imports = [ ];
      environment.systemPackages = with pkgs; [ curl jq inetutils myHello ];
    };

    testScript = ''
      import json
      import shlex
      createReadSA = json.dumps({
                 "name": "newGrafanaSA",
                 "role": "Editor",})
      createReadWriteSA = json.dumps({
                 "name": "newGrafanaSA",
                 "role": "Editor",})

      start_all()

      oldGrafana.wait_for_open_port(3500)
      newGrafana.wait_for_open_port(3000)
      newGrafana.wait_for_unit("grafana.service")
      oldGrafana.wait_for_unit("grafana.service")
      client.succeed("ping -c 2 newGrafana")
      client.succeed("ping -c 2 oldGrafana")

      client.succeed("curl -v http://newGrafana:3000/api/health")
      client.succeed("curl -v http://oldGrafana:3500/api/health")

      newGrafanaSA = client.succeed(
                      f"curl --fail  -X POST -H Content-Type:application/json -d '{createReadSA}' -u admin:admin http://newGrafana:3000/api/auth/keys | jq -r .key ")
      oldGrafanaSA = client.succeed(
                      f"curl --fail -X POST -H Content-Type:application/json -d '{createReadWriteSA}' -u admin:admin http://oldGrafana:3500/api/auth/keys | jq -r .key")

      newGrafanaAuthHeader = shlex.quote(f"Authorization: Bearer {newGrafanaSA}")
      oldGrafanaAuthHeader = shlex.quote(f"Authorization: Bearer {oldGrafanaSA}")

      newFolder = json.dumps({
                 "title": "Department ABC"})

      SA = client.succeed(f"curl --fail -X POST -H Content-Type:application/json -d '{createReadWriteSA}' http://admin:admin@oldGrafana:3500/api/serviceaccounts | jq -r .id")
      SATREQ = json.dumps({"name": "my-secret"})
      SAT = client.succeed(f"curl --fail -X POST -H Content-Type:application/json -d '{SATREQ}' http://admin:admin@oldGrafana:3500/api/serviceaccounts/2/tokens | jq -r .key")
      SATHeader = shlex.quote(f"Authorization: Bearer {SAT}")


      client.succeed(f"curl -vv --fail -X POST  -H Content-Type:application/json -H Accept:application/json -d '{newFolder}' --url http://oldGrafana:3500/api/folders -H {SATHeader}")
    '';

  };
}
