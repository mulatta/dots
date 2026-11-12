#!/usr/bin/env bash
# Claude Code status line: only what Herdr's agents list does not already show.
# Layout adapted from github.com/Gui-Gou/claude-statusline-burnrate (MIT).
#
#   Opus 5.5 · medium ❯ ~/dots ❯ main ❯ #12 ❯ +672 −114      CTX ▰▱▱▱▱▱▱ 17% 168k/1M │ TTL ▰▰▰▰▰▰▰ 98% 59m/1h │ 5H ▰▱▱▱▱▱▱ 6% ↻ 4h09m │ WK ▰▱▱▱▱▱▱ 14% ↻ 5d18h │ $42.38
#
# Same shape as the pi footer: text on the left, cells flush right. A pane too narrow for one
# line gets the cells on their own line; then the text wraps at ❯ and the cells drop amounts
# and timers, then bars, so Claude Code never has to cut a segment.
#
# Claude Code reruns this every few seconds per pane, so helpers return through variables
# instead of command substitution: each $(...) forks, and forks were most of the cost.
set -u
export LC_ALL=${LC_ALL:-en_US.UTF-8}

# The prompt cache comes from the snapshot hmeter wrote for this terminal just before drawing.
snap=/dev/null
if [ -n "${HMETER_SNAPSHOT:-}" ]; then
  snap=$HMETER_SNAPSHOT
elif [ -n "${HC_TERMINAL_ID:-}" ]; then
  snap=${XDG_STATE_HOME:-$HOME/.local/state}/herdr-meter/sessions/$HC_TERMINAL_ID.json
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

# Model and effort, written as pi shows them.
model=${model%% (*}
case ${model,,} in
*opus*) mc=PEACH ;; *sonnet*) mc=BLUE ;; *fable*) mc=MAUVE ;; *haiku*) mc=GREEN ;;
*gpt*) mc=TEAL ;; *) mc=SUB ;;
esac
case $eff in low) ec=OVL ;; high) ec=YEL ;; xhigh | max) ec=RED ;; *) ec=SUB ;; esac
title=""
[ -n "$model" ] && title="${C[$mc]}$model$R"
[ -n "$eff" ] && title+="${title:+ ${C[OVL]}·$R }${C[$ec]}$eff$R"
price=""
[ -n "$cost" ] && printf -v price '%s$%.2f%s' "${C[SUB]}" "$cost" "$R"

# Cells: label, bar, share, then the amount behind the share; a shorter amount for narrow panes.
heads=() pcts=() hues=() tails=() lows=() shorts=()
cell() { # $1 label, $2 percent, $3 bar color name or "ramp", $4 share text, $5 amount, $6 short amount
  heads+=("${C[OVL]}$1$R") pcts+=("$2") hues+=("$3") tails+=("$4") lows+=("$5") shorts+=("${6-}")
}

if [ -n "$cpct" ]; then
  int "$cpct"
  p=$INT tk=$ctok
  [[ $tk =~ ^[0-9]+$ ]] || tk=$(awk -v p="$cpct" -v w="${cwsz:-0}" 'BEGIN{printf "%d", p*w/100}')
  kilo "$tk"
  short=$KILO low=$KILO
  if [[ $cwsz =~ ^[0-9]+$ ]]; then
    kilo "$cwsz"
    low+="${C[OVL]}/$KILO$R"
  fi
  cell CTX "$p" ramp "$p%" "$low" "$short"
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
    cell TTL "$frac" "$wc" "${C[$wc]}$blink$frac%$R" "${C[$wc]}$blink$SPAN$R${C[OVL]}/$ttl$R" "${C[$wc]}$blink$SPAN$R"
  else
    cell TTL 0 SURF "${C[OVL]}cold$R" "" ""
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
  cell "$1" "$INT" ramp "$INT%" "$r" ""
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

# Claude Code cuts lines short instead of wrapping them, so size the output to the pane.
# The margin leaves room for Claude Code's own indent.
cols=${SL_COLS:-0}
if [ -z "${SL_COLS:-}" ] && [ -n "${HC_TERMINAL_ID:-}" ]; then
  [[ $(hc get "$HC_TERMINAL_ID" --json 2>/dev/null) =~ \"cols\":([0-9]+) ]] && cols=${BASH_REMATCH[1]}
fi
max=$((cols > 0 ? cols - 4 : 1 << 30))

# ---- layout --------------------------------------------------------------------------
glue() { # GLUED = the non-empty arguments joined by $1
  local sep=$1 x
  shift
  GLUED=""
  for x in "$@"; do
    [ -n "$x" ] || continue
    GLUED+="${GLUED:+$sep}$x"
  done
}
join() { # JOINED = the non-empty arguments joined by $1 (of width $2), wrapped at max
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
csep=" ${C[SURF]}│$R "
cellline() { # LINE = the cells at level $1 (0 full, 1 short amounts, 2 no bars), then the price
  local lvl=$1 i s a
  PARTS=()
  for ((i = 0; i < n; i++)); do
    if ((lvl < 2)); then
      bar 7 "${pcts[i]}" "${hues[i]}"
      s="${heads[i]} $BAR ${tails[i]}"
    else
      s="${heads[i]} ${tails[i]}"
    fi
    case $lvl in 0) a=${lows[i]} ;; 1) a=${shorts[i]} ;; *) a="" ;; esac
    PARTS+=("$s${a:+ $a}")
  done
  glue "$csep" "${PARTS[@]}" "$price"
  LINE=$GLUED
}

n=${#heads[@]}
sep=" ${C[SURF]}❯$R "
glue "$sep" "$title" "${place[@]}" "$diff"
text=$GLUED
cellline 0
if [ -z "$LINE" ] || ((cols == 0)); then
  printf '%s%s' "$text" "${LINE:+  $LINE}"
  exit 0
fi
vis "$text"
tw=$VIS
vis "$LINE"
cw=$VIS
if ((tw + 1 + cw <= max)); then
  printf '%s%*s%s' "$text" $((max - tw - cw)) '' "$LINE"
  exit 0
fi

# Too narrow for one line: the cells go below, whole. Only then the text wraps at ❯ and the
# cells lose amounts and timers, then bars, so nothing is cut inside a segment.
if ((tw > max)); then
  join "$sep" 3 "$title" "${place[@]}" "$diff"
  text=$JOINED
fi
lvl=0
while ((cw > max && lvl < 2)); do
  cellline $((++lvl))
  vis "$LINE"
  cw=$VIS
done
if ((cw > max)); then
  join "$csep" 3 "${PARTS[@]}" "$price"
  LINE=$JOINED
fi
printf '%s\n%s' "$text" "$LINE"
