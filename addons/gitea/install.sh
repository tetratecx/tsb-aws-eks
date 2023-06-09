# Helper functions to start, stop and remove gitea (a lightweight git server)
#

# Some colors
END_COLOR="\033[0m"
GREENB_COLOR="\033[1;32m"
REDB_COLOR="\033[1;31m"

GITEA_ADMIN_PASSWORD="gitea-admin"
GITEA_ADMIN_USER="gitea-admin"
GITEA_HTTP_PORT=3000
GITEA_NAMESPACE="gitea"

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

# Deploy gitea server in kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'gitea')
#     (3) admin user (optional, default 'gitea-admin')
#     (4) admin password (optional, default 'gitea-admin')
function gitea_deploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${GITEA_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password="${GITEA_ADMIN_PASSWORD}" || local admin_password="${4}" ;

  helm repo add gitea-charts https://dl.gitea.io/charts/ ;
  helm repo update ;
  helm install gitea gitea-charts/gitea \
    --create-namespace \
    --kubeconfig "${kubeconfig}" \
    --namespace "${namespace}" \
    --set gitea.admin.email=${admin_user}@local.domain \
    --set gitea.admin.password=${admin_password} \
    --set gitea.admin.username=${admin_user} \
    --set service.http.type=LoadBalancer ;
  print_info "Installed helm chart for gitea" ;
}

# Undeploy gitea from kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'gitea')
function gitea_undeploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall gitea \
    --kubeconfig "${kubeconfig}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for gitea" ;
}

# Get gitea server http url
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'gitea')
function gitea_get_http_url {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;

  local gitea_ip=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" gitea-http --template "{{(index .status.loadBalancer.ingress 0 ).hostname}}" 2>/dev/null) ;
  if [[ -z "${gitea_ip}" ]]; then
    print_error "Service 'gitea-http' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${gitea_ip}:${GITEA_HTTP_PORT}" ;
}

# Get gitea server http url with credentials
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'gitea')
#     (3) admin user (optional, default 'gitea_admin')
#     (4) admin password (optional, default 'gitea-admin')
function gitea_get_http_url_with_credentials {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${GITEA_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password="${GITEA_ADMIN_PASSWORD}" || local admin_password="${4}" ;

  local gitea_ip=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" gitea-http --template "{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}" 2>/dev/null) ;
  if [[ -z "${gitea_ip}" ]]; then
    print_error "Service 'gitea-http' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${admin_user}:${admin_password}@${gitea_ip}:${GITEA_HTTP_PORT}" ;
}
