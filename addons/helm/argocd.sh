# Helper functions to manage argocd (a pull based gitops solution)
#

# ArgoCD uses htpasswd style, which uses a hashed password
# Use to regenerate: htpasswd -nbBC 10 "" argocd-admin | tr -d ':\n' | sed 's/$2y/$2a/' ; echo
#
#   default: admin:$2a$10$XRFNO/K5cHtptZl77vCOUO0/P4hMflV/wJaBmFtpTsjlwN0iQW7B6
#
ARGOCD_ADMIN_PASSWORD_HASHED='$2a$10$XRFNO/K5cHtptZl77vCOUO0/P4hMflV/wJaBmFtpTsjlwN0iQW7B6'
ARGOCD_ADMIN_PASSWORD="argocd-admin"
ARGOCD_ADMIN_USER="admin"
ARGOCD_HTTP_PORT=80
ARGOCD_NAMESPACE="argocd"

# Deploy argocd server in kubernetes using helm
#   args:
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'argocd')
#     (3) admin user (optional, default 'admin')
#     (4) admin password hashed (optional, default hashed 'argocd-admin')
function argocd_deploy_helm {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${ARGOCD_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${ARGOCD_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password_hashed="${ARGOCD_ADMIN_PASSWORD_HASHED}" || local admin_password_hashed="${4}" ;

  helm repo add argocd-charts https://argoproj.github.io/argo-helm ;
  helm repo update argocd-charts ;

  if $(helm status argocd --kube-context "${cluster_context}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade argocd argocd-charts/argo-cd \
      --kube-context "${cluster_context}" \
      --namespace "${namespace}" \
      --set configs.secret.argocdServerAdminPassword="${admin_password_hashed}" \
      --set configs.secret.argocdServerAdminPasswordMtime="2023-01-01T00:00:00Z" \
      --set server.service.type=LoadBalancer ;
    print_info "Upgraded helm chart for argocd" ;
  else
    helm install argocd argocd-charts/argo-cd \
      --create-namespace \
      --kube-context "${cluster_context}" \
      --namespace "${namespace}" \
      --set configs.secret.argocdServerAdminPassword="${admin_password_hashed}" \
      --set configs.secret.argocdServerAdminPasswordMtime="2023-01-01T00:00:00Z" \
      --set server.service.type=LoadBalancer ;
    print_info "Installed helm chart for argocd" ;
  fi
}

# Undeploy argocd from kubernetes using helm
#   args:
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'argocd')
function argocd_undeploy_helm {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${ARGOCD_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall argocd \
    --kube-context "${cluster_context}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for argocd" ;
}

# Get argocd server http url
#   args:
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'argocd')
function argocd_get_http_url {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${ARGOCD_NAMESPACE}" || local namespace="${2}" ;

  local argocd_ip=$(kubectl get svc --context "${cluster_context}" --namespace "${namespace}" argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${argocd_ip}" ]]; then
    print_error "Service 'argocd-server' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${argocd_ip}:${ARGOCD_HTTP_PORT}" ;
}

# Get argocd server http url with credentials
#   args:
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'argocd')
#     (3) admin user (optional, default 'admin')
#     (4) admin password (optional, default 'argocd-admin')
function argocd_get_http_url_with_credentials {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${ARGOCD_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${ARGOCD_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password="${ARGOCD_ADMIN_PASSWORD}" || local admin_password="${4}" ;

  local argocd_ip=$(kubectl get svc --context "${cluster_context}" --namespace "${namespace}" argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${argocd_ip}" ]]; then
    print_error "Service 'argocd-server' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${admin_user}:${admin_password}@${argocd_ip}:${ARGOCD_HTTP_PORT}" ;
}


# Get argocd version
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'admin:argocd-admin')
function argocd_get_version {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${ARGOCD_ADMIN_USER}:${ARGOCD_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  curl --insecure --location --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/version" ;
}

# Wait for argocd api to be ready
#     (1) api url
#     (2) basic auth credentials (optional, default 'admin:argocd-admin')
#     (3) timeout in seconds (optional, default '120')
function argocd_wait_api_ready {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${ARGOCD_ADMIN_USER}:${ARGOCD_ADMIN_PASSWORD}" || local basic_auth="${2}" ;
  [[ -z "${3}" ]] && local timeout="120" || local timeout="${3}" ;

  local count=0 ;
  echo -n "Waiting for argocd rest api to become ready at url '${base_url}' (basic auth credentials '${basic_auth}'): "
  while ! $(argocd_get_version "${base_url}" "${basic_auth}" &>/dev/null); do
    echo -n "." ; sleep 1 ; count=$((count+1)) ;
    if [[ ${count} -ge ${timeout} ]] ; then print_error "Timeout exceeded while waiting for argocd api readiness" ; return 1 ; fi
  done
  echo "DONE" ;
}
