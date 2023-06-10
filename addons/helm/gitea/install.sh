# Helper functions to start, upgrade and remove gitea (a lightweight git server)
#

GITEA_ADMIN_PASSWORD="gitea-admin"
GITEA_ADMIN_USER="gitea-admin"
GITEA_HTTP_PORT=3000
GITEA_NAMESPACE="gitea"

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
  helm repo update gitea-charts ;

  if $(helm status gitea --kubeconfig "${kubeconfig}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade gitea gitea-charts/gitea \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set gitea.admin.email=${admin_user}@local.domain \
      --set gitea.admin.password=${admin_password} \
      --set gitea.admin.username=${admin_user} \
      --set service.http.type=LoadBalancer ;
    print_info "Upgraded helm chart for gitea" ;
  else
    helm install gitea gitea-charts/gitea \
      --create-namespace \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set gitea.admin.email=${admin_user}@local.domain \
      --set gitea.admin.password=${admin_password} \
      --set gitea.admin.username=${admin_user} \
      --set service.http.type=LoadBalancer ;
    print_info "Installed helm chart for gitea" ;
  fi
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

  local gitea_ip=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" gitea-http -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
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
#     (3) admin user (optional, default 'gitea-admin')
#     (4) admin password (optional, default 'gitea-admin')
function gitea_get_http_url_with_credentials {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${GITEA_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password="${GITEA_ADMIN_PASSWORD}" || local admin_password="${4}" ;

  local gitea_ip=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" gitea-http -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${gitea_ip}" ]]; then
    print_error "Service 'gitea-http' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${admin_user}:${admin_password}@${gitea_ip}:${GITEA_HTTP_PORT}" ;
}
