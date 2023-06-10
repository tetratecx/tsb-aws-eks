# Helper functions to start, upgrade and remove twun docker registry (docker registry v2)
#

REGISTRY_HTTP_PORT=5000
REGISTRY_NAMESPACE="registry"

# Deploy registry server in kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'registry')
function registry_deploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${REGISTRY_NAMESPACE}" || local namespace="${2}" ;

  helm repo add twuni-charts https://helm.twun.io ;
  helm repo update twuni-charts ;

  if $(helm status docker-registry --kubeconfig "${kubeconfig}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade docker-registry twuni-charts/docker-registry \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set persistence.deleteEnabled=true \
      --set persistence.enabled=true \
      --set persistence.size=10Gi \
      --set replicaCount=1 \
      --set secrets.htpasswd="" \
      --set service.type=LoadBalancer ;
    print_info "Upgraded helm chart for docker-registry" ;
  else
    helm install docker-registry twuni-charts/docker-registry \
      --create-namespace \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set persistence.deleteEnabled=true \
      --set persistence.enabled=true \
      --set persistence.size=10Gi \
      --set replicaCount=1 \
      --set secrets.htpasswd="" \
      --set service.type=LoadBalancer ;
    print_info "Installed helm chart for docker-registry" ;
  fi
  
}

# Undeploy registry from kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'registry')
function registry_undeploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${REGISTRY_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall docker-registry \
    --kubeconfig "${kubeconfig}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for docker-registry" ;
}

# Get docker registry endpoint
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'registry')
function registry_get_docker_endpoint {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${REGISTRY_NAMESPACE}" || local namespace="${2}" ;

  local registry_ip=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" docker-registry -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${registry_ip}" ]]; then
    print_error "Service 'docker-registry' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "${registry_ip}:${REGISTRY_HTTP_PORT}" ;
}

# Get docker registry http url
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'registry')
function registry_get_http_url {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${REGISTRY_NAMESPACE}" || local namespace="${2}" ;

  local registry_ip=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" docker-registry -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${registry_ip}" ]]; then
    print_error "Service 'docker-registry' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${registry_ip}:${REGISTRY_HTTP_PORT}" ;
}
