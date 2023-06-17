# Helper functions to manage tsb management and control plane
#   Docs:
#     - https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/requirements-and-download 
#     - https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/helm/managementplane
#     - https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/helm/controlplane 

ENVOY_HTTPS_PORT=443
TSB_NAMESPACE="tsb"

# Deploy tsb management plane in kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) container registry
#     (3) tsb version
#     (4) tsb organization
#     (5) tsb gui certificate file
#     (6) tsb gui key file
#     (7) xcp central certificate file
#     (8) xcp central key file
#     (9) root ca certificate file
#     (10) namespace (optional, default 'tsb')
#     (11) tsb https port (optional, default '443')
function tsb_mp_deploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide container registry as 2nd argument" && return 2 || local container_registry="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide tsb version as 3rd argument" && return 2 || local tsb_version="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide tsb organization as 4th argument" && return 2 || local tsb_org="${4}" ;
  [[ -z "${5}" ]] && print_error "Please provide tsb gui certificate file as 5th argument" && return 2 || local tsb_gui_cert_file="${5}" ;
  [[ -z "${6}" ]] && print_error "Please provide tsb gui key file as 6th argument" && return 2 || local tsb_gui_key_file="${6}" ;
  [[ -z "${7}" ]] && print_error "Please provide tsb xcp central certificate file as 7th argument" && return 2 || local xcp_central_cert_file="${7}" ;
  [[ -z "${8}" ]] && print_error "Please provide xcp central key file as 8th argument" && return 2 || local xcp_central_key_file="${8}" ;
  [[ -z "${9}" ]] && print_error "Please provide root ca certificate file as 9th argument" && return 2 || local root_ca_cert_file="${9}" ;
  [[ -z "${10}" ]] && local namespace="${TSB_NAMESPACE}" || local namespace="${10}" ;
  [[ -z "${11}" ]] && local envoy_https_port="${ENVOY_HTTPS_PORT}" || local envoy_https_port="${11}" ;

  helm repo add tetrate-tsb-charts 'https://charts.dl.tetrate.io/public/helm/charts/' ;
  helm repo update ;

  if $(helm status tsb-mp --kubeconfig "${kubeconfig}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade tsb-mp tetrate-tsb-charts/managementplane \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set image.registry=${container_registry} \
      --set image.tag=${tsb_version} \
      --set secrets.ldap.binddn='cn=admin,dc=tetrate,dc=io' \
      --set secrets.ldap.bindpassword='admin' \
      --set secrets.postgres.password='tsb-postgres-password' \
      --set secrets.postgres.username='tsb' \
      --set secrets.tsb.adminPassword='admin' \
      --set-file secrets.tsb.cert=${tsb_gui_cert_file} \
      --set-file secrets.tsb.key=${tsb_gui_key_file} \
      --set secrets.xcp.autoGenerateCerts=false \
      --set-file secrets.xcp.central.cert=${xcp_central_cert_file} \
      --set-file secrets.xcp.central.key=${xcp_central_key_file} \
      --set-file secrets.xcp.rootca=${root_ca_cert_file} \
      --set spec.hub=${container_registry} \
      --set spec.organization=${tsb_org} \
      --set spec.components.frontEnvoy.port=${envoy_https_port} ;
    print_info "Upgraded helm chart for tsb-mp" ;
  else
    helm install tsb-mp tetrate-tsb-charts/managementplane \
      --create-namespace \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set image.registry=${container_registry} \
      --set image.tag=${tsb_version} \
      --set secrets.ldap.binddn='cn=admin,dc=tetrate,dc=io' \
      --set secrets.ldap.bindpassword='admin' \
      --set secrets.postgres.password='tsb-postgres-password' \
      --set secrets.postgres.username='tsb' \
      --set secrets.tsb.adminPassword='admin' \
      --set-file secrets.tsb.cert=${tsb_gui_cert_file} \
      --set-file secrets.tsb.key=${tsb_gui_key_file} \
      --set secrets.xcp.autoGenerateCerts=false \
      --set-file secrets.xcp.central.cert=${xcp_central_cert_file} \
      --set-file secrets.xcp.central.key=${xcp_central_key_file} \
      --set-file secrets.xcp.rootca=${root_ca_cert_file} \
      --set spec.hub=${container_registry} \
      --set spec.organization=${tsb_org} \
      --set spec.components.frontEnvoy.port=${envoy_https_port} ;
    print_info "Installed helm chart for tsb-mp" ;
  fi

}

# Undeploy tsb management plane from kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'tsb')
function registry_undeploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${TSB_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall tsb-mp \
    --kubeconfig "${kubeconfig}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for tsb-mp" ;
}
