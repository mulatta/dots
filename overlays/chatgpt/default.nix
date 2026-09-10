{ inputs }:
_final: prev:
let
  upstream = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}.chatgpt;
  unwrapped = upstream.unwrapped.overrideAttrs (old: {
    # app.asar and bundled scripts change during the build, invalidating the
    # upstream signature. Refresh integrity metadata before signing.
    postFixup = (old.postFixup or "") + ''
      python3 ${./refresh-asar-integrity.py} \
        "$out/Applications/ChatGPT.app/Contents/Resources/app.asar"
      /usr/bin/codesign --force --deep --sign - \
        "$out/Applications/ChatGPT.app"
      /usr/bin/codesign --verify --deep --strict \
        "$out/Applications/ChatGPT.app"
    '';
  });
  wrapped = upstream.override {
    chatgpt-unwrapped = unwrapped;
  };
in
if prev.stdenv.hostPlatform.isDarwin then
  {
    chatgpt = wrapped.overrideAttrs (old: {
      # Execute by the bundle path and expose the app from the wrapped package.
      # The upstream executable symlink breaks Frameworks.
      installPhase =
        builtins.replaceStrings
          [ "${unwrapped}/bin/chatgpt" ]
          [ "${unwrapped}/Applications/ChatGPT.app/Contents/MacOS/ChatGPT" ]
          old.installPhase
        + ''
          mkdir -p "$out/Applications"
          ln -s ${unwrapped}/Applications/ChatGPT.app \
            "$out/Applications/ChatGPT.app"
        '';
    });
  }
else
  { chatgpt = upstream; }
