# Helper functions to manage twun docker registry (docker registry v2)
#

REGISTRY_HTTP_PORT=5000
REGISTRY_NAMESPACE="registry"

# Deploy registry server in kubernetes using helm
#   args:
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'registry')
function registry_helm_deploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${REGISTRY_NAMESPACE}" || local namespace="${2}" ;

  helm repo add twuni-charts https://helm.twun.io ;
  helm repo update twuni-charts ;

  if $(helm status docker-registry --kube-context "${cluster_context}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade docker-registry twuni-charts/docker-registry \
      --kube-context "${cluster_context}" \
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
      --kube-context "${cluster_context}" \
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
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'registry')
function registry_helm_undeploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${REGISTRY_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall docker-registry \
    --kube-context "${cluster_context}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for docker-registry" ;
}

# Get docker registry endpoint
#   args:
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'registry')
function registry_get_docker_endpoint {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${REGISTRY_NAMESPACE}" || local namespace="${2}" ;

  local registry_ip=$(kubectl get svc --context "${cluster_context}" --namespace "${namespace}" docker-registry -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${registry_ip}" ]]; then
    print_error "Service 'docker-registry' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "${registry_ip}:${REGISTRY_HTTP_PORT}" ;
}

# Get docker registry http url
#   args:
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'registry')
function registry_get_http_url {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${REGISTRY_NAMESPACE}" || local namespace="${2}" ;

  local registry_ip=$(kubectl get svc --context "${cluster_context}" --namespace "${namespace}" docker-registry -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${registry_ip}" ]]; then
    print_error "Service 'docker-registry' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${registry_ip}:${REGISTRY_HTTP_PORT}" ;
}

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
  echo -n "Waiting for registry rest api to become ready at url '${base_api_url}': " ;

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
