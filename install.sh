#!/bin/bash
#todo: redo the whole thing in an actual language

set -e
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cache_dir="/var/cache/pacman/pkg/"
modules_file="$SCRIPT_DIR/modules"

main () {
  parse_args "$@"
  init 
  load_modules
  get_targets 
  #paru -Cu #update chroot
  run_targets
  log info "Run complete."
  list_failed
  list_reverted
  list_skipped
  #clear
  #print_log
}

parse_args () {
  ARGS_=()
  for arg in "$@"; do
    if [[ "$arg" = "--debug" ]]; then
      DEBUG=true
    elif [[ "$arg" =~ "--config=" ]]; then
      modules_file=${arg:9}
      echo "new modules file $modules_file"
    elif ! [ -z "$arg" ]; then
      ARGS_+=("$arg")
    fi
  done
  ARGS+=( "${ARGS_[@]}" )
}

init () {
  declare -a LOG
  declare -a TARGETS
  declare -a MODULES 
  declare -a SCRIPTS
  declare -a FAILS
  declare -a DEPS
  declare -a CODEPS
  declare -a POSTS
  declare -a RAN
  declare -a FAILED
  declare -a REVERTED
  declare -a SUCCEEDED
  declare -a SKIPPED
  declare -a TARGET_IDS

  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m' # No Color
  cache_files=($cache_dir)
  module=''
}

load_modules () {
  if ! [ -f "$modules_file" ]; then
    log warn "Failed to load module file '${RED}$mod${NC}', file doesn't exist: $file"
    exit
  fi
  readarray -t a < "$modules_file"
  local -i i=-1
  for _line in "${a[@]}"; do
    line=($_line)
    opt="${line[0]}"
    case "$opt" in
      "[module]")
        # start new module
        i+=1
        module_="${line[1]}"
        if [ "${line[2]}" = "disabled" ]; then 
          SKIP+=("true")
          log debug "Skipping module"
        else
          SKIP+=("no")
        fi
        local script_=''
        local deps_=''
        local codeps_=''
        local post_=''
        local revert_=''
        local fail=''
        MODULES+=("$module_")
        log debug "Module #$i: ${GREEN}$module_${NC}"
        ;;
      "[script]")
        script_="${line[@]:1}"
        SCRIPTS+=( "${script_[*]}" )
        log debug "script = $script_"
        ;;
      "[dependencies]")
        deps_+="${line[@]:1}"
        DEPS+=( "${deps_[*]}" )
        log debug "deps = ${deps_[*]}"
        ;;
      "[codependencies]")
        codeps_="${line[@]:1}"
        CODEPS+=( "${codeps_[*]}" )
        log debug "codeps = ${codeps_[*]}"
        ;;
      "[post-script]")
        post_="${line[@]:1}"
        POSTS+=( "${post_[*]}" )
        log debug "post-script = $post_"
        ;;
      "[revert-script]")
        revert_="${line[@]:1}"
        REVERTS+=( "${revert_[*]}" )
        log debug "revert-script = $revert_"
        ;;
      "[fail-script]")
        fails_="${line[@]:1}"
        FAILS+=( "${fails_[*]}" )
        log debug "fail-script = $fails_"
        ;;
      "")
        :
        ;;
      *)
        log warn "Invalid config: $_line"
        exit
        ;;
    esac
  done
  module_=''
}

log () {
  if ! [ -z "$module_" ]; then
    opt=" [${GREEN}$module_${NC}]"
  else
    opt=''
  fi
  case "$1" in 
    info)
      local str="($(date +%T))$opt ${YELLOW}INFO:${NC} "
      str+="$2"
      ;;
    debug)
      local str="($(date +%T))$opt ${YELLOW}DEBUG:${NC} "
      str+="$2"
      ! [ -z $DEBUG ] || str=''
      ;;
    warn)
      local str="($(date +%T))$opt ${RED}WARNING:${NC} "
      str+="$2"
      ;;
    cmd)
      local str="($(date +%T))$opt [${GREEN}$module_${NC}] "
      str+="$2"
      ;;
    *)
      str="$1"
      ;;
    esac
  if ! [ -z "$str" ]; then
    printf "$str\n" 
  fi
  LOG+=("$str")
}

get_targets () {
  if is_empty ${ARGS[@]}; then
    log info "No targets, assuming all."
    ARGS+=(${MODULES[@]})
  fi
  for arg in "${ARGS[@]}"; do
    local -i i=$(module_id "$arg")
    if [ "$i" = "-1" ]; then
      log warn "${RED}$arg${NC} is not a module, ignoring."
    elif [ ${SKIP[$i]} = "true" ]; then
      log debug "${GREEN}$arg${NC} is disabled, skipping."
    else
      TARGETS+=("$arg")
      TARGET_IDS+=($i)
    fi
  done

  if is_empty ${TARGETS[@]}; then
    log warn "No targets, exiting."
    exit
  fi
  log info "Targets: ${GREEN}${TARGETS[*]}${NC}"
}

#TODO: check for dependency cycles
#TODO: look for suitable run order
run_targets () {
  for i in ${TARGET_IDS[@]}; do
    if ! check_dependencies "$i"; then
      log warn "Failed dependency check for ${GREEN}${MODULES[$i]}${NC}, skipping."
      SKIPPED+=( "${MODULES[$i]}" )
      continue
    fi
    run_module "$i" || fail_module "$i"
  done
}

fail_module () {
  if ! [ -z "${FAILS[$i]}" ]; then
    log warn "Running fail script."
    run_script "${FAILS[$i]}"
  fi
  check_codependencies "$i"
}

install_from_cache () {
  newFile=$(find "$cache_dir" -name "$1*.pkg.tar.zst" -print0 | xargs -r -0 ls -1 -t | head -1)
  if is_element_of $old_cache $newFile; then
    echo "newest file as in there when we started"
    return 1
  elif is_element_of $old_cache $cachedFile; then
    cachedFile=$(find "$cache_dir" -name "$1*.pkg.tar.zst" -print0 | xargs -r -0 ls -1 -t | head -2 | tail -1)
    echo "paru -U "$file" --noconfirm"
  fi
}


run_script () {
  script="$1"
  log info "Running script: $script"
  if test -f "$script"; then
    /bin/bash -e "$script" || return 1
  else
    eval "$script" || return 1
  fi
}

run_module () {
  local id=$1
  local module_="${MODULES[$1]}"
  local failed=0
  printf "\n"
  log info "Running module ${GREEN}${MODULES[$1]}${NC}."
  run_script "${SCRIPTS[$i]}" || failed="1"
  if [ "$failed" -eq "1" ]; then
    FAILED+=( "${MODULES[$id]}" )
    log warn "${RED}${MODULES[$1]}${NC} failed."
    return 1
  else
    SUCCEEDED+=( "${MODULES[id]}" )
    log info "Module ${GREEN}${MODULES[$1]}${NC} ran successfully."
  fi
  RUN+=( "${MODULES[$id]}" )
}

revert () {
  local id=$1
  local failed=0
  run_script "${REVERTS[$id]}" || failed="1"
  if [ "$failed" -eq "1" ]; then
    log warn "Failed to revert ${RED}${MODULES[$1]}${NC}, quitting."
    return 1
  else
    REVERTED+=( "${MODULES[$id]}" )
    log info "Module ${GREEN}${MODULES[$1]}${NC} reverted successfully."
  fi
#  eval 'paru -U "$1"_cache'
}

list_failed() {
  local arr=()
  for i in "${TARGET_IDS[@]}"; do
    local name=${MODULES[$i]}
    if ! is_element_of FAILED $name ; then
      continue
    fi
    if is_empty ${arr[@]}; then
      arr+=("${RED}$name${NC}")
    else
      arr+=(", ${RED}$name${NC}")
    fi
  done
  is_empty ${arr[@]} || log warn "Failed targets: ${arr[*]}"
}

list_reverted() {
  local arr=()
  for i in "${TARGET_IDS[@]}"; do
    local name=${MODULES[$i]}
    if ! is_element_of REVERTED $name ; then
      continue
    fi
    if is_empty ${arr[@]}; then
      arr+=("${YELLOW}$name${NC}")
    else
      arr+=(", ${YELLOW}$name${NC}")
    fi
  done
  is_empty ${arr[@]} || log warn "Reverted targets: ${arr[*]}"
}

list_skipped() {
  local arr=()
  for i in "${TARGET_IDS[@]}"; do
    local name=${MODULES[$i]}
    if ! is_element_of SKIPPED $name ; then
      continue
    fi
    if is_empty ${arr[@]}; then
      arr+=("${YELLOW}$name${NC}")
    else
      arr+=(", ${YELLOW}$name${NC}")
    fi
  done
  is_empty ${arr[@]} || log warn "Skipped targets: ${arr[*]}"
}

print_log () {
  for str in "${LOG[@]}"; do
    if ! [ -z "$str" ]; then
      printf "$str\n" 
    fi
  done
}


# A is dependent on B if A --> B.
# before doing A, make sure each B succeeded.
check_dependencies () {
  local i="$1"
  local str="${DEPS[$i]}"
  local deps=($str)
  log debug "Dependencies for ${GREEN}${MODULES[$i]}${NC}: ${GREEN}${DEPS[$i]}${NC}"
  for dep in "${deps[@]}"; do    
    if ! is_element_of TARGETS $dep; then
      log debug "$dep isn't a target, continuing"
      continue
    fi
    if ! is_element_of SUCCEEDED $dep; then
      log warn "${GREEN}${MODULES[$i]}${NC} is missing dependency ${RED}$dep${NC}."
      return 1
    fi
  done
  log debug "Dependency check for module ${MODULES[$i]} passed."
}

# A is codependent on B if A <-- B.
# after failing A, revert every B.
check_codependencies () {
  local i="$1"
  local str="${CODEPS[$i]}"
  local deps=($str)
  log debug "Codependencies for ${RED}${MODULES[$i]}${NC}: ${GREEN}${CODEPS[$i]}${NC}"
  for dep in "${deps[@]}"; do    
    if ! is_element_of TARGETS $dep; then
      log debug "$dep isn't a target, continuing"
      continue
    fi
    if is_element_of SUCCEEDED $dep; then
      log warn "${GREEN}$dep${NC} is a codependency of ${RED}${MODULES[$i]}${NC} and will be reverted."
      local -i id=$(module_id "$dep")
      revert "$id"
    fi
  done
  log debug "Codependency check for module ${MODULES[$i]} passed."
}

# I really wish I could use bash's associative arrays (id = module_id[name]).
# They seem to be really finnicky when setting/getting with variables.
module_id () {
  local -i i=-1
  local -i id=-1
  for name in "${MODULES[@]}"; do
    i+=1
    if [ "$1" = "$name" ]; then
      id=$i
      break
    fi
  done
  echo $id
}

is_empty () {
  arg=("$@")

  [ ${#arg[@]} -eq 0 ] || return 1
}

is_element_of () {
  elem="$2"
  declare -n arr="$1"
  if [[ " ${arr[*]} " =~ " $2 " ]]; then
    return 0
  else
    return 1
  fi
}

main "$@"
