#!/usr/bin/env bash
#
# Bootstrap a repository created from this template.
#
# Picks the toolchains this project uses, deletes the modules and flake inputs
# belonging to the ones it does not, points the template's own references at
# the new repository, swaps in a project README, re-locks the flake, and then
# removes itself.
#
# Run it once, from anywhere inside the checkout. `--help` lists the flags that
# make it non-interactive.

set -euo pipefail

# The template's own identity. These are the strings the script replaces. They
# are real values rather than placeholders so that the template repository is
# itself valid — an issue-template URL full of {{OWNER}} would just be a broken
# link.
readonly TEMPLATE_OWNER='jiezhuzzz'
readonly TEMPLATE_REPO='harder'
readonly TEMPLATE_AUTHOR='Jie Zhu'

readonly README_SOURCE='scripts/template/README.md'

if [ -t 1 ]; then
  readonly BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[31m' RESET=$'\033[0m'
else
  readonly BOLD='' DIM='' RED='' RESET=''
fi

log() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$*"; }
note() { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
warn() { printf '%swarning:%s %s\n' "$RED" "$RESET" "$*" >&2; }
die() {
  printf '%serror:%s %s\n' "$RED" "$RESET" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Bootstrap a repository created from this template.

Usage: scripts/init-from-template.sh [options]

Options:
  -n, --name NAME            Project name, used in the README title
  -d, --description TEXT     One-line description, used in flake.nix and the README
  -t, --toolchains LIST      Comma- or space-separated, e.g. "rust,web". Use
                             "none" for a Nix-and-docs-only repository
  -o, --owner OWNER          GitHub owner, for the issue-template links
  -r, --repo REPO            GitHub repository name, for those same links
  -a, --author NAME          Copyright holder in LICENSE
      --year YEAR            Copyright year in LICENSE (default: this year)

  -y, --yes                  Take every default without prompting
      --keep-script          Do not delete scripts/ when finished
      --no-lock              Skip `nix flake lock`
      --no-format            Skip `nix fmt`
  -h, --help                 Show this message

Anything not supplied is prompted for, or defaulted when there is no terminal.
EOF
}

# Rewrites a file in place, preserving its inode and mode. `mv` from a mktemp
# file would leave everything 0600.
write_back() {
  local tmp=$1 file=$2
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# Literal (non-regex, non-escaping) search and replace over a whole file.
replace_literal() {
  local file=$1 tmp
  tmp=$(mktemp "${file}.XXXXXX")
  RL_FROM=$2 RL_TO=$3 awk '
    function repl(s, from, to,   out, at) {
      out = ""
      while ((at = index(s, from)) > 0) {
        out = out substr(s, 1, at - 1) to
        s = substr(s, at + length(from))
      }
      return out s
    }
    { print repl($0, ENVIRON["RL_FROM"], ENVIRON["RL_TO"]) }
  ' "$file" >"$tmp"
  write_back "$tmp" "$file"
}

# Collapses runs of blank lines down to one. Removing a marker block leaves the
# blank line that preceded it next to the one that followed it.
squeeze_blank_lines() {
  local file=$1 tmp
  tmp=$(mktemp "${file}.XXXXXX")
  awk 'NF == 0 { if (blank++) next } NF { blank = 0 } { print }' "$file" >"$tmp"
  write_back "$tmp" "$file"
}

# Every tracked file, NUL-separated. Falls back to a filesystem walk for
# checkouts that are not git repositories, such as a downloaded archive.
list_files() {
  if [ -d .git ] && command -v git >/dev/null 2>&1; then
    git ls-files -z
  else
    find . -type f -not -path './.git/*' -print0
  fi
}

# Deletes `# >>> toolchain:NAME` ... `# <<< toolchain:NAME` blocks, markers
# included, from every file that has them.
strip_toolchain_blocks() {
  local name=$1 file tmp
  while IFS= read -r -d '' file; do
    grep -qF ">>> toolchain:${name}" "$file" 2>/dev/null || continue
    tmp=$(mktemp "${file}.XXXXXX")
    SM_NAME=$name awk '
      BEGIN {
        opening = "^[[:space:]]*#[[:space:]]*>>>[[:space:]]*toolchain:" ENVIRON["SM_NAME"] "[[:space:]]*$"
        closing = "^[[:space:]]*#[[:space:]]*<<<[[:space:]]*toolchain:" ENVIRON["SM_NAME"] "[[:space:]]*$"
      }
      $0 ~ opening { inside = 1; next }
      inside && $0 ~ closing { inside = 0; next }
      inside { next }
      { print }
    ' "$file" >"$tmp"
    write_back "$tmp" "$file"
    squeeze_blank_lines "$file"
    note "stripped toolchain:${name} from ${file}"
  done < <(list_files)
}

# Replaces the contents of a `key = [ ... ];` list in a Nix file. Called with no
# items it leaves an empty list for the formatter to collapse.
set_nix_list() {
  local file=$1 key=$2
  shift 2
  local rendered='' item tmp
  for item in "$@"; do
    rendered+="    \"${item}\""$'\n'
  done
  tmp=$(mktemp "${file}.XXXXXX")
  SN_KEY=$key SN_ITEMS=$rendered awk '
    BEGIN { opening = "^[[:space:]]*" ENVIRON["SN_KEY"] "[[:space:]]*=[[:space:]]*\\[" }
    !done && $0 ~ opening {
      print "  " ENVIRON["SN_KEY"] " = ["
      printf "%s", ENVIRON["SN_ITEMS"]
      inside = 1
      next
    }
    inside && /^[[:space:]]*\];[[:space:]]*$/ { print "  ];"; inside = 0; done = 1; next }
    inside { next }
    { print }
  ' "$file" >"$tmp"
  write_back "$tmp" "$file"
}

# Replaces the value of the first `key = "...";` in a Nix file.
set_nix_string() {
  local file=$1 key=$2 value=$3 tmp
  tmp=$(mktemp "${file}.XXXXXX")
  SS_KEY=$key SS_VALUE=$value awk '
    BEGIN { opening = "^[[:space:]]*" ENVIRON["SS_KEY"] "[[:space:]]*=[[:space:]]*\"" }
    !done && $0 ~ opening {
      print "  " ENVIRON["SS_KEY"] " = \"" ENVIRON["SS_VALUE"] "\";"
      done = 1
      next
    }
    { print }
  ' "$file" >"$tmp"
  write_back "$tmp" "$file"
}

ask() {
  local var=$1 prompt=$2 default=$3 reply=''
  if [ "$assume_yes" = true ] || [ ! -t 0 ]; then
    printf -v "$var" '%s' "$default"
    return
  fi
  read -r -p "${prompt} [${default}]: " reply || reply=''
  printf -v "$var" '%s' "${reply:-$default}"
}

# ---------------------------------------------------------------------------

name=''
description=''
toolchains_arg=''
owner=''
repo=''
author=''
year=''
assume_yes=false
keep_script=false
do_lock=true
do_format=true
toolchains_given=false

while [ $# -gt 0 ]; do
  case $1 in
  -n | --name)
    name=${2:-}
    shift 2
    ;;
  -d | --description)
    description=${2:-}
    shift 2
    ;;
  -t | --toolchains)
    toolchains_arg=${2:-}
    toolchains_given=true
    shift 2
    ;;
  -o | --owner)
    owner=${2:-}
    shift 2
    ;;
  -r | --repo)
    repo=${2:-}
    shift 2
    ;;
  -a | --author)
    author=${2:-}
    shift 2
    ;;
  --year)
    year=${2:-}
    shift 2
    ;;
  -y | --yes)
    assume_yes=true
    shift
    ;;
  --keep-script)
    keep_script=true
    shift
    ;;
  --no-lock)
    do_lock=false
    shift
    ;;
  --no-format)
    do_format=false
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown option: $1 (try --help)" ;;
  esac
done

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/.." && pwd)
cd "$root"

[ -f flake.nix ] && [ -f project.nix ] || die "$root does not look like this template (no flake.nix and project.nix)"
[ -f "$README_SOURCE" ] || die "$README_SOURCE is gone — this repository has already been bootstrapped"

available=()
for module in nix/toolchains/*.nix; do
  [ -e "$module" ] || continue
  available+=("$(basename "$module" .nix)")
done
[ ${#available[@]} -gt 0 ] || die 'no toolchain modules found under nix/toolchains/'

# Defaults come from the git remote where there is one, so the common case is
# pressing Enter through every prompt.
remote_url=$(git remote get-url origin 2>/dev/null || true)
if [[ $remote_url =~ github\.com[:/]+([^/]+)/([^/]+)$ ]]; then
  default_owner=${BASH_REMATCH[1]}
  default_repo=${BASH_REMATCH[2]%.git}
else
  default_owner=$TEMPLATE_OWNER
  default_repo=$(basename "$root")
fi

current_toolchains=$(
  awk '/^[[:space:]]*toolchains[[:space:]]*=/, /\];/' project.nix |
    grep -o '"[^"]*"' | tr -d '"' | tr '\n' ',' | sed 's/,$//'
)

log 'Setting up this repository'
ask name 'Project name' "${name:-$default_repo}"
ask description 'One-line description' "${description:-A project built from the harder template}"
ask owner 'GitHub owner' "${owner:-$default_owner}"
ask repo 'GitHub repository' "${repo:-$default_repo}"
ask author 'Copyright holder' "${author:-$(git config user.name || echo "$TEMPLATE_AUTHOR")}"
ask year 'Copyright year' "${year:-$(date +%Y)}"

if [ "$toolchains_given" = false ]; then
  note "available: ${available[*]}  (comma-separated, or 'none')"
  ask toolchains_arg 'Toolchains' "${current_toolchains:-none}"
fi

toolchains=()
if [ "$toolchains_arg" != 'none' ] && [ -n "$toolchains_arg" ]; then
  IFS=', ' read -r -a toolchains <<<"$toolchains_arg"
fi

for want in ${toolchains[@]+"${toolchains[@]}"}; do
  found=false
  for have in "${available[@]}"; do
    [ "$want" = "$have" ] && found=true && break
  done
  [ "$found" = true ] || die "unknown toolchain '$want' (available: ${available[*]})"
done

[ -n "$name" ] || die 'a project name is required'
[ -n "$owner" ] && [ -n "$repo" ] || die 'a GitHub owner and repository are required'

# ---------------------------------------------------------------------------

log 'Selecting toolchains'
set_nix_list project.nix toolchains ${toolchains[@]+"${toolchains[@]}"}
if [ ${#toolchains[@]} -eq 0 ]; then
  note 'none — the dev shell will carry only the git hook packages'
else
  note "keeping: ${toolchains[*]}"
fi

for have in "${available[@]}"; do
  keep=false
  for want in ${toolchains[@]+"${toolchains[@]}"}; do
    [ "$want" = "$have" ] && keep=true && break
  done
  [ "$keep" = true ] && continue

  strip_toolchain_blocks "$have"
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    git rm -q -f "nix/toolchains/${have}.nix"
  else
    rm -f "nix/toolchains/${have}.nix"
  fi
  note "removed nix/toolchains/${have}.nix"
done

log 'Rewriting project metadata'
# Nix string literals give `\`, `"` and `${` a meaning, so neutralise all three
# before the description goes into flake.nix.
nix_description=${description//\\/\\\\}
nix_description=${nix_description//\"/\\\"}
nix_description=${nix_description//\$/\\\$}
set_nix_string flake.nix description "$nix_description"

for file in LICENSE README.md CONTRIBUTING.md .github/ISSUE_TEMPLATE/config.yml; do
  [ -f "$file" ] || continue
  replace_literal "$file" "${TEMPLATE_OWNER}/${TEMPLATE_REPO}" "${owner}/${repo}"
  replace_literal "$file" "$TEMPLATE_AUTHOR" "$author"
done
replace_literal LICENSE 'Copyright (c) 2026' "Copyright (c) ${year}"
note "owner ${owner}/${repo}, © ${year} ${author}"

log 'Writing README.md'
cp "$README_SOURCE" README.md
replace_literal README.md '{{PROJECT_NAME}}' "$name"
replace_literal README.md '{{PROJECT_DESCRIPTION}}' "$description"

if command -v nix >/dev/null 2>&1; then
  if [ "$do_lock" = true ]; then
    log 'Re-locking the flake'
    nix flake lock || warn 'nix flake lock failed — run it yourself once the tree is committed'
  fi
  if [ "$do_format" = true ]; then
    log 'Formatting'
    nix fmt >/dev/null || warn 'nix fmt failed — run it yourself'
  fi
else
  warn 'nix is not on PATH; skipping the lock and format steps'
fi

if [ "$keep_script" = true ]; then
  log 'Keeping scripts/'
else
  log 'Removing scripts/'
  # Safe while this script is still executing: unlinking leaves the inode alive
  # for the file descriptor bash already holds.
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    git rm -rq -f scripts
  else
    rm -rf scripts
  fi
fi

cat <<EOF

${BOLD}Done.${RESET} Next:

  1. Read through the diff — ${BOLD}git diff${RESET}
  2. Enter the dev shell   — ${BOLD}nix develop${RESET}
  3. Commit                — ${BOLD}git add -A && git commit -m 'chore: bootstrap from template'${RESET}

Optional repository settings are listed under "Repository settings" in the
template's README, which this run replaced. The short version: set the
ANTHROPIC_API_KEY secret for the Claude workflows, the CACHIX_CACHE variable
for the binary cache, and protect main so the branch rules bind everyone.
EOF
