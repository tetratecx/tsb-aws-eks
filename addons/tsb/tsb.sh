# Helper functions to manage tsb management and control plane using tctl
#   Docs:
#     - https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/requirements-and-download
#     - https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed
#     - https://docs.tetrate.io/service-bridge/1.6.x/en-us/reference/cli/guide/index#installation
#     - https://docs.tetrate.io/service-bridge/1.6.x/en-us/reference/cli/reference

ENVOY_HTTPS_PORT=8443
TSB_NAMESPACE="tsb"

# Login as admin into tsb
#   args:
#     (1) tsb organization
function login_tsb_admin {
  [[ -z "${1}" ]] && print_error "Please provide tsb organization as 1st argument" && return 2 || local tsb_org="${1}" ;

  expect <<DONE
  spawn tctl login --username admin --password admin --org ${tsb_org}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

# Patch OAP refresh rate of management plane
#   args:
#     (1) kubeconfig cluster context
function patch_oap_refresh_rate_mp {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${cluster_context} -n tsb patch managementplanes managementplane --type merge --patch ${oap_patch}
}

# Patch OAP refresh rate of control plane
#   args:
#     (1) kubeconfig cluster context
function patch_oap_refresh_rate_cp {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --context ${cluster_context} -n istio-system patch controlplanes controlplane --type merge --patch ${oap_patch}
}

# Patch jwt token expiration and pruneInterval
#   args:
#     (1) kubeconfig cluster context
function patch_jwt_token_expiration_mp {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;

  local token_patch='{"spec":{"tokenIssuer":{"jwt":{"expiration":"36000s","tokenPruneInterval":"36000s"}}}}'
  kubectl --context ${cluster_context} -n tsb patch managementplanes managementplane --type merge --patch ${token_patch}
}

# Patch GitOps enablement of control plane
#   args:
#     (1) kubeconfig cluster context
function patch_enable_gitop_cp {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;

  local gitops_patch='{"spec":{"components":{"gitops":{"enabled":true,"reconcileInterval":"30s","webhookTimeout":"30s"}}}}' ;
  kubectl --context ${cluster_context} -n istio-system patch controlplanes controlplane --type merge --patch ${gitops_patch}
}

# Deploy tsb management plane cluster using tctl
#   args:
#     (1) mp kubeconfig cluster context
#     (2) mp cluster name
#     (3) mp cluster region
#     (4) certificate base directory
function tsb_mp_deploy_tctl {
  [[ -z "${1}" ]] && print_error "Please provide mp kubeconfig cluster context as 1st argument" && return 2 || local mp_cluster_context="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide mp cluster name as 2nd argument" && return 2 || local mp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide mp cluster region as 3rd argument" && return 2 || local mp_cluster_region="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide certificate base directory as 4th argument" && return 2 || local certs_base_dir="${4}" ;

  print_info "Install tsb demo management/control plane in cluster '${mp_cluster_name}' in region '${mp_cluster_region}'"

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  if ! kubectl --context ${mp_cluster_context} get ns istio-system &>/dev/null; then
    kubectl --context ${mp_cluster_context} create ns istio-system ;
  fi
  if ! kubectl --context ${mp_cluster_context} -n istio-system get secret cacerts &>/dev/null; then
    kubectl --context ${mp_cluster_context} create secret generic cacerts -n istio-system \
      --from-file=${certs_base_dir}/${mp_cluster_name}/ca-cert.pem \
      --from-file=${certs_base_dir}/${mp_cluster_name}/ca-key.pem \
      --from-file=${certs_base_dir}/${mp_cluster_name}/root-cert.pem \
      --from-file=${certs_base_dir}/${mp_cluster_name}/cert-chain.pem ;
  fi

  # install tsb management plane using the demo profile
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/demo-installation
  #   NOTE: the demo profile deploys both the mgmt plane AND the ctrl plane!
  local repo_region=$(jq -r '.ecr.region' ${AWS_ENV_FILE}) ;
  local ecr_repository_url=$(get_ecr_repository_url "${AWS_PROFILE}" "${repo_region}") ;
  print_command "tctl install demo --cluster ${mp_cluster_name} --registry ${ecr_repository_url} --admin-password admin" ;
  kubectl config use-context ${mp_cluster_context} ;
  tctl install demo --cluster ${mp_cluster_name} --registry ${ecr_repository_url} --admin-password admin ;

  # We do this more times, because aws loadbalancer status causes consistent failure the first time
  #   Error: unable to connect to TSB at xyz:8443: time out trying to connection to TSB at xyz:8443
  while [[ $? != 0 ]]; do
    print_warning "Running 'tctl install demo' another time due to AWS LB timeout" ;
    kubectl config use-context ${mp_cluster_context} ;
    tctl install demo --cluster ${mp_cluster_name} --registry ${ecr_repository_url} --admin-password admin ;
  done

  # Wait for the management, control and data plane to become available
  kubectl --context ${mp_cluster_context} wait deployment -n tsb tsb-operator-management-plane --for condition=Available=True --timeout=600s ;
  kubectl --context ${mp_cluster_context} wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl --context ${mp_cluster_context} wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl --context ${mp_cluster_context} get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl --context ${mp_cluster_context} wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl --context ${mp_cluster_context} get pods -A ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_mp ${mp_cluster_context} ;
  patch_oap_refresh_rate_cp ${mp_cluster_context} ;
  patch_jwt_token_expiration_mp ${mp_cluster_context} ;

  # Enable gitops in the cp plane of the management cluster
  patch_enable_gitop_cp ${mp_cluster_context} ;
  print_command "tctl x gitops grant ${mp_cluster_name}" ;
  tctl x gitops grant ${mp_cluster_name} ;

  # Demo mgmt plane secret extraction (need to connect application clusters to mgmt cluster)
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets (demo install)
  local mp_output_dir="${ROOT_DIR}/output/${mp_cluster_name}" ;
  mkdir -p "${mp_output_dir}" ;
  kubectl --context ${mp_cluster_context} get -n istio-system secret mp-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${mp_output_dir}/mp-certs.pem ;
  kubectl --context ${mp_cluster_context} get -n istio-system secret es-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${mp_output_dir}/es-certs.pem ;
  kubectl --context ${mp_cluster_context} get -n istio-system secret xcp-central-ca-bundle -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${mp_output_dir}/xcp-central-ca-certs.pem ;

  print_info "Finished installation of tsb demo management/control plane in cluster '${mp_cluster_name}' in region '${mp_cluster_region}'"
}

# Deploy tsb management plane in kubernetes using helm
#   args:
#     (1) kubeconfig cluster context
#     (2) container registry
#     (3) tsb version
#     (4) tsb organization
#     (5) tsb gui certificate file
#     (6) tsb gui key file
#     (7) xcp central certificate file
#     (8) xcp central key file
#     (9) root ca certificate file
#     (10) namespace (optional, default 'tsb')
#     (11) tsb https port (optional, default '8443')
function tsb_mp_deploy_helm {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
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

  if $(helm status tsb-mp --kube-context "${cluster_context}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade tsb-mp tetrate-tsb-charts/managementplane \
      --kube-context "${cluster_context}" \
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
      --kube-context "${cluster_context}" \
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

# Undeploy tsb management plane cluster using tctl
#   args:
#     (1) mp kubeconfig cluster context
#     (2) mp cluster name
#     (3) mp cluster region
function tsb_mp_undeploy_tctl {
  [[ -z "${1}" ]] && print_error "Please provide mp kubeconfig cluster context as 1st argument" && return 2 || local mp_cluster_context="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide mp cluster name as 2nd argument" && return 2 || local mp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide mp cluster region as 3rd argument" && return 2 || local mp_cluster_region="${3}" ;

  print_info "Start removing installation of tsb demo management/control plane in cluster '${mp_cluster_name}' in region '${mp_cluster_region}'"

  # Put operators to sleep
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${mp_cluster_context} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${mp_cluster_context} scale deployment {} -n ${namespace} --replicas=0 ; 
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${mp_cluster_context} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${mp_cluster_context} delete deployment {} -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${mp_cluster_context} delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context ${mp_cluster_context} delete --all jobs -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context ${mp_cluster_context} delete --all statefulset -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context ${mp_cluster_context} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${mp_cluster_context} patch deployment {} -n ${namespace} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl --context ${mp_cluster_context} delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${mp_cluster_context} delete namespace ${namespace} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl --context ${mp_cluster_context} get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context ${mp_cluster_context} delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl --context ${mp_cluster_context} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${mp_cluster_context} delete crd {} --timeout=10s --wait=false ;
  kubectl --context ${mp_cluster_context} get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context ${mp_cluster_context} delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl --context ${mp_cluster_context} get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context ${mp_cluster_context} delete clusterrole {} --timeout=10s --wait=false ;
  kubectl --context ${mp_cluster_context} get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context ${mp_cluster_context} delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl --context ${mp_cluster_context} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${mp_cluster_context} delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl --context ${mp_cluster_context} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${mp_cluster_context} patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl --context ${mp_cluster_context} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${mp_cluster_context} delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${mp_cluster_context} get namespace ${namespace} -o json \
      | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
      | kubectl --context ${mp_cluster_context} replace --raw /api/v1/namespaces/${namespace}/finalize -f - ;
  done

  sleep 10 ;
  print_info "Finished removing installation of tsb demo management/control plane in cluster '${mp_cluster_name}' in region '${mp_cluster_region}'"
}

# Undeploy tsb management plane from kubernetes using helm
#   args:
#     (1) kubeconfig cluster context
#     (2) namespace (optional, default 'tsb')
function tsb_mp_undeploy_helm {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && local namespace="${TSB_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall tsb-mp \
    --kube-context "${cluster_context}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for tsb-mp" ;
}

# Bootstrap tsb control plane cluster installation using tctl
#   args:
#     (1) cp kubeconfig cluster context
#     (2) cp cluster name
#     (3) cp cluster region
#     (4) mp kubeconfig cluster context
#     (5) mp cluster name
#     (6) mp cluster region
#     (7) certificate base directory
function tsb_cp_bootstrap_tctl {
  [[ -z "${1}" ]] && print_error "Please provide cp kubeconfig cluster context as 1st argument" && return 2 || local cp_cluster_context="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cp cluster name as 2nd argument" && return 2 || local cp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cp cluster region as 3rd argument" && return 2 || local cp_cluster_region="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide mp kubeconfig cluster context as 4th argument" && return 2 || local mp_cluster_context="${4}" ;
  [[ -z "${5}" ]] && print_error "Please provide mp cluster name as 5th argument" && return 2 || local mp_cluster_name="${5}" ;
  [[ -z "${6}" ]] && print_error "Please provide mp cluster region as 6th argument" && return 2 || local mp_cluster_region="${6}" ;
  [[ -z "${7}" ]] && print_error "Please provide certificate base directory as 7th argument" && return 2 || local certs_base_dir="${7}" ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "tetrate" ;

  print_info "Start installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}'"
  local cp_output_dir="${ROOT_DIR}/output/${cp_cluster_name}" ;
  local mp_output_dir="${ROOT_DIR}/output/${mp_cluster_name}" ;
  mkdir -p "${cp_output_dir}" ;

  # Generate a service account private key for the active cluster
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  print_command "tctl install cluster-service-account --cluster ${cp_cluster_name} > ${cp_output_dir}/cluster-service-account.jwk" ;
  tctl install cluster-service-account --cluster ${cp_cluster_name} > ${cp_output_dir}/cluster-service-account.jwk ;

  # Create control plane secrets
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  print_command "tctl install manifest control-plane-secrets \
    --cluster ${cp_cluster_name} \
    --cluster-service-account=\"$(cat ${cp_output_dir}/cluster-service-account.jwk)\" \
    --elastic-ca-certificate=\"$(cat ${mp_output_dir}/es-certs.pem)\" \
    --management-plane-ca-certificate=\"$(cat ${mp_output_dir}/mp-certs.pem)\" \
    --xcp-central-ca-bundle=\"$(cat ${mp_output_dir}/xcp-central-ca-certs.pem)\" \
    > ${cp_output_dir}/controlplane-secrets.yaml" ;
  tctl install manifest control-plane-secrets \
    --cluster ${cp_cluster_name} \
    --cluster-service-account="$(cat ${cp_output_dir}/cluster-service-account.jwk)" \
    --elastic-ca-certificate="$(cat ${mp_output_dir}/es-certs.pem)" \
    --management-plane-ca-certificate="$(cat ${mp_output_dir}/mp-certs.pem)" \
    --xcp-central-ca-bundle="$(cat ${mp_output_dir}/xcp-central-ca-certs.pem)" \
    > ${cp_output_dir}/controlplane-secrets.yaml ;

  # Generate controlplane.yaml by inserting the correct mgmt plane API endpoint IP address
  local repo_region=$(jq -r '.ecr.region' ${AWS_ENV_FILE}) ;
  local ecr_repository_url=$(get_ecr_repository_url "${AWS_PROFILE}" "${repo_region}") ;
  export TSB_API_ENDPOINT=$(kubectl --context ${mp_cluster_context} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].hostname}') ;
  export TSB_CLUSTER_NAME=${cp_cluster_name} ;
  export ECR_REPO_URL=${ecr_repository_url} ;
  envsubst < ${ROOT_DIR}/templates/controlplane-template.yaml > ${cp_output_dir}/controlplane.yaml ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  if ! kubectl --context ${cp_cluster_context} get ns istio-system &>/dev/null; then
    kubectl --context ${cp_cluster_context} create ns istio-system ; 
  fi
  if ! kubectl --context ${cp_cluster_context} -n istio-system get secret cacerts &>/dev/null; then
    kubectl --context ${cp_cluster_context} create secret generic cacerts -n istio-system \
      --from-file=${certs_base_dir}/${cp_cluster_name}/ca-cert.pem \
      --from-file=${certs_base_dir}/${cp_cluster_name}/ca-key.pem \
      --from-file=${certs_base_dir}/${cp_cluster_name}/root-cert.pem \
      --from-file=${certs_base_dir}/${cp_cluster_name}/cert-chain.pem ;
  fi

  # Deploy operators
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#deploy-operators
  login_tsb_admin "tetrate" ;
  print_command "tctl install manifest cluster-operators --registry ${tsb_install_repo} > ${cp_output_dir}/clusteroperators.yaml" ;
  tctl install manifest cluster-operators --registry ${ecr_repository_url} > ${cp_output_dir}/clusteroperators.yaml ;

  # Applying operator, secrets and control plane configuration
  kubectl --context ${cp_cluster_context} apply -f ${cp_output_dir}/clusteroperators.yaml ;
  kubectl --context ${cp_cluster_context} apply -f ${cp_output_dir}/controlplane-secrets.yaml ;
  while ! kubectl --context ${cp_cluster_context} get controlplanes.install.tetrate.io &>/dev/null; do sleep 1; done ;
  kubectl --context ${cp_cluster_context} apply -f ${cp_output_dir}/controlplane.yaml ;
  print_info "Bootstrapped installation of tsb control plane in cluster ${cp_cluster_name} in region '${cp_cluster_region}'"
}

# Wait for tsb control plane cluster to be ready
#   args:
#     (1) cp kubeconfig cluster context
#     (2) cp cluster name
#     (3) cp cluster region
function tsb_cp_wait_ready {
  [[ -z "${1}" ]] && print_error "Please provide cp kubeconfig cluster context as 1st argument" && return 2 || local cp_cluster_context="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cp cluster name as 2nd argument" && return 2 || local cp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cp cluster region as 3rd argument" && return 2 || local cp_cluster_region="${3}" ;

  print_info "Wait installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}' to finish"

  # Wait for the control and data plane to become available
  kubectl --context ${cp_cluster_context} wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl --context ${cp_cluster_context} wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl --context ${cp_cluster_context} get deployment -n istio-system edge &>/dev/null; do sleep 5; done ;
  kubectl --context ${cp_cluster_context} wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl --context ${cp_cluster_context} get pods -A ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_cp ${cp_cluster_context} ;

  print_info "Finished installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}'"
}

# Undeploy tsb control plane cluster using tctl
#   args:
#     (1) cp kubeconfig cluster context
#     (2) cp cluster name
#     (3) cp cluster region
function tsb_cp_undeploy_tctl {
  [[ -z "${1}" ]] && print_error "Please provide cp kubeconfig cluster context as 1st argument" && return 2 || local cp_cluster_context="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cp cluster name as 2nd argument" && return 2 || local cp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cp cluster region as 3rd argument" && return 2 || local cp_cluster_region="${3}" ;

  print_info "Start removing installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}'"

  # Put operators to sleep
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${cp_cluster_context} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${cp_cluster_context} scale deployment {} -n ${namespace} --replicas=0 ; 
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${cp_cluster_context} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${cp_cluster_context} delete deployment {} -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${cp_cluster_context} delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context ${cp_cluster_context} delete --all jobs -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context ${cp_cluster_context} delete --all statefulset -n ${namespace} --timeout=10s --wait=false ;
    kubectl --context ${cp_cluster_context} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --context ${cp_cluster_context} patch deployment {} -n ${namespace} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl --context ${cp_cluster_context} delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --context ${cp_cluster_context} delete namespace ${namespace} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl --context ${cp_cluster_context} get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context ${cp_cluster_context} delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl --context ${cp_cluster_context} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${cp_cluster_context} delete crd {} --timeout=10s --wait=false ;
  kubectl --context ${cp_cluster_context} get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --context ${cp_cluster_context} delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl --context ${cp_cluster_context} get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context ${cp_cluster_context} delete clusterrole {} --timeout=10s --wait=false ;
  kubectl --context ${cp_cluster_context} get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --context ${cp_cluster_context} delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl --context ${cp_cluster_context} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${cp_cluster_context} delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl --context ${cp_cluster_context} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${cp_cluster_context} patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl --context ${cp_cluster_context} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --context ${cp_cluster_context} delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --context ${cp_cluster_context} get namespace ${namespace} -o json \
      | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
      | kubectl --context ${cp_cluster_context} replace --raw /api/v1/namespaces/${namespace}/finalize -f - ;
  done

  sleep 10 ;
  print_info "Finished removing installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}'"
}