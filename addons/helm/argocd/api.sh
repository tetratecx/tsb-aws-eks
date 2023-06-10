# Helper functions to manage argocd (a pull based gitops solution)
#

# Get argocd version
#   args:
#     (1) api url
function argocd_get_version {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;

  curl --insecure --location --fail --silent --request GET \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/version" ;
}

# Wait for argocd api to be ready
#     (1) api url
#     (3) timeout in seconds (optional, default '120')
function argocd_wait_api_ready {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local timeout="120" || local timeout="${2}" ;

  local count=0 ;
  echo -n "Waiting for argocd rest api to become ready at url '${base_url}': "
  while ! $(argocd_get_version "${base_url}" "${basic_auth}" &>/dev/null); do
    echo -n "." ; sleep 1 ; count=$((count+1)) ;
    if [[ ${count} -ge ${timeout} ]] ; then print_error "Timeout exceeded while waiting for argocd api readiness" ; return 1 ; fi
  done
  echo "DONE" ;
}
