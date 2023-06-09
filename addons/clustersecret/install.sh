# Helper functions to start, upgrade and remove clustersecret (to auto sync secrets in all namespaces)
#

# Some colors
END_COLOR="\033[0m"
GREENB_COLOR="\033[1;32m"
REDB_COLOR="\033[1;31m"


CLUSTERSECRET_NAMESPACE="clustersecret"

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

# Deploy clustersecret controller in kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'clustersecret')
function clustersecret_deploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${CLUSTERSECRET_NAMESPACE}" || local namespace="${2}" ;

  helm repo add clustersecret-charts https://charts.clustersecret.io/ ;
  helm repo update ;

  if $(helm status clustersecret --kubeconfig "${kubeconfig}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade clustersecret clustersecret-charts/clustersecret \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" ;
    print_info "Upgraded helm chart for clustersecret" ;
  else
    helm install clustersecret clustersecret-charts/clustersecret \
      --create-namespace \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" ;
    print_info "Installed helm chart for clustersecret" ;
  fi
  
}

# Undeploy clustersecret controller from kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'clustersecret')
function clustersecret_undeploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${CLUSTERSECRET_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall clustersecret \
    --kubeconfig "${kubeconfig}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for clustersecret" ;
}
