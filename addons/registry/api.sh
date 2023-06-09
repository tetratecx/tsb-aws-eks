# Helper functions to manage twun docker registry (docker registry v2)
#

# Some colors
END_COLOR="\033[0m"
GREENB_COLOR="\033[1;32m"
REDB_COLOR="\033[1;31m"

# Print info messages
#   args:
#     (1) message
function print_info {
  [[ -z "${1}" ]] && print_error "Please provide message as 1st argument" && return 2 || local message="${1}" ;
  echo -e "${GREENB_COLOR}${message}${END_COLOR}" ;
}

# Print error messages
#   args:
#     (1) message
function print_error {
  [[ -z "${1}" ]] && print_error "Please provide message as 1st argument" && return 2 || local message="${1}" ;
  echo -e "${REDB_COLOR}${message}${END_COLOR}" ;
}

# Get registry version
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'registry-admin:registry-admin')
function registry_get_catalog {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="registry-admin:registry-admin" || local basic_auth="${2}" ;

  curl --insecure --location --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/v2/_catalog" ;
}

# Wait for registry api to be ready
#     (1) api url
#     (2) basic auth credentials (optional, default 'registry-admin:registry-admin')
#     (3) timeout in seconds (optional, default '120')
function registry_wait_api_ready {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="registry-admin:registry-admin" || local basic_auth="${2}" ;
  [[ -z "${3}" ]] && local timeout="120" || local timeout="${3}" ;

  local count=0 ;
  echo -n "Waiting for registry rest api to become ready at url '${base_url}': "
  while ! $(registry_get_catalog "${base_url}" "${basic_auth}" &>/dev/null); do
    echo -n "." ; sleep 1 ; count=$((count+1)) ;
    if [[ ${count} -ge ${timeout} ]] ; then print_error "Timeout exceeded while waiting for registry api readiness" ; return 1 ; fi
  done
  echo "DONE" ;
}
