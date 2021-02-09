#!/usr/bin/env bash

set -e

setup_echo_colours() {
  # Exit the script on any error
  set -e

  # shellcheck disable=SC2034
  if [ "${MONOCHROME}" = true ]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BLUE2=''
    DGREY=''
    NC='' # No Colour
  else 
    RED='\033[1;31m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;34m'
    BLUE2='\033[1;34m'
    DGREY='\e[90m'
    NC='\033[0m' # No Colour
  fi
}

debug_value() {
  local name="$1"; shift
  local value="$1"; shift
  
  if [ "${IS_DEBUG}" = true ]; then
    echo -e "${DGREY}DEBUG ${name}: ${value}${NC}"
  fi
}

debug() {
  local str="$1"; shift
  
  if [ "${IS_DEBUG}" = true ]; then
    echo -e "${DGREY}DEBUG ${str}${NC}"
  fi
}

create_ssh_key_pair() {
  local github_uname="$1"; shift

  local github_keys_dir="${HOME}/.ssh/github_keys"

  local key_file="${github_keys_dir}/id_rsa_${github_uname}"

  if [ ! -f "${key_file}" ]; then
    echo -e "${YELLOW}Creating ssh key pair for github user" \
      "${BLUE}${github_uname}${NC}"

    ssh-keygen \
      -t rsa \
      -b 4096 \
      -f "${key_file}"

  else
    echo -e "${GREEN}SSH key pair for github user" \
      "${BLUE}${github_uname}${GREEN} exists${NC}"
  fi

  found_key=false

  # Loop over curl https://github.com/<username>.keys
  # and check that our public key is in there
  echo -e "${GREEN}Checking if a public key for repo" \
    "${BLUE}${github_uname}${GREEN} matches ours${NC}"
  while read -r github_key; do
    echo
    # Echo the first and last 10 chars of the key
    echo -e "  ${GREEN}Testing key" \
      "${BLUE}${github_key:0:15}...${github_key:(-15)}"

    local private_key_file="${github_keys_dir}/id_rsa_${github_uname}"
    local public_key_file="${private_key_file}.pub"

    if grep --silent --fixed-strings "${github_key}" "${public_key_file}"; then
      found_key=true
    fi

  done <<<"$(curl --silent "https://github.com/${github_uname}.keys")"

  echo

  if [ "${found_key}" = false ]; then
    echo -e "${RED}Error:${NC} No SSH key found for user" \
      "${BLUE}${github_uname}${NC}"
    echo
    echo -e "${GREEN}You need to add ssh key" \
      "${BLUE}${public_key_file}${NC}"
    echo -e "${GREEN}to the profile of github user ${BLUE}${github_uname}${NC}"
    echo -e "--------------------------------------------------------"
    cat "${public_key_file}"
    echo -e "--------------------------------------------------------"
    exit 1
  fi

  # Now make sure we have ssh config for the new key
  ensure_ssh_config_exists
}

ensure_binary_exists() {
  local package_name="$1"; shift

  if ! pacman --query "${package_name}" > /dev/null; then
    echo -e "${GREEN}${package_name} cannot be found," \
      "it will now be installed${NC}"
    echo -e "${GREEN}You may need to enter your password for" \
      "sudo access${NC}"
    sudo pacman --sync "${package_name}"
  fi
}

ensure_git_dir_exists() {
  mkdir -p "${git_repo_dir}"
}

ensure_dev_setup_repo_exists() {

  if [ ! -d "${dev_setup_dir}" ]; then
    echo -e "${GREEN}Cloning ${BLUE}${dev_setup_repo_name}" \
      "repo to ${BLUE}${dev_setup_dir}${NC}"

    git \
      clone \
      "github.com-${github_uname}:${github_uname}/${dev_setup_repo_name}.git" \
      "${dev_setup_dir}"
  fi
}

ensure_ssh_config_exists() {
  if [ -f "${ssh_config_file}" ]; then
    if grep \
      --silent \
      --fixed-strings \
      "${github_uname}" \
      "${ssh_config_file}"; then

      echo -e "${GREEN}Found SSH config entry for ${BLUE}${github_uname}${NC}"
    else
      echo -e "${GREEN}SSH config entry not found for ${BLUE}${github_uname}${NC}"
      output_ssh_config_entry
    fi
  else
    echo -e "${GREEN}SSH config file ${BLUE}${ssh_config_file}${GREEN}not" \
      "found for ${BLUE}${github_uname}${NC}"
    output_ssh_config_entry
  fi
}

output_ssh_config_entry() {
  echo -e "${GREEN}Adding entry for ${BLUE}${github_uname}${GREEN} to" \
    "${BLUE}${ssh_config_file}${GREEN} not found for ${BLUE}${github_uname}${NC}"
  {
    echo 
    echo "Host github.com-${github_uname}"
    echo "  HostName github.com"
    echo "  User git"
    echo "  PreferredAuthentications publickey"
    echo "  IdentityFile ${private_key_file}"
  } >> "${ssh_config_file}"
}

main() {
  local IS_DEBUG=false

  local github_uname="thebigtoad"
  local git_repo_dir="${HOME}/git_work"
  local dev_setup_repo_name="dev-setup"
  local dev_setup_dir="${git_repo_dir}/${github_uname}/${dev_setup_repo_name}"
  local dev_setup_script="${dev_setup_dir}/run.sh"
  local ssh_config_file="${HOME}/.ssh/config"

  setup_echo_colours

  mkdir -p "${HOME}/.ssh/github_keys"

  if ! command -v ssh-keygen > /dev/null; then
    echo -e "${RED}Error${NC}: ssh-keygen is not installed"
    exit 1
  fi

  # Make sure we have a ssh key pair and that the public key is in
  # Github
  create_ssh_key_pair "${github_uname}"

  # Make sure we have the dev-setup repo
  ensure_dev_setup_repo_exists

  echo 
  echo -e "${GREEN}Running script ${BLUE}${dev_setup_script}${NC}"
  echo 
  pushd "${dev_setup_dir}" > /dev/null
  # Now run the script in the dev-setup repo
  # Pass through any args e.g to use ansible tags
  # shellcheck source=/dev/null
  source "${dev_setup_script}" "$@"
  popd > /dev/null
}

main "$@"
