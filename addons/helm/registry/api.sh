# Helper functions to manage twun docker registry (docker registry v2)
#

# Get registry version
#   args:
#     (1) api url
function registry_get_catalog {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_api_url="${1}" ;

  curl --insecure --location --fail --silent --request GET \
    --header 'Content-Type: application/json' \
    --url "${base_api_url}/v2/_catalog" ;
}

# Wait for registry api to be ready
#     (1) api url
#     (2) timeout in seconds (optional, default '120')
function registry_wait_api_ready {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_api_url="${1}" ;
  [[ -z "${2}" ]] && local timeout="120" || local timeout="${2}" ;

  local count=0 ;
  echo -n "Waiting for registry rest api to become ready at url '${base_api_url}': "

  while ! $(registry_get_catalog "${base_api_url}" &>/dev/null); do
    echo -n "." ; sleep 1 ; count=$((count+1)) ;
    if [[ ${count} -ge ${timeout} ]] ; then print_error "Timeout exceeded while waiting for registry api readiness" ; return 1 ; fi
  done
  echo "DONE" ;
}

# Check if registry has image
#     (1) api url
#     (2) image name
#     (3) image tag
function registry_has_image {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_api_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide image name as 2nd argument" && return 2 || local image_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide image tag as 3rd argument" && return 2 || local image_tag="${3}" ;

  curl --insecure --location --fail --silent --request GET \
    --header 'Content-Type: application/json' \
    --url "${base_api_url}/v2/${image_name}/tags/list" | grep "${image_tag}" &>/dev/null ;
}

# Check if registry has image
#     (1) registry endpoint
function registry_check_configured_as_insecure {
  [[ -z "${1}" ]] && print_error "Please provide registry endpoint as 1st argument" && return 2 || local registry_endpoint="${1}" ;
  
  while ! $(cat /etc/docker/daemon.json | grep ${registry_endpoint} &>/dev/null); do
    print_warning "Insecure registry '${registry_endpoint}' not configured" ;
    print_warning "Please do so manually and restart docker with 'sudo systemctl restart docker'" ;
    read -p "Press enter to continue" ;
    sudo systemctl restart docker ; 
  done

  print_info "Insecure registry configured" ;
}
