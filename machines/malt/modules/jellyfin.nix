{
  self,
  lib,
  config,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";
  wgTrustedCidr = "${wgPrefix}::/64";

  port = 8096;
  ssoPlugin = pkgs.jellyfin-plugin-sso-auth;
  ssoVersion = ssoPlugin.version;
  networkConfig = pkgs.writeText "jellyfin-network.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <BaseUrl />
      <EnableHttps>false</EnableHttps>
      <RequireHttps>false</RequireHttps>
      <CertificatePath />
      <CertificatePassword />
      <InternalHttpPort>${toString port}</InternalHttpPort>
      <InternalHttpsPort>8920</InternalHttpsPort>
      <PublicHttpPort>${toString port}</PublicHttpPort>
      <PublicHttpsPort>8920</PublicHttpsPort>
      <AutoDiscovery>false</AutoDiscovery>
      <EnableUPnP>false</EnableUPnP>
      <EnableIPv4>false</EnableIPv4>
      <EnableIPv6>true</EnableIPv6>
      <EnableRemoteAccess>true</EnableRemoteAccess>
      <LocalNetworkSubnets />
      <LocalNetworkAddresses>
        <string>${maltWgIP}</string>
      </LocalNetworkAddresses>
      <KnownProxies>
        <string>${wgTrustedCidr}</string>
      </KnownProxies>
      <IgnoreVirtualInterfaces>true</IgnoreVirtualInterfaces>
      <VirtualInterfaceNames>
        <string>veth</string>
      </VirtualInterfaceNames>
      <EnablePublishedServerUriByRequest>false</EnablePublishedServerUriByRequest>
      <PublishedServerUriBySubnet />
      <RemoteIPFilter />
      <IsRemoteIPFilterBlacklist>false</IsRemoteIPFilterBlacklist>
    </NetworkConfiguration>
  '';
  brandingConfig = pkgs.writeText "jellyfin-branding.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <BrandingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <LoginDisclaimer>&lt;form action="https://video.mulatta.io/sso/OID/start/kanidm"&gt;&lt;button class="raised block emby-button button-submit"&gt;Login with Kanidm&lt;/button&gt;&lt;/form&gt;</LoginDisclaimer>
      <CustomCss>a.raised.emby-button { padding: 0.9em 1em; color: inherit !important; } .disclaimerContainer { display: block; }</CustomCss>
      <SplashscreenEnabled>false</SplashscreenEnabled>
    </BrandingOptions>
  '';
  ssoConfigTemplate = pkgs.writeText "jellyfin-sso-auth.xml.in" ''
    <?xml version="1.0" encoding="utf-8"?>
    <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <SamlConfigs />
      <OidConfigs>
        <item>
          <key>
            <string>kanidm</string>
          </key>
          <value>
            <PluginConfiguration>
              <OidEndpoint>https://idm.mulatta.io/oauth2/openid/jellyfin/</OidEndpoint>
              <OidClientId>jellyfin</OidClientId>
              <OidSecret>@OIDC_SECRET@</OidSecret>
              <Enabled>true</Enabled>
              <EnableAuthorization>true</EnableAuthorization>
              <EnableAllFolders>true</EnableAllFolders>
              <EnabledFolders />
              <AdminRoles>
                <string>admins@idm.mulatta.io</string>
              </AdminRoles>
              <Roles>
                <string>media_users@idm.mulatta.io</string>
                <string>admins@idm.mulatta.io</string>
              </Roles>
              <EnableFolderRoles>false</EnableFolderRoles>
              <EnableLiveTvRoles>false</EnableLiveTvRoles>
              <EnableLiveTv>false</EnableLiveTv>
              <EnableLiveTvManagement>false</EnableLiveTvManagement>
              <LiveTvRoles />
              <LiveTvManagementRoles />
              <FolderRoleMappings />
              <RoleClaim>groups</RoleClaim>
              <OidScopes>
                <string>groups</string>
              </OidScopes>
              <DefaultProvider>kanidm</DefaultProvider>
              <SchemeOverride>https</SchemeOverride>
              <NewPath>true</NewPath>
              <CanonicalLinks />
              <DefaultUsernameClaim>preferred_username</DefaultUsernameClaim>
              <DisablePushedAuthorization>true</DisablePushedAuthorization>
              <DoNotLoadProfile>false</DoNotLoadProfile>
            </PluginConfiguration>
          </value>
        </item>
      </OidConfigs>
    </PluginConfiguration>
  '';
in
{
  # Declared for NixOS mounts, not for automatic post-provisioning changes.
  # Create these datasets manually on existing malt before switching:
  #   zfs create -o mountpoint=/var/lib/jellyfin -o com.sun:auto-snapshot=true zroot/jellyfin
  #   zfs create -o mountpoint=/srv/media -o com.sun:auto-snapshot=false zroot/media
  disko.devices.zpool.zroot.datasets = {
    "jellyfin" = {
      type = "zfs_fs";
      mountpoint = "/var/lib/jellyfin";
      options."com.sun:auto-snapshot" = "true";
    };
    "media" = {
      type = "zfs_fs";
      mountpoint = "/srv/media";
      options."com.sun:auto-snapshot" = "false";
    };
  };

  clan.core.vars.generators.kanidm-jellyfin-oidc = {
    share = true;
    files.secret = {
      secret = true;
      owner = "jellyfin";
      group = "jellyfin";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-compute-runtime
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = false;
    forceEncodingConfig = true;
    hardwareAcceleration = {
      enable = true;
      type = "qsv";
      device = "/dev/dri/renderD128";
    };
    transcoding = {
      enableHardwareEncoding = true;
      enableToneMapping = true;
      hardwareDecodingCodecs = {
        h264 = true;
        hevc = true;
        hevc10bit = true;
        vp9 = true;
        av1 = true;
      };
      hardwareEncodingCodecs = {
        hevc = true;
        av1 = true;
      };
    };
  };

  users.groups.media = { };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
    "media"
  ];

  systemd.tmpfiles.rules = [
    "d /srv/media 0755 root media -"
    "d /srv/media/movies 0755 jellyfin jellyfin -"
    "d /srv/media/tv 0755 jellyfin jellyfin -"
    "d /srv/media/music 0755 jellyfin jellyfin -"
    "d /srv/media/videos 0755 root media -"
    "d /srv/media/videos/restate 2750 media-archive media -"
    "d /var/lib/jellyfin/plugins 0750 jellyfin jellyfin -"
    "d /var/lib/jellyfin/plugins/configurations 0750 jellyfin jellyfin -"
  ];

  systemd.services.jellyfin = {
    preStart = lib.mkBefore ''
      set -euo pipefail

      plugin_dir=/var/lib/jellyfin/plugins/SSO-Auth_${ssoVersion}
      rm -rf "$plugin_dir"
      cp -R ${ssoPlugin} "$plugin_dir"
      chmod -R u+rwX,go-rwx "$plugin_dir"

      install -m 0600 ${networkConfig} /var/lib/jellyfin/config/network.xml
      install -m 0600 ${brandingConfig} /var/lib/jellyfin/config/branding.xml

      install -d -m 0750 /var/lib/jellyfin/plugins/configurations
      oidc_secret=$(<"$CREDENTIALS_DIRECTORY/oidc-secret")
      tmp_config=$(mktemp)
      ${pkgs.gnused}/bin/sed "s|@OIDC_SECRET@|$oidc_secret|g" ${ssoConfigTemplate} > "$tmp_config"
      install -m 0600 "$tmp_config" /var/lib/jellyfin/plugins/configurations/SSO-Auth.xml
      rm -f "$tmp_config"
    '';
    serviceConfig.LoadCredential = [
      "oidc-secret:${config.clan.core.vars.generators.kanidm-jellyfin-oidc.files.secret.path}"
    ];
    unitConfig.RequiresMountsFor = [
      "/srv/media"
      "/var/lib/jellyfin"
    ];
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ port ];
}
