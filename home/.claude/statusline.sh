#!/usr/bin/env bash
# Claude Code status line: only what Herdr's agents list does not already show.
# Layout adapted from github.com/Gui-Gou/claude-statusline-burnrate (MIT).
#
#   ╭─ OPUS 5.5 · MEDIUM ──────────────────────────────────────── $42.38 ─╮
#   │ CTX ▰▱▱▱▱▱▱ 17% │ TTL ▰▰▰▰▰▰▰ 98% │ 5H ▰▱▱▱▱▱▱ 6% │ WK ▰▱▱▱▱▱▱ 14% │
#   │ 168k/1M         │ 59m/1h          │ ↻ 4h09m       │ ↻ 5d18h        │
#   ╰─ ~/dots  main ─────────────────────────────────────────── +672 −114 ─╯
#
# Each cell shows a share on top and the amount behind it below. The frame fades from the
# model's color to gray. A pane too narrow for the card gets two plain lines.
#
# Claude Code reruns this every few seconds per pane, so helpers return through variables
# instead of command substitution: each $(...) forks, and forks were most of the cost.
set -u
export LC_ALL=${LC_ALL:-en_US.UTF-8}

# The prompt cache comes from the snapshot hq wrote for this terminal just before drawing.
snap=/dev/null
if [ -n "${HQ_SNAPSHOT:-}" ]; then
  snap=$HQ_SNAPSHOT
elif [ -n "${HC_TERMINAL_ID:-}" ]; then
  snap=${XDG_STATE_HOME:-$HOME/.local/state}/herdr-queue/sessions/$HC_TERMINAL_ID.json
fi
[ -r "$snap" ] || snap=/dev/null
IFS=$'\x1f' read -r model eff cpct ctok cwsz cost ladd lrem cur proj h5p h5r wkp wkr prn prs exp ttl < <(jq -rs '
  .[0] as $i | (.[1].cache // {}) as $c | $i |
  [ (.model.display_name // ""), (.effort.level // ""),
    (.context_window.used_percentage // "" | tostring),
    (.context_window.total_input_tokens // "" | tostring),
    (.context_window.context_window_size // "" | tostring),
    (.cost.total_cost_usd // "" | tostring),
    (.cost.total_lines_added // 0 | tostring), (.cost.total_lines_removed // 0 | tostring),
    (.workspace.current_dir // .cwd // ""), (.workspace.project_dir // ""),
    (.rate_limits.five_hour.used_percentage // "" | tostring),
    (.rate_limits.five_hour.resets_at // "" | tostring),
    (.rate_limits.seven_day.used_percentage // "" | tostring),
    (.rate_limits.seven_day.resets_at // "" | tostring),
    (.pr.number // "" | tostring), (.pr.review_state // ""),
    ($c.expiresAt // "" | tostring), ($c.ttl // "5m") ] | join("\u001f")' - "$snap")
now=${SL_NOW:-$EPOCHSECONDS}

e=$'\e' R=$'\e[0m'
# Catppuccin Mocha, to match the agents list: RGB by name, and C holds each escape.
declare -A RGB=([SUB]="166;173;200" [SURF]="69;71;90" [OVL]="108;112;134" [PEACH]="250;179;135"
  [YEL]="249;226;175" [RED]="243;139;168" [BLUE]="137;180;250" [MAUVE]="203;166;247"
  [GREEN]="166;227;161" [TEAL]="148;226;213") C=()
for c in "${!RGB[@]}"; do C[$c]="${e}[38;2;${RGB[$c]}m"; done
RAMP=(SUB YEL YEL PEACH RED)

vis() { # VIS = visible width of $1
  # Cut one escape at a time: an extglob ${1//...} costs about 15ms per bar cell line.
  local s=$1 out=""
  while [[ $s == *$'\e['* ]]; do
    out+=${s%%$'\e['*}
    s=${s#*$'\e['}
    s=${s#*m}
  done
  out+=$s
  VIS=${#out}
}
pad() { # PAD = $1 padded with spaces to $2 visible columns
  vis "$1"
  printf -v PAD '%s%*s' "$1" $(($2 > VIS ? $2 - VIS : 0)) ''
}
kilo() { # KILO = $1 as 840, 168k or 1M
  if (($1 >= 1000000)); then
    KILO="$(($1 / 1000000))M"
  elif (($1 >= 1000)); then
    KILO="$(($1 / 1000))k"
  else KILO=$1; fi
}
span() { # SPAN = $1 seconds as 5d18h, 4h09m, 12m or 40s
  local s=$1
  if ((s >= 86400)); then
    printf -v SPAN '%dd%02dh' $((s / 86400)) $((s % 86400 / 3600))
  elif ((s >= 3600)); then
    printf -v SPAN '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  elif ((s > 120)); then
    SPAN="$((s / 60))m"
  else SPAN="${s}s"; fi
}
int() { # INT = $1 rounded; shares arrive as floats
  printf -v INT '%.0f' "${1:-0}" 2>/dev/null || INT=0
}
bar() { # BAR = $1 cells at $2 percent; $3 = a color name, or "ramp" to warm as it fills
  local n=$1 p=$2 lit i c x
  BAR=""
  lit=$(((p * n + 50) / 100))
  ((p > 0 && lit == 0)) && lit=1
  ((lit > n)) && lit=n
  for ((i = 0; i < n; i++)); do
    if ((i >= lit)); then
      c=SURF x=▱
    elif [ "$3" = ramp ]; then
      c=${RAMP[i * 5 / n]} x=▰
    else
      c=$3 x=▰
    fi
    BAR+=${C[$c]}$x
  done
  BAR+=$R
}

# Model and effort; the model's color also tints the frame.
model=${model%% (*}
case ${model,,} in
*opus*) mc=PEACH ;; *sonnet*) mc=BLUE ;; *fable*) mc=MAUVE ;; *haiku*) mc=GREEN ;;
*gpt*) mc=TEAL ;; *) mc=SUB ;;
esac
case $eff in low) ec=OVL ;; high) ec=YEL ;; xhigh | max) ec=RED ;; *) ec=SUB ;; esac
title=""
[ -n "$model" ] && title="${C[$mc]}${model^^}$R"
[ -n "$eff" ] && title+="${title:+ ${C[OVL]}·$R }${C[$ec]}${eff^^}$R"
price=""
[ -n "$cost" ] && printf -v price '%s$%.2f%s' "${C[SUB]}" "$cost" "$R"

# Cells: label, bar and share on top, the amount behind the share below.
heads=() pcts=() hues=() tails=() lows=() tops=()
cell() { # $1 label, $2 percent, $3 bar color name or "ramp", $4 share text, $5 amount
  heads+=("${C[OVL]}$1$R") pcts+=("$2") hues+=("$3") tails+=("$4") lows+=("$5")
}
draw() { # tops = each cell's top line with $1-cell bars
  local i
  tops=()
  for ((i = 0; i < ${#heads[@]}; i++)); do
    bar "$1" "${pcts[i]}" "${hues[i]}"
    tops+=("${heads[i]} $BAR ${tails[i]}")
  done
}

if [ -n "$cpct" ]; then
  int "$cpct"
  p=$INT tk=$ctok
  [[ $tk =~ ^[0-9]+$ ]] || tk=$(awk -v p="$cpct" -v w="${cwsz:-0}" 'BEGIN{printf "%d", p*w/100}')
  kilo "$tk"
  low=$KILO
  if [[ $cwsz =~ ^[0-9]+$ ]]; then
    kilo "$cwsz"
    low+="${C[OVL]}/$KILO$R"
  fi
  cell CTX "$p" ramp "$p%" "$low"
fi

# Warmth runs peach -> yellow -> blue as the TTL drains, like the agents list rings.
if [[ $exp =~ ^[0-9]+$ ]]; then
  left=$((exp - now)) total=300
  [ "$ttl" = 1h ] && total=3600
  if ((left > 0)); then
    frac=$((left * 100 / total))
    if ((frac > 50)); then wc=PEACH; elif ((frac > 15)); then wc=YEL; else wc=BLUE; fi
    blink=""
    ((left <= 120)) && blink=$'\e[5m'
    span "$left"
    cell TTL "$frac" "$wc" "${C[$wc]}$blink$frac%$R" "${C[$wc]}$blink$SPAN$R${C[OVL]}/$ttl$R"
  else
    cell TTL 0 SURF "${C[OVL]}0%$R" "${C[OVL]}cold$R"
  fi
fi

limit() { # $1 label, $2 used percent, $3 reset epoch
  [ -n "$2" ] || return 0
  local r=""
  int "$2"
  if [[ $3 =~ ^[0-9]+$ ]] && (($3 > now)); then
    span $(($3 - now))
    r="${C[OVL]}↻$R $SPAN"
  fi
  cell "$1" "$INT" ramp "$INT%" "$r"
}
limit 5H "$h5p" "$h5r"
limit WK "$wkp" "$wkr"

# Where Claude works: amber once it leaves the launch folder, red in another repo,
# where edits may land in the wrong place.
gitroot() { # ROOT = nearest folder above $1 holding .git, or empty
  local d=$1
  ROOT=""
  while [ -n "$d" ] && [ "$d" != / ]; do
    [ -e "$d/.git" ] && {
      ROOT=$d
      return
    }
    d=${d%/*}
  done
}
place=()
if [ -n "$cur" ]; then
  cur=${cur%/} proj=${proj%/}
  short=${cur/#$HOME/\~}
  dc=SUB
  gitroot "$cur"
  cr=$ROOT
  if [ -n "$proj" ] && [[ $cur/ != "$proj"/* ]]; then
    gitroot "$proj"
    if [ -n "$cr" ] && [ "$cr" != "$ROOT" ]; then dc=RED; else dc=YEL; fi
  fi
  place+=("${C[$dc]}$short$R")

  # Branch from the HEAD file, so the render never waits on git.
  if [ -n "$cr" ]; then
    gd=$cr/.git
    if [ -f "$gd" ]; then
      read -r _ gd <"$gd"
      [[ $gd == /* ]] || gd=$cr/$gd
    fi
    head=""
    read -r head <"$gd/HEAD" 2>/dev/null
    case $head in
    "ref: refs/heads/"*) place+=("${C[MAUVE]}${head#ref: refs/heads/}$R") ;;
    ?*) place+=("${C[OVL]}${head:0:8}$R") ;;
    esac
  fi
fi
# The branch's pull request, colored by review state.
if [ -n "$prn" ]; then
  case $prs in approved) pc=GREEN ;; changes_requested) pc=RED ;; *) pc=SUB ;; esac
  place+=("${C[$pc]}#$prn$R")
fi
diff=""
((ladd + lrem > 0)) && diff="${C[GREEN]}+$ladd$R ${C[RED]}−$lrem$R"
where=""
for x in "${place[@]}"; do where+="${where:+  }$x"; done

# Claude Code cuts lines short instead of wrapping them, so size the output to the pane.
# The margin leaves room for Claude Code's own indent.
cols=${SL_COLS:-0}
if [ -z "${SL_COLS:-}" ] && [ -n "${HC_TERMINAL_ID:-}" ]; then
  [[ $(hc get "$HC_TERMINAL_ID" --json 2>/dev/null) =~ \"cols\":([0-9]+) ]] && cols=${BASH_REMATCH[1]}
fi
max=$((cols > 0 ? cols - 4 : 1 << 30))

# ---- card ----------------------------------------------------------------------------
draw 7
n=${#tops[@]}
widths=() inner=0
for ((i = 0; i < n; i++)); do
  vis "${tops[i]}"
  a=$VIS
  vis "${lows[i]}"
  widths+=($((a > VIS ? a : VIS)))
  inner=$((inner + widths[i] + (i ? 3 : 0)))
done
inner=$((inner + 2))
vis "$title"
tv=$VIS
vis "$price"
cv=$VIS
vis "$where"
pv=$VIS
vis "$diff"
dv=$VIS
need=$((tv + 6 + (cv ? cv + 3 : 0)))
((need > inner)) && inner=$need
need=$((pv + 6 + (dv ? dv + 3 : 0)))
((need > inner)) && inner=$need
W=$((inner + 2))
if ((W <= max && n > 0)) && [ -n "$title" ]; then
  read -r wr wg wb <<<"${RGB[$mc]//;/ }"
  read -r sr sg sb <<<"${RGB[SURF]//;/ }"
  run() { # appends $1 to O $2 times from column $3, fading from the model color to gray
    local ch=$1 col=$3 i t c
    for ((i = col; i < col + $2; i++)); do
      t=$((i * 100 / (W - 1)))
      printf -v c '%s[38;2;%d;%d;%dm%s' "$e" $(((wr * (100 - t) + sr * t) / 100)) $(((wg * (100 - t) + sg * t) / 100)) $(((wb * (100 - t) + sb * t) / 100)) "$ch"
      O+=$c
    done
    O+=$R
  }
  edge() { # a border line: $1 left corner, $2 right corner, $3 left caption, $4 right caption
    local lv rv
    vis "$3"
    lv=$VIS
    vis "$4"
    rv=$VIS
    run "$1" 1 0
    run '─' 1 1
    O+=" $3 "
    if ((rv)); then
      run '─' $((inner - lv - rv - 6)) $((lv + 4))
      O+=" $4 "
      run '─' 1 $((W - 2))
    else
      run '─' $((inner - lv - 3)) $((lv + 4))
    fi
    run "$2" 1 $((W - 1))
  }
  row() { # a row of cells from the array named $1; the last takes the leftover width
    local -n cells=$1
    local i col=2 w
    run '│' 1 0
    O+=" "
    for ((i = 0; i < n; i++)); do
      w=${widths[i]}
      ((i == n - 1)) && w=$((inner - col))
      pad "${cells[i]}" "$w"
      O+=$PAD
      col=$((col + w))
      if ((i < n - 1)); then
        O+=" "
        run '│' 1 $((col + 1))
        O+=" "
        col=$((col + 3))
      fi
    done
    O+=" "
    run '│' 1 $((W - 1))
  }
  O=""
  edge '╭' '╮' "$title" "$price"
  O+=$'\n'
  row tops
  O+=$'\n'
  row lows
  O+=$'\n'
  edge '╰' '╯' "$where" "$diff"
  printf '%s' "$O"
  exit 0
fi

# ---- two plain lines, wrapped at segment boundaries ----------------------------------
join() { # JOINED = the segments after $1 (separator) and $2 (its width), wrapped to max
  local sep=$1 sw=$2 x width=0
  shift 2
  JOINED=""
  for x in "$@"; do
    [ -n "$x" ] || continue
    vis "$x"
    if ((width == 0)); then
      JOINED+=$x width=$VIS
    elif ((width + sw + VIS > max)); then
      JOINED+=$'\n'$x width=$VIS
    else
      JOINED+=$sep$x width=$((width + sw + VIS))
    fi
  done
}
join " ${C[SURF]}│$R " 3 "$title" "$price" "${tops[@]}"
top=$JOINED
join "  " 2 "${place[@]}" "$diff"
printf '%s' "$top${top:+${JOINED:+$'\n'}}$JOINED"
