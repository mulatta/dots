{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  ipv4 = config.networking.cask.ipv4.address;
  ipv6 = config.networking.cask.ipv6.address;
  # The acme records mirror terraform/cloudflare/dns.tf until mulatta.io moves here.
  publicZone = pkgs.writeText "mulatta.io.zone" ''
    ${builtins.replaceStrings [ "@SERVICE_IPV4@" "@SERVICE_IPV6@" ] [ ipv4 ipv6 ] (
      builtins.readFile ./mulatta.io.zone
    )}
    acme IN NS ns1.mulatta.io.
    ${lib.concatMapStrings (
      host:
      lib.concatMapStrings (name: ''
        _acme-challenge.${name}.ts IN CNAME ${acmeKey host}.
      '') ([ host ] ++ self.nixosConfigurations.${host}.config.mulatta.tailnetNames)
    ) acmeHosts}
  '';
  # Hosts importing nixosModules/acme-knot, each with its own TSIG key.
  # cask itself is skipped: its generators depend on this list.
  acmeHosts = lib.attrNames (
    lib.filterAttrs (name: machine: machine.config.clan.core.vars.generators ? "acme-tsig-${name}") (
      removeAttrs self.nixosConfigurations [ config.networking.hostName ]
    )
  );
  acmeKey = host: "${host}.acme.mulatta.io";
  acmeZone = pkgs.writeText "acme.mulatta.io.zone" ''
    $ORIGIN acme.mulatta.io.
    $TTL 60
    @ IN SOA ns1.mulatta.io. hostmaster.mulatta.io. 1 3600 600 604800 60
    @ IN NS ns1.mulatta.io.
  '';
in
{
  clan.core.vars.generators = lib.genAttrs' acmeHosts (
    host:
    lib.nameValuePair "acme-tsig-${host}" (
      lib.mkMerge [
        (import ../../../../nixosModules/acme-knot/tsig.nix { inherit pkgs host; })
        { files."knot-key.conf".owner = "knot"; }
      ]
    )
  );

  sops.secrets."knot-keys.conf" = {
    owner = "knot";
    restartUnits = [ "knot.service" ];
  };

  services.knot = {
    enable = true;
    keyFiles = [
      config.sops.secrets."knot-keys.conf".path
    ]
    ++ map (
      host: config.clan.core.vars.generators."acme-tsig-${host}".files."knot-key.conf".path
    ) acmeHosts;
    settings = {
      server.listen = [
        "${ipv4}@53"
        "${ipv6}@53"
      ];

      remote = [
        {
          id = "he_ip4";
          address = "216.218.130.2";
        }
      ];

      acl = [
        {
          id = "he_acl";
          key = "52cc052c-fb0c-444c-9056-17c32c18d9bb.uniq.mulatta.io";
          action = "transfer";
        }
      ]
      # An ACL with no key would accept unsigned updates.
      ++ lib.optional (acmeHosts != [ ]) {
        # Each host's key, named after its record, may only replace that TXT record.
        id = "acme_update";
        key = map acmeKey acmeHosts;
        action = "update";
        update-owner = "key";
        update-owner-match = "equal";
        update-type = [ "TXT" ];
      };

      template = [
        {
          id = "default";
          semantic-checks = "on";
        }
        {
          id = "master";
          semantic-checks = "on";
          notify = [ "he_ip4" ];
          acl = [ "he_acl" ];
          zonefile-sync = "-1";
          zonefile-load = "difference-no-serial";
          serial-policy = "dateserial";
          journal-content = "all";
        }
      ];

      # Shadow answers establish cask before delegation or resolver changes
      # make these zones part of production resolution.
      zone = [
        {
          domain = "n";
          file = "${self.inputs.dure.packages.${pkgs.stdenv.hostPlatform.system}.n-zone}";
        }
        {
          domain = "i";
          file = "${self.inputs.dure.packages.${pkgs.stdenv.hostPlatform.system}.i-zone}";
        }
        {
          domain = "mulatta.io";
          file = "${publicZone}";
          template = "master";
        }
        {
          # Hosts point _acme-challenge here, so DNS-01 never needs a Cloudflare token.
          domain = "acme.mulatta.io";
          file = "${acmeZone}";
          acl = lib.optional (acmeHosts != [ ]) "acme_update";
          zonefile-sync = "-1";
          zonefile-load = "difference-no-serial";
          journal-content = "all";
        }
      ];
    };
  };
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
