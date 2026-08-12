#!/usr/bin/env bash
#
# Scaffold a new project from this template.
#
# Invoked as `nix run github:jiezhuzzz/harder -- <directory> [options]`. The
# template source is this flake's own tree, baked in at build time, so the
# script and the files it transforms always come from the same revision. The
# run copies that tree into <directory>, keeps the toolchains the project
# wants and strips the rest, rewrites the project metadata, and leaves a
# committed git repository behind.
#
# It then creates the GitHub repository and applies the two things that only
# exist server-side: the issue labels from .github/labels.json and the branch
# ruleset from .github/rulesets/main.json. That half needs an authenticated
# `gh` and is skipped, with the commands to run yourself, when it is missing.

set -euo pipefail

# Substituted by nix/app.nix at build time. The environment variable wins so
# the script stays runnable straight from a checkout during development:
#   TEMPLATE_SOURCE=. bash nix/scaffold.sh /tmp/somewhere
TEMPLATE_SOURCE=${TEMPLATE_SOURCE:-@templateSource@}

# The template's own identity. These are the strings the script replaces. They
# are real values rather than placeholders so that the template repository is
# itself valid — an issue-template URL full of {{OWNER}} would just be a broken
# link.
readonly TEMPLATE_OWNER='jiezhuzzz'
readonly TEMPLATE_REPO='harder'
readonly TEMPLATE_AUTHOR='Jie Zhu'

# The CLI, declared as argc (https://github.com/sigoden/argc) comment tags.
# argc parses the arguments into argc_* variables and generates --help. The
# tags must sit above every function definition, or argc reads them as a
# subcommand's.

# @describe Scaffold a new project from this template. Anything not supplied is prompted for, or defaulted when there is no terminal.
# @arg target! The directory to create
# @option -n --name Project name, used in the README title (default: the directory's basename)
# @option -d --description One-line description, used in flake.nix and the README
# @option -t --toolchain Comma- or space-separated, e.g. "python,rust"; "none" for a Nix-and-docs-only repository
# @option -o --owner GitHub owner (default: the account `gh` is logged in as)
# @option -r --repo GitHub repository name (default: the directory's basename)
# @option -v --visibility[=private|public|internal] Visibility of the repository it creates
# @option -a --author Copyright holder in LICENSE
# @option --year Copyright year in LICENSE (default: this year)
# @flag -y --yes Take every default without prompting
# @flag --no-lock Skip `nix flake lock`
# @flag --no-format Skip `nix fmt`
# @flag --no-git Skip `git init` and the bootstrap commit
# @flag --no-github Skip the GitHub repository, its labels and its branch ruleset
eval "$(argc --argc-eval "$0" "$@")"

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

# Deletes `# >>> MARKER` ... `# <<< MARKER` blocks, markers included, from
# every file that has them. Called with e.g. "toolchain:go" or "scaffold".
strip_marker_blocks() {
  local marker=$1 file tmp
  while IFS= read -r -d '' file; do
    grep -qF ">>> ${marker}" "$file" 2>/dev/null || continue
    tmp=$(mktemp "${file}.XXXXXX")
    SM_MARKER=$marker awk '
      BEGIN {
        opening = "^[[:space:]]*#[[:space:]]*>>>[[:space:]]*" ENVIRON["SM_MARKER"] "[[:space:]]*$"
        closing = "^[[:space:]]*#[[:space:]]*<<<[[:space:]]*" ENVIRON["SM_MARKER"] "[[:space:]]*$"
      }
      $0 ~ opening { inside = 1; next }
      inside && $0 ~ closing { inside = 0; next }
      inside { next }
      { print }
    ' "$file" >"$tmp"
    write_back "$tmp" "$file"
    squeeze_blank_lines "$file"
    note "stripped ${marker} from ${file#./}"
  done < <(find . -type f -not -path './.git/*' -print0)
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

# True if $1 equals any of the remaining arguments.
contains() {
  local needle=$1 x
  shift
  for x in "$@"; do
    [ "$x" = "$needle" ] && return 0
  done
  return 1
}

ask() {
  local var=$1 prompt=$2 default=$3 reply=''
  if [ -n "${argc_yes:-}" ] || [ ! -t 0 ]; then
    printf -v "$var" '%s' "$default"
    return
  fi
  read -r -p "${prompt} [${default}]: " reply || reply=''
  printf -v "$var" '%s' "${reply:-$default}"
}

# Prints the account `gh` is logged in as, which doubles as the check that the
# GitHub half can run at all. The lookup hits the network, so it runs under a
# timeout: an offline `gh` should cost a few seconds and fall back to a
# local-only scaffold, not hang the run. The warnings go to stderr, so they
# still reach the terminal through the command substitution this is called in.
gh_login() {
  local login=''
  if ! command -v gh >/dev/null 2>&1; then
    warn 'gh is not on PATH; skipping the GitHub setup'
    return 1
  fi
  if ! login=$(timeout 10 gh api user --jq .login 2>/dev/null) || [ -z "$login" ]; then
    warn 'gh is not authenticated, or GitHub is unreachable (try: gh auth login); skipping the GitHub setup'
    return 1
  fi
  printf '%s' "$login"
}

# Creates the active labels from .github/labels.json. --force updates a label
# that already exists, which is what GitHub's own defaults need: a new
# repository ships with a `bug` that says something else.
create_labels() {
  local slug=$1 name color description
  jq -r '.labels[] | [.name, .color, .description // ""] | @tsv' .github/labels.json |
    while IFS=$'\t' read -r name color description; do
      if gh label create "$name" --repo "$slug" --color "$color" --description "$description" --force >/dev/null 2>&1; then
        note "label ${name}"
      else
        warn "could not create the label '${name}'"
      fi
    done
}

# ---------------------------------------------------------------------------

target=${argc_target:-}
[ -f "${TEMPLATE_SOURCE}/flake.nix" ] || die "no template source at ${TEMPLATE_SOURCE}"

if [ -e "$target" ]; then
  [ -d "$target" ] || die "${target} exists and is not a directory"
  [ -z "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ] || die "${target} exists and is not empty"
fi

base=$(basename "$target")

# ask() assigns through printf -v, which shellcheck cannot see; initialise the
# variables it fills so nounset and SC2154 stay honest.
name='' description='' owner='' repo='' author='' year='' visibility=''

# Whether the GitHub half runs at all, settled before anything else: a run
# that cannot do it should say so before it asks about visibility, and long
# before it starts copying files. Without a git repository there is nothing to
# push, so --no-git implies --no-github.
github=1
if [ -n "${argc_no_github:-}" ] || [ -n "${argc_no_git:-}" ]; then
  github=''
fi

login='' default_owner=$TEMPLATE_OWNER
if [ -n "$github" ]; then
  if login=$(gh_login); then
    default_owner=$login
  else
    github=''
  fi
fi

log "Scaffolding ${target} from ${TEMPLATE_OWNER}/${TEMPLATE_REPO}"
ask name 'Project name' "${argc_name:-$base}"
ask description 'One-line description' "${argc_description:-A project built from the harder template}"
ask owner 'GitHub owner' "${argc_owner:-$default_owner}"
ask repo 'GitHub repository' "${argc_repo:-$base}"
if [ -n "$github" ]; then
  ask visibility 'Repository visibility — private, public, internal, or no to skip GitHub' "${argc_visibility:-private}"
  case $visibility in
  private | public | internal) ;;
  n | no | none) github='' ;;
  *) die "unknown visibility '${visibility}' (private, public, internal, or no)" ;;
  esac
fi
ask author 'Copyright holder' "${argc_author:-$(git config user.name 2>/dev/null || echo "$TEMPLATE_AUTHOR")}"
ask year 'Copyright year' "${argc_year:-$(date +%Y)}"

available=()
for module in "$TEMPLATE_SOURCE"/nix/toolchains/*.nix; do
  [ -e "$module" ] || continue
  available+=("$(basename "$module" .nix)")
done
[ ${#available[@]} -gt 0 ] || die 'no toolchain modules found under nix/toolchains/'

toolchains_arg=${argc_toolchain:-}
if [ "${argc_toolchain+given}" != given ]; then
  note "available: ${available[*]}  (comma-separated, or 'none')"
  ask toolchains_arg 'Toolchains' 'none'
fi

toolchains=()
if [ "$toolchains_arg" != 'none' ] && [ -n "$toolchains_arg" ]; then
  IFS=', ' read -r -a toolchains <<<"$toolchains_arg"
fi

for want in ${toolchains[@]+"${toolchains[@]}"}; do
  contains "$want" "${available[@]}" || die "unknown toolchain '$want' (available: ${available[*]})"
done

[ -n "$name" ] || die 'a project name is required'
[ -n "$owner" ] && [ -n "$repo" ] || die 'a GitHub owner and repository are required'

# ---------------------------------------------------------------------------

log 'Copying the template'
mkdir -p "$target"
cp -R --no-preserve=mode,ownership -- "${TEMPLATE_SOURCE}/." "$target/"
cd "$target"

# The scaffolder does not follow the project it creates: the new README comes
# from the template file, and the app, this script, and their import in
# flake.nix all go. The .git only exists when TEMPLATE_SOURCE is a checkout
# rather than a store path — dropping it keeps a development run from
# inheriting the template's history and, worse, its origin remote.
cp template/README.md README.md
rm -rf template nix/app.nix nix/scaffold.sh .git
strip_marker_blocks scaffold

log 'Selecting toolchains'
set_nix_list project.nix toolchains ${toolchains[@]+"${toolchains[@]}"}
if [ ${#toolchains[@]} -eq 0 ]; then
  note 'none — the dev shell will carry only the git hook packages'
else
  note "keeping: ${toolchains[*]}"
fi

for have in "${available[@]}"; do
  contains "$have" ${toolchains[@]+"${toolchains[@]}"} && continue

  strip_marker_blocks "toolchain:${have}"
  rm -f "nix/toolchains/${have}.nix"
  note "removed nix/toolchains/${have}.nix"
done

log 'Rewriting project metadata'
# Nix string literals give `\`, `"` and `${` a meaning, so neutralise all three
# before the description goes into flake.nix.
nix_description=${description//\\/\\\\}
nix_description=${nix_description//\"/\\\"}
nix_description=${nix_description//\$/\\\$}
set_nix_string flake.nix description "$nix_description"

for file in LICENSE CONTRIBUTING.md .github/ISSUE_TEMPLATE/config.yml; do
  [ -f "$file" ] || continue
  replace_literal "$file" "${TEMPLATE_OWNER}/${TEMPLATE_REPO}" "${owner}/${repo}"
  replace_literal "$file" "$TEMPLATE_AUTHOR" "$author"
done
replace_literal LICENSE 'Copyright (c) 2026' "Copyright (c) ${year}"
note "owner ${owner}/${repo}, © ${year} ${author}"

log 'Writing README.md'
replace_literal README.md '{{PROJECT_NAME}}' "$name"
replace_literal README.md '{{PROJECT_DESCRIPTION}}' "$description"

if command -v nix >/dev/null 2>&1; then
  if [ -z "${argc_no_lock:-}" ]; then
    log 'Re-locking the flake'
    nix flake lock || warn 'nix flake lock failed — run it yourself once the tree is committed'
  fi
  if [ -z "${argc_no_format:-}" ]; then
    log 'Formatting'
    nix fmt >/dev/null || warn 'nix fmt failed — run it yourself'
  fi
else
  warn 'nix is not on PATH; skipping the lock and format steps'
fi

if [ -z "${argc_no_git:-}" ]; then
  log 'Initializing git'
  git init -q -b main
  git add -A
  if git commit -q -m 'chore: bootstrap from template' 2>/dev/null; then
    note 'committed: chore: bootstrap from template'
  else
    warn 'the bootstrap commit failed — set git user.name and user.email, then commit yourself'
    github=''
  fi
fi

slug="${owner}/${repo}" err=''
if [ -n "$github" ]; then
  log "Creating github.com/${slug}"
  if gh repo create "$slug" --source=. --"$visibility" --push --description "$description"; then
    note "${visibility}, origin set, main pushed"

    log 'Creating the issue labels'
    create_labels "$slug"
    note 'the labels under "inactive" in .github/labels.json are not created'

    log 'Applying the branch ruleset'
    if err=$(gh api --method POST "repos/${slug}/rulesets" --input .github/rulesets/main.json --silent 2>&1); then
      note 'main now requires a pull request, a green "Nix flake" check, and squash merges'
    else
      warn "the ruleset was rejected: ${err}"
      note "retry with: gh api --method POST repos/${slug}/rulesets --input .github/rulesets/main.json"
    fi
  else
    warn 'gh repo create failed — the project is committed locally; push it yourself'
    github=''
  fi
fi

printf '\n%sDone.%s Next:\n\n' "$BOLD" "$RESET"
printf '  1. Enter it            — %scd %s && nix develop%s\n' "$BOLD" "$target" "$RESET"
if [ -z "$github" ]; then
  printf '  2. Put it on GitHub    — %sgh repo create %s --source=. --private --push%s\n' "$BOLD" "$slug" "$RESET"
  printf '  3. Create the labels   — %sgh label create ... --force%s, from .github/labels.json\n' "$BOLD" "$RESET"
  printf '  4. Protect main        — %sgh api --method POST repos/%s/rulesets --input .github/rulesets/main.json%s\n' "$BOLD" "$slug" "$RESET"
fi
cat <<EOF

Optional repository settings are listed under "Repository settings" in the
template's README (github.com/${TEMPLATE_OWNER}/${TEMPLATE_REPO}). The short
version: set the ANTHROPIC_API_KEY and OPENAI_API_KEY secrets for the agent
workflows, and the CACHIX_CACHE variable for the binary cache.
EOF
