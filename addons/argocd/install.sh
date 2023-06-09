# Helper functions to start, upgrade and remove argocd (a pull based gitops solution)
#

# Some colors
END_COLOR="\033[0m"
GREENB_COLOR="\033[1;32m"
REDB_COLOR="\033[1;31m"

# ArgoCD uses htpasswd style, which uses a hashed password
# Use to regenerate: htpasswd -nbBC 10 "" argocd-admin | tr -d ':\n' | sed 's/$2y/$2a/' ; echo
#
#   default: admin:$2a$10$XRFNO/K5cHtptZl77vCOUO0/P4hMflV/wJaBmFtpTsjlwN0iQW7B6
#
ARGOCD_ADMIN_PASSWORD='$2a$10$XRFNO/K5cHtptZl77vCOUO0/P4hMflV/wJaBmFtpTsjlwN0iQW7B6'
ARGOCD_ADMIN_USER="admin"
ARGOCD_HTTP_PORT=80
ARGOCD_NAMESPACE="argocd"

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

# Deploy argocd server in kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'argocd')
#     (3) admin user (optional, default 'admin')
#     (4) admin password (optional, default 'argocd-admin')
function argocd_deploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${ARGOCD_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${ARGOCD_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password="${ARGOCD_ADMIN_PASSWORD}" || local admin_password="${4}" ;

  helm repo add argocd-charts https://argoproj.github.io/argo-helm ;
  helm repo update ;

  if $(helm status argocd --kubeconfig "${kubeconfig}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade argocd argocd-charts/argo-cd \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set configs.secret.argocdServerAdminPassword="${admin_password}" \
      --set configs.secret.argocdServerAdminPasswordMtime="2023-01-01T00:00:00Z" \
      --set server.service.type=LoadBalancer ;
    print_info "Upgraded helm chart for argocd" ;
  else
    helm install argocd argocd-charts/argo-cd \
      --create-namespace \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set configs.secret.argocdServerAdminPassword="${admin_password}" \
      --set configs.secret.argocdServerAdminPasswordMtime="2023-01-01T00:00:00Z" \
      --set server.service.type=LoadBalancer ;
    print_info "Installed helm chart for argocd" ;
  fi
}

# Undeploy argocd from kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'argocd')
function argocd_undeploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${ARGOCD_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall argocd \
    --kubeconfig "${kubeconfig}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for argocd" ;
}

# Get argocd server http url
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'argocd')
function argocd_get_http_url {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${ARGOCD_NAMESPACE}" || local namespace="${2}" ;

  local argocd_ip=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${argocd_ip}" ]]; then
    print_error "Service 'argocd-server' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${argocd_ip}:${ARGOCD_HTTP_PORT}" ;
}

# Get argocd server http url with credentials
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'argocd')
#     (3) admin user (optional, default 'admin')
#     (4) admin password (optional, default 'argocd-admin')
function argocd_get_http_url_with_credentials {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${ARGOCD_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${ARGOCD_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password="${ARGOCD_ADMIN_PASSWORD}" || local admin_password="${4}" ;

  local argocd_ip=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${argocd_ip}" ]]; then
    print_error "Service 'argocd-server' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${admin_user}:${admin_password}@${argocd_ip}:${ARGOCD_HTTP_PORT}" ;
}
