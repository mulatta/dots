{ pkgs, ... }:
{
  clan.core.vars.generators.mulatta-password = {
    files.password-hash.neededFor = "users";
    files.password.deploy = false;
    runtimeInputs = [
      pkgs.mkpasswd
      pkgs.xkcdpass
    ];
    prompts.password.type = "hidden";
    script = ''
       prompt_value="$(cat "$prompts"/password)"
      if [[ -n "''${prompt_value-}" ]]; then
        echo "$prompt_value" | tr -d "\n" > "$out"/password
      else
        xkcdpass --numwords 4 --delimiter - --count 1 | tr -d "\n" > "$out"/password
      fi
      mkpasswd -s -m sha-512 < "$out"/password | tr -d "\n" > "$out"/password-hash
    '';
  };
}
