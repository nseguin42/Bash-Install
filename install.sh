#!/bin/bash
set -e
init () {
  ARGS=("$@")
  LOG=()
  MODULES=(
  "llvm"
  "mesa"
  "lib32_llvm"
  "lib32_mesa"
  "llvm_rocm"
  "rocm"
  )

  for var in "${MODULES[@]}"; do
    eval "$var"_failed=false;
    eval "$var"_succeeded=false;
  done

  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m' # No Color
  cacheDir="/var/cache/pacman/pkg/"
}

main () {
  init "$@"
  paru -Cu #update chroot
  get_targets 
  install_targets
  update_dependents
  clear
  log info "Install complete."
  print_log
}


log () {
  case "$1" in 
    cmd)
      local str="[$(date +%T)] "
      str+="$2"
      ;;
    info)
      local str="[$(date +%T)] ${YELLOW}INFO:${NC} "
      str+="$2"
      ;;
    warn)
      local str="[$(date +%T)] ${RED}WARNING:${NC} "
      str+="$2"
      ;;
    *)
      str+="$1"
      ;;
    esac
  printf "$str\n"
  LOG+=("$str")
}

# defaults to "all modules"
get_targets () {
  TARGETS=()
  if is_empty ${ARGS[@]}; then
    log info "No arguments, assuming all: ${GREEN}${MODULES[*]}${NC}."
    TARGETS=("${MODULES[@]}")
    return;
  fi

  for var in "${ARGS[@]}"; do
    if $(is_module "$var"); then
      TARGETS+=("$var")
    else
      log warn "$var is not a module"
    fi
  done

  if is_empty ${TARGETS[@]}; then
    log warn "No targets. Stopping."
    exit
  else
    log info "Targets: ${TARGETS[*]}"
  fi
}

#TODO: check for dependency cycles
install_targets () {
  for var in ${TARGETS[@]}; do
    check_dependencies "$var" || return
    install "$var" || revert_codependencies "$var"
  done
}

# only consider dependencies which are targets
get_dependencies () {
  local deps=()
  if ! is_target $1; then
    return
  fi
  case "$1" in
    mesa)
      deps+=("llvm")
      ;;
    lib32_llvm)
      deps+=("llvm")
      ;;
    lib32_mesa)
      deps+=("lib32_llvm")
      ;;
    llvm_rocm)
      deps+=("llvm")
      ;;
    rocm)
      deps+=("llvm_rocm")
      ;;
    *)
      :
      ;;
  esac
  [ "$deps" ] || echo a && eval "$1"_dependencies="$deps"
}

# TODO: make this list programmatically
get_codependencies () {
  local deps=()
  if ! is_target $1; then
    return
  fi
  case "$1" in
    mesa)
      deps+=("llvm")
      ;;
    lib32_mesa)
      deps+=("lib32_llvm")
      ;;
    rocm)
      deps+=("llvm_rocm")
      ;;
    *)
      :
      ;;
  esac
  [ -z "$deps" ] || eval "$1"_codependencies="$deps"
}

# assumes this file will still be available after upgrading
# in case a rollback is needed
cache_file () {
  eval "$1"_cache="$(ls $cacheDir | grep "$1")"
}

install () {
  log info "Installing module ${GREEN}$1${NC}."
  local arr=()
  case "$1" in
    llvm)
      arr+=('paru -S aur/llvm-minimal-git aur/llvm-libs-minimal-git --chroot --noconfirm --needed')
      ;;
    mesa)
      arr+=('cd ~/aur/mesa-git')
      arr+=('paru -U --chroot --noconfirm --install')
      ;;
    lib32_llvm)
      arr+=('paru -S aur/lib32-llvm-minimal-git aur/lib32-llvm-libs-minimal-git --chroot --noconfirm --needed')
      ;;
    lib32_mesa)
      arr+=('cd ~/aur/lib32-mesa-git')
      arr+=('paru -U --chroot --noconfirm --install || lib32_mesa_failed=true')
      ;;
    llvm_rocm)
      arr+=('paru -S aur/rocm-llvm --chroot --noconfirm --needed || rocm_llvm_failed=true')
      ;;
    rocm)
      arr+=('paru -S aur/rocm-opencl-runtime --chroot --noconfirm --rebuild')
      ;;
    *)
      :
      ;;
  esac

  local failed
  for str in "${arr[@]}"; do
    eval "log cmd \"$str\""
    (eval "$str") || (break && eval failed=true)
  done

  if $failed; then
    eval "$1"_failed=true
    log warn "$1 failed to install!"
  else
    eval "$1"_succeeded=true
    log info "$1 installed successfully."
  fi
}

revert () {
  log warn "$Reverting $1."
  eval 'paru -U "$1"_cache'
}

list_failed() {
  for var in "${TARGETS[@]}"; do
    local arr=();
    local str="$var_failed"
    local failed=${!str}
    $failed || continue;
    if is_empty ${arr[@]}; then
      failedTargets+=("$var")
    else
      failedTargets+=(", $var")
    fi
  done
  is_empty ${arr[@]} || log warn "Failed targets: ${failedTargets[*]}"
}

update_dependents () {
  log info "Updating dependents..."
  ffmpeg -version >/dev/null || paru -S ffmpeg-amd-full --rebuild --noconfirm 
  mpv -v >/dev/null || paru -S mpv-amd-full-git --rebuild --noconfirm
}

print_log() {
  for var in "${LOG[@]}"; do
    printf "$var\n"
  done
}


# A is dependent on B if A --> B.
# before doing A, make sure each B succeeded.
check_dependencies () {
  get_dependencies "$1"
  local str="$1"_dependencies
  local deps="${!str}"
  for dep in "${deps[@]}"; do
    eval local succeeded="$dep"_succeeded
    is_target $dep  || return 0
    ${!succeeded} || return 1
  done
}

# A is codependent on B if A <-- B.
# after failing A, revert every B.
check_codependencies () {
  local str="$1"_codependencies
  local deps="${!str}"
  for dep in "${deps[@]}"; do
    eval local succeeded="$dep"_succeeded
    is_target $dep && ${!succeeded} || continue
    info log "Reverting $dep because it is a codependency of $1."
    revert $dep
  done
}

is_module () {
  if [[ " ${MODULES[*]} " =~ " $1 " ]]; then
    return 0
  else
    return 1
  fi
}

is_target () {
  if [[ " ${TARGETS[*]} " =~ " $1 " ]]; then
    return 0
  else
    return 1
  fi
}

is_empty () {
  arg=("$@")
  [ ${#arg[@]} -eq 0 ] || return 1
}

main "$@"
