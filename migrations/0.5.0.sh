#!/usr/bin/env bash
# 0.5.0: monomono is renamed nomimono and moves to github.com/OpenRelationship/nomimono.
#   packages/monomono -> packages/nomimono (git mv for a submodule or tracked copy, mv for an untracked one);
#   the buck2 cell @monomono// -> @nomimono// and its .buckconfig line; the `# monomono:toolchain` marker;
#   the justfile import; mono.toml's [monomono] section, path and repo; the submodule url; the telemetry
#   names monomono.* -> nomimono.*; and the package's name in AGENTS.md, CLAUDE.md and .agents/.
# Never touches submodules (any gitlink, and submodules/), the package itself, buck-out or vendored trees.
# Idempotent: every rewrite only matches the old name. Prints each file it changed.
set -euo pipefail
cd "$MONO_ROOT"

OLD=monomono
NEW=nomimono
NEW_URL=https://github.com/OpenRelationship/nomimono
old_dir=packages/$OLD
new_dir=packages/$NEW
say() { echo "  $*"; }

in_git=false
if top=$(git rev-parse --show-toplevel 2>/dev/null) && [[ $(cd "$top" && pwd -P) == "$(pwd -P)" ]]; then in_git=true; fi

# --- 1. the folder ---------------------------------------------------------------------------------------------
if [[ -d $old_dir && ! -L $old_dir ]]; then
  [[ ! -e $new_dir ]] || { echo "  both $old_dir and $new_dir exist; move one aside and re-run just mono migrate" >&2; exit 1; }
  kind=untracked
  if $in_git; then
    entry=$(git ls-files --stage -- "$old_dir" | awk 'NR == 1 { print $1 }')
    if [[ $entry == 160000 ]]; then kind=submodule; elif [[ -n $entry ]]; then kind=tracked; fi
  fi
  case $kind in
    submodule|tracked) git mv "$old_dir" "$new_dir" ;;
    untracked) mv "$old_dir" "$new_dir" ;;
  esac
  say "moved $old_dir -> $new_dir ($kind)"
else
  say "$new_dir already in place"
fi

# the submodule entry: url to the new home (the old one redirects, but say where it lives now)
if $in_git && [[ -f .gitmodules ]]; then
  name=$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null |
    awk -v p="$new_dir" '$2 == p { sub(/^submodule\./, "", $1); sub(/\.path$/, "", $1); print $1; exit }')
  if [[ -n $name ]]; then
    url=$(git config -f .gitmodules "submodule.$name.url" || true)
    if [[ $url == *shinyobjectz/$OLD* ]]; then
      git config -f .gitmodules "submodule.$name.url" "$NEW_URL"
      git submodule sync -q -- "$new_dir" 2>/dev/null || true
      say "rewrote .gitmodules: submodule \"$name\" url -> $NEW_URL"
    fi
    git add .gitmodules
  fi
fi
if [[ -d $new_dir/.git || -f $new_dir/.git ]]; then
  origin=$(git -C "$new_dir" remote get-url origin 2>/dev/null || true)
  if [[ $origin == *shinyobjectz/$OLD* ]]; then git -C "$new_dir" remote set-url origin "$NEW_URL"; say "$new_dir origin -> $NEW_URL"; fi
fi

# --- 2. text rewrites in the consumer's own files ------------------------------------------------------------
excluded() {
  case "$1" in
    .git/*|.gitmodules|buck-out/*|submodules/*|"$new_dir"/*|"$old_dir"/*|*/node_modules/*|node_modules/*) return 0 ;;
    packages/*/_build/*|packages/*/deps/*|packages/*/.venv/*|packages/*/target/*|*/vendor/*|vendor/*|*/third_party/*|third_party/*) return 0 ;;
  esac
  return 1
}
list_files() {
  if $in_git; then
    # regular tracked files only (a submodule is a gitlink, not a file); plus the per-machine buckconfig
    git ls-files -s | awk '$1 != "160000" { sub(/^[^\t]*\t/, ""); print }'
    local f; for f in .buckconfig.local mono.toml justfile .buckconfig; do [[ ! -f $f ]] || echo "$f"; done
  else
    find . \( -name .git -o -name buck-out -o -name submodules -o -name node_modules \) -prune -o -type f -print | sed 's#^\./##'
  fi
}
is_doc() {
  case "$1" in
    AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md|.agents/*) return 0 ;;
  esac
  return 1
}

changed=0
rewritten=()
while IFS= read -r f; do
  [[ -n $f && -f $f && ! -L $f ]] || continue
  ! excluded "$f" || continue
  grep -qI "$OLD" "$f" 2>/dev/null || continue
  exprs=(
    -e "s#\[$OLD\]\(https://github\.com/shinyobjectz/$OLD#[$NEW]($NEW_URL#g"
    -e "s#https://github\.com/shinyobjectz/$OLD#$NEW_URL#g"
    -e "s#git@github\.com:shinyobjectz/$OLD#git@github.com:OpenRelationship/$NEW#g"
    -e "s#raw\.githubusercontent\.com/shinyobjectz/$OLD#raw.githubusercontent.com/OpenRelationship/$NEW#g"
    -e "s#packages/$OLD#packages/$NEW#g"
    -e "s#$OLD//#$NEW//#g"
    -e "s#$OLD:toolchain#$NEW:toolchain#g"
    -e "s#$OLD\.(feature|scenarios|scenario|steps|step|outcome|undefined|unclosed|run|kind|keyword|passed|failed)([^a-z_]|\$)#$NEW.\1\2#g"
  )
  case "$f" in
    .buckconfig|.buckconfig.local|*/.buckconfig) exprs+=(-e "s#^([[:space:]]*)$OLD([[:space:]]*=)#\1$NEW\2#") ;;
    mono.toml) exprs+=(-e "1s|^# $OLD manifest\. (.just mono update. rewrites )\[$OLD\]|# $NEW manifest. \1[$NEW]|") ;;
  esac
  if is_doc "$f"; then exprs+=(-e "s#$OLD#$NEW#g"); fi
  before=$(cksum <"$f")
  sed -E -i.mono-bak "${exprs[@]}" "$f" && rm -f "$f.mono-bak"
  if [[ $(cksum <"$f") != "$before" ]]; then
    say "rewrote $f"
    rewritten+=("$f")
    changed=$((changed + 1))
  fi
done < <(list_files)
say "$changed file(s) rewritten"

# --- 3. mono.toml: the section is [nomimono] -----------------------------------------------------------------
if [[ -f mono.toml ]]; then
  if grep -qx "\[$OLD\]" mono.toml && ! grep -qx "\[$NEW\]" mono.toml; then
    sed -i.mono-bak "s/^\[$OLD\]\$/[$NEW]/" mono.toml && rm -f mono.toml.mono-bak
    say "mono.toml: [$OLD] -> [$NEW]"
  fi
  # The 0.4 updater running this migration reads [monomono] path and packages/monomono after it returns; leave it
  # a stub and a link, which the first 0.5 script it calls (its sync) removes (scripts/lib.sh mono_finish_rename).
  if [[ ${MONO_SECTION:-} != "$NEW" ]]; then
    if [[ -n ${MONO_TO:-} ]]; then
      awk -v s="[$NEW]" -v v="$MONO_TO" '/^\[/ { insec = ($0 == s) } insec && $1 == "version" { print "version = \"" v "\""; next } { print }' mono.toml >mono.toml.tmp && mv mono.toml.tmp mono.toml
    fi
    grep -qx "\[$OLD\]" mono.toml || printf '\n[%s]\npath = "%s"\n' "$OLD" "$new_dir" >>mono.toml
    [[ -e $old_dir || -L $old_dir ]] || ln -s "$NEW" "$old_dir"
  fi
fi

if $in_git; then
  # the package path only when git already tracks it (a submodule or a committed copy), never an untracked folder
  [[ -z $(git ls-files -- "$new_dir" | head -n 1) ]] || git add -A -- "$new_dir"
  git add -- mono.toml ${rewritten[@]+"${rewritten[@]}"} 2>/dev/null || true
fi
say "renamed to $NEW; run just mono sync, then just check, and commit"
