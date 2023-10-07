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
                 "role": "Viewer",})
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

      newGrafanaSA = json.loads(
                   client.succeed(
                      f"curl -X POST -H Content-Type:application/json -d '{createReadSA}' -u admin:admin http://newGrafana:3000/api/serviceaccounts"))
      oldGrafanaSA =  json.loads(client.succeed(
                      f"curl -X POST -H Content-Type:application/json -d '{createReadWriteSA}' -u admin:admin http://oldGrafana:3500/api/serviceaccounts"))

      newGrafanaAuthHeader = shlex.quote(f"Authorization: Bearer {newGrafanaSA}")
      newFolder = json.dumps({
                 "uid": "nErXDvCkzz",
                 "title": "Department ABC"})


      oldGrafanaNewFolder =  json.loads(client.succeed(
                      f"curl -X POST -H Content-Type:application/json -d '{newFolder}' -u admin:admin http://oldGrafana:3500/api/folders"))
      assert oldGrafanaNewFolder.get("uid") == "nErXDvCkzz"
    '';

  };
}
