{
  self,
  config,
  ...
}:
{
  _module.args.wgLib = import ./lib/wg.nix { inherit self config; };

  # Shared scanner noise filter for app vhosts. Keep this near the
  # $block_dotted map so the helper and its nginx variable stay together.
  _module.args.blockDottedPathsConfig = ''
    if ($block_dotted) { return 404; }
  '';

  # nginx enablement, recommended settings, and public 80/443 firewall
  # opening come from srvos.nixosModules.mixins-nginx in taps/configuration.nix.
  imports = [
    ./atuin.nix
    ./blog.nix
    ./home-assistant.nix
    ./jellyfin.nix
    ./linkwarden.nix
    ./miniflux.nix
    ./mulatta-io.nix
    ./mta-sts.nix
    ./ntfy.nix
    ./n8n.nix
    ./uptermd.nix
    ./nextcloud.nix
    ./paperless.nix
    ./radicle.nix
    ./restate.nix
    ./stalwart.nix
    ./step-ca.nix
    ./vaultwarden.nix
    ./nostr.nix
    ./nip05.nix
    ./security-txt.nix
    ./vikunja.nix
    ./zotero.nix
  ];

  services.nginx = {
    # Fix "could not build optimal proxy_headers_hash" warning
    proxyTimeout = "3600s";
    appendHttpConfig = ''
      proxy_headers_hash_max_size 1024;
      proxy_headers_hash_bucket_size 128;

      # Shared AI crawler user-agent map. Virtual hosts opt in by
      # returning 403 when $block_ai is truthy. The list focuses on
      # agents that are either well-known for ignoring robots.txt or
      # whose training usage we want to refuse regardless of declared
      # intent. Cloudflare bot features are unavailable because
      # mulatta.io runs DNS-only.
      map $http_user_agent $block_ai {
        default 0;
        "~*(GPTBot|ChatGPT-User|OAI-SearchBot|ClaudeBot|Claude-Web|Claude-User|anthropic-ai|CCBot|Bytespider|Amazonbot|Google-Extended|Applebot-Extended|PerplexityBot|Meta-ExternalAgent|Meta-ExternalFetcher|DuckAssistBot|cohere-ai|cohere-training-data-crawler|AI2Bot|Diffbot|ImagesiftBot|Omgilibot|YouBot|Bravebot)" 1;
      }

      # Shared dotted-path scanner map. Opt-in per vhost by returning 404
      # when $block_dotted is truthy. /.well-known/ is always allowed so
      # ACME challenges, CalDAV/WebFinger/NIP-05 continue to work.
      map $request_uri $block_dotted {
        default 0;
        "~^/\.well-known/" 0;
        "~^/\."            1;
      }
    '';

    commonHttpConfig = ''
      add_header Strict-Transport-Security 'max-age=31536000; includeSubDomains; preload' always;
    '';

    # Reject unknown hosts
    virtualHosts."_" = {
      default = true;
      rejectSSL = true;
      locations."/".return = "444";
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "acme@mulatta.io";
      # Use Let's Encrypt production server instead of minica
      server = "https://acme-v02.api.letsencrypt.org/directory";
    };
  };
}
