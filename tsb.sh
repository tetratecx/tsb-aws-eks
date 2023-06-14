#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
source ${ROOT_DIR}/addons/aws/ecr.sh ;
source ${ROOT_DIR}/addons/helm/tsb.sh ;

AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;
HOST_ENV_FILE=${ROOT_DIR}/env_host.json ;

AWS_PROFILE=$(cat ${AWS_ENV_FILE} | jq -r ".profile") ;

ACTION=${1} ;

# Login as admin into tsb
#   args:
#     (1) kubeconfig file
#     (2) tsb organization
function login_tsb_admin {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig_file="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide tsb organization as 2nd argument" && return 2 || local tsb_org="${2}" ;

  KUBECONFIG=${kubeconfig_file} expect <<DONE
  spawn tctl login --username admin --password admin --org ${tsb_org}
  expect "Tenant:" { send "\\r" }
  expect eof
DONE
}

# Patch OAP refresh rate of management plane
#   args:
#     (1) kubeconfig file
function patch_oap_refresh_rate_mp {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig_file="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --kubeconfig ${kubeconfig_file} -n tsb patch managementplanes managementplane --type merge --patch ${oap_patch}
}

# Patch OAP refresh rate of control plane
#   args:
#     (1) kubeconfig file
function patch_oap_refresh_rate_cp {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig_file="${1}" ;

  local oap_patch='{"spec":{"components":{"oap":{"streamingLogEnabled":true,"kubeSpec":{"deployment":{"env":[{"name":"SW_CORE_PERSISTENT_PERIOD","value":"5"}]}}}}}}'
  kubectl --kubeconfig ${kubeconfig_file} -n istio-system patch controlplanes controlplane --type merge --patch ${oap_patch}
}

# Patch jwt token expiration and pruneInterval
#   args:
#     (1) kubeconfig file
function patch_jwt_token_expiration_mp {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig_file="${1}" ;

  local token_patch='{"spec":{"tokenIssuer":{"jwt":{"expiration":"36000s","tokenPruneInterval":"36000s"}}}}'
  kubectl --kubeconfig ${kubeconfig_file} -n tsb patch managementplanes managementplane --type merge --patch ${token_patch}
}

# Patch GitOps enablement of control plane
#   args:
#     (1) kubeconfig file
function patch_enable_gitop_cp {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig_file="${1}" ;

  local gitops_patch='{"spec":{"components":{"gitops":{"enabled":true,"reconcileInterval":"30s","webhookTimeout":"30s"}}}}' ;
  kubectl --kubeconfig ${kubeconfig_file} -n istio-system patch controlplanes controlplane --type merge --patch ${gitops_patch}
}

# Install tsb management plane cluster
#   args:
#     (1) mp kubeconfig file
#     (2) mp cluster name
#     (3) mp cluster region
function install_tsb_mp {
  [[ -z "${1}" ]] && print_error "Please provide mp kubeconfig file as 1st argument" && return 2 || local mp_cluster_kubeconfig="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide mp cluster name as 2nd argument" && return 2 || local mp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide mp cluster region as 3rd argument" && return 2 || local mp_cluster_region="${3}" ;

  print_info "Install tsb demo management/control plane in cluster '${mp_cluster_name}' in region '${mp_cluster_region}'"

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  local certs_base_dir="${ROOT_DIR}/certs" ;
  if ! kubectl --kubeconfig ${mp_cluster_kubeconfig} get ns istio-system &>/dev/null; then
    kubectl --kubeconfig ${mp_cluster_kubeconfig} create ns istio-system ;
  fi
  if ! kubectl --kubeconfig ${mp_cluster_kubeconfig} -n istio-system get secret cacerts &>/dev/null; then
    kubectl --kubeconfig ${mp_cluster_kubeconfig} create secret generic cacerts -n istio-system \
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
  print_command "KUBECONFIG=${mp_cluster_kubeconfig} tctl install demo --cluster ${mp_cluster_name} --registry ${ecr_repository_url} --admin-password admin"
  KUBECONFIG=${mp_cluster_kubeconfig} tctl install demo --cluster ${mp_cluster_name} --registry ${ecr_repository_url} --admin-password admin ;

  # We do this a second time, because aws loadbalancer status causes consistent failure the first time
  #   Error: unable to connect to TSB at xyz:8443: time out trying to connection to TSB at xyz:8443
  if [[ $? != 0 ]]; then
    print_warning "Running 'tctl install demo' a second time due to AWS LB timeout"
    KUBECONFIG=${mp_cluster_kubeconfig} tctl install demo --cluster ${mp_cluster_name} --registry ${ecr_repository_url} --admin-password admin ;
  fi

  # Wait for the management, control and data plane to become available
  kubectl --kubeconfig ${mp_cluster_kubeconfig} wait deployment -n tsb tsb-operator-management-plane --for condition=Available=True --timeout=600s ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl --kubeconfig ${mp_cluster_kubeconfig} get deployment -n istio-system edge &>/dev/null; do sleep 1; done ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get pods -A ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_mp ${mp_cluster_kubeconfig} ;
  patch_oap_refresh_rate_cp ${mp_cluster_kubeconfig} ;
  patch_jwt_token_expiration_mp ${mp_cluster_kubeconfig} ;

  # Enable gitops in the cp plane of the management cluster
  patch_enable_gitop_cp ${mp_cluster_kubeconfig} ;
  print_command "KUBECONFIG=${mp_cluster_kubeconfig} tctl x gitops grant ${mp_cluster_name}" ;
  KUBECONFIG=${mp_cluster_kubeconfig} tctl x gitops grant ${mp_cluster_name} ;

  # Demo mgmt plane secret extraction (need to connect application clusters to mgmt cluster)
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets (demo install)
  local mp_output_dir="${ROOT_DIR}/output/${mp_cluster_name}" ;
  mkdir -p "${mp_output_dir}" ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get -n istio-system secret mp-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${mp_output_dir}/mp-certs.pem ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get -n istio-system secret es-certs -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${mp_output_dir}/es-certs.pem ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get -n istio-system secret xcp-central-ca-bundle -o jsonpath='{.data.ca\.crt}' | base64 --decode > ${mp_output_dir}/xcp-central-ca-certs.pem ;

  print_info "Finished installation of tsb demo management/control plane in cluster '${mp_cluster_name}' in region '${mp_cluster_region}'"
}

# Uninstall tsb management plane cluster
#   args:
#     (1) mp kubeconfig file
#     (2) mp cluster name
#     (3) mp cluster region
function uninstall_tsb_mp {
  [[ -z "${1}" ]] && print_error "Please provide mp kubeconfig file as 1st argument" && return 2 || local mp_cluster_kubeconfig="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide mp cluster name as 2nd argument" && return 2 || local mp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide mp cluster region as 3rd argument" && return 2 || local mp_cluster_region="${3}" ;

  print_info "Start removing installation of tsb demo management/control plane in cluster '${mp_cluster_name}' in region '${mp_cluster_region}'"

  # Put operators to sleep
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --kubeconfig ${mp_cluster_kubeconfig} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} scale deployment {} -n ${namespace} --replicas=0 ; 
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --kubeconfig ${mp_cluster_kubeconfig} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} delete deployment {} -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --kubeconfig ${mp_cluster_kubeconfig} delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    kubectl --kubeconfig ${mp_cluster_kubeconfig} delete --all jobs -n ${namespace} --timeout=10s --wait=false ;
    kubectl --kubeconfig ${mp_cluster_kubeconfig} delete --all statefulset -n ${namespace} --timeout=10s --wait=false ;
    kubectl --kubeconfig ${mp_cluster_kubeconfig} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} patch deployment {} -n ${namespace} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl --kubeconfig ${mp_cluster_kubeconfig} delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --kubeconfig ${mp_cluster_kubeconfig} delete namespace ${namespace} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} delete crd {} --timeout=10s --wait=false ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} delete clusterrole {} --timeout=10s --wait=false ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl --kubeconfig ${mp_cluster_kubeconfig} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --kubeconfig ${mp_cluster_kubeconfig} delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --kubeconfig ${mp_cluster_kubeconfig} get namespace ${namespace} -o json \
      | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
      | kubectl --kubeconfig ${mp_cluster_kubeconfig} replace --raw /api/v1/namespaces/${namespace}/finalize -f - ;
  done

  sleep 10 ;
  print_info "Finished removing installation of tsb demo management/control plane in cluster '${mp_cluster_name}' in region '${mp_cluster_region}'"
}

# Bootstrap tsb control plane cluster installation
#   args:
#     (1) cp kubeconfig file
#     (2) cp cluster name
#     (3) cp cluster region
#     (4) mp kubeconfig file
#     (5) mp cluster name
#     (6) mp cluster region
function bootstrap_install_tsb_cp {
  [[ -z "${1}" ]] && print_error "Please provide cp kubeconfig file as 1st argument" && return 2 || local cp_cluster_kubeconfig="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cp cluster name as 2nd argument" && return 2 || local cp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cp cluster region as 3rd argument" && return 2 || local cp_cluster_region="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide mp cluster name as 4th argument" && return 2 || local mp_cluster_kubeconfig="${4}" ;
  [[ -z "${5}" ]] && print_error "Please provide mp cluster name as 5th argument" && return 2 || local mp_cluster_name="${5}" ;
  [[ -z "${6}" ]] && print_error "Please provide mp cluster region as 6th argument" && return 2 || local mp_cluster_region="${6}" ;

  # Login again as tsb admin in case of a session time-out
  login_tsb_admin "${mp_cluster_kubeconfig}" "tetrate" ;

  print_info "Start installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}'"
  local cp_output_dir="${ROOT_DIR}/output/${cp_cluster_name}" ;
  local mp_output_dir="${ROOT_DIR}/output/${mp_cluster_name}" ;
  mkdir -p "${cp_output_dir}" ;

  # Generate a service account private key for the active cluster
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  print_command "KUBECONFIG=${mp_cluster_kubeconfig} tctl install cluster-service-account --cluster ${cp_cluster_name} > ${cp_output_dir}/cluster-service-account.jwk" ;
  KUBECONFIG=${mp_cluster_kubeconfig} tctl install cluster-service-account --cluster ${cp_cluster_name} > ${cp_output_dir}/cluster-service-account.jwk ;

  # Create control plane secrets
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#using-tctl-to-generate-secrets
  print_command "KUBECONFIG=${mp_cluster_kubeconfig} tctl install manifest control-plane-secrets \
    --cluster ${cp_cluster_name} \
    --cluster-service-account=\"$(cat ${cp_output_dir}/cluster-service-account.jwk)\" \
    --elastic-ca-certificate=\"$(cat ${mp_output_dir}/es-certs.pem)\" \
    --management-plane-ca-certificate=\"$(cat ${mp_output_dir}/mp-certs.pem)\" \
    --xcp-central-ca-bundle=\"$(cat ${mp_output_dir}/xcp-central-ca-certs.pem)\" \
    > ${cp_output_dir}/controlplane-secrets.yaml" ;
  KUBECONFIG=${mp_cluster_kubeconfig} tctl install manifest control-plane-secrets \
    --cluster ${cp_cluster_name} \
    --cluster-service-account="$(cat ${cp_output_dir}/cluster-service-account.jwk)" \
    --elastic-ca-certificate="$(cat ${mp_output_dir}/es-certs.pem)" \
    --management-plane-ca-certificate="$(cat ${mp_output_dir}/mp-certs.pem)" \
    --xcp-central-ca-bundle="$(cat ${mp_output_dir}/xcp-central-ca-certs.pem)" \
    > ${cp_output_dir}/controlplane-secrets.yaml ;

  # Generate controlplane.yaml by inserting the correct mgmt plane API endpoint IP address
  local repo_region=$(jq -r '.ecr.region' ${AWS_ENV_FILE}) ;
  local ecr_repository_url=$(get_ecr_repository_url "${AWS_PROFILE}" "${repo_region}") ;
  export TSB_API_ENDPOINT=$(kubectl --kubeconfig ${mp_cluster_kubeconfig} get svc -n tsb envoy --output jsonpath='{.status.loadBalancer.ingress[0].hostname}') ;
  export TSB_CLUSTER_NAME=${cp_cluster_name} ;
  export ECR_REPO_URL=${ecr_repository_url} ;
  envsubst < ${ROOT_DIR}/templates/controlplane-template.yaml > ${cp_output_dir}/controlplane.yaml ;

  # bootstrap cluster with self signed certificate that share a common root certificate
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#intermediate-istio-ca-certificates
  local certs_base_dir="${ROOT_DIR}/certs" ;
  if ! kubectl --kubeconfig ${cp_cluster_kubeconfig} get ns istio-system &>/dev/null; then
    kubectl --kubeconfig ${cp_cluster_kubeconfig} create ns istio-system ; 
  fi
  if ! kubectl --kubeconfig ${cp_cluster_kubeconfig} -n istio-system get secret cacerts &>/dev/null; then
    kubectl --kubeconfig ${cp_cluster_kubeconfig} create secret generic cacerts -n istio-system \
      --from-file=${certs_base_dir}/${cp_cluster_name}/ca-cert.pem \
      --from-file=${certs_base_dir}/${cp_cluster_name}/ca-key.pem \
      --from-file=${certs_base_dir}/${cp_cluster_name}/root-cert.pem \
      --from-file=${certs_base_dir}/${cp_cluster_name}/cert-chain.pem ;
  fi

  # Deploy operators
  #   REF: https://docs.tetrate.io/service-bridge/1.6.x/en-us/setup/self_managed/onboarding-clusters#deploy-operators
  login_tsb_admin "${mp_cluster_kubeconfig}" "tetrate" ;
  print_command "KUBECONFIG=${mp_cluster_kubeconfig} tctl install manifest cluster-operators --registry ${tsb_install_repo} > ${cp_output_dir}/clusteroperators.yaml" ;
  KUBECONFIG=${mp_cluster_kubeconfig} tctl install manifest cluster-operators --registry ${ecr_repository_url} > ${cp_output_dir}/clusteroperators.yaml ;

  # Applying operator, secrets and control plane configuration
  kubectl --kubeconfig ${cp_cluster_kubeconfig} apply -f ${cp_output_dir}/clusteroperators.yaml ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} apply -f ${cp_output_dir}/controlplane-secrets.yaml ;
  while ! kubectl --kubeconfig ${cp_cluster_kubeconfig} get controlplanes.install.tetrate.io &>/dev/null; do sleep 1; done ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} apply -f ${cp_output_dir}/controlplane.yaml ;
  print_info "Bootstrapped installation of tsb control plane in cluster ${cp_cluster_name} in region '${cp_cluster_region}'"
}

# Wait for tsb control plane cluster to be ready
#   args:
#     (1) cp kubeconfig file
#     (2) cp cluster name
#     (3) cp cluster region
function wait_tsb_cp_ready {
  [[ -z "${1}" ]] && print_error "Please provide cp kubeconfig file as 1st argument" && return 2 || local cp_cluster_kubeconfig="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cp cluster name as 2nd argument" && return 2 || local cp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cp cluster region as 3rd argument" && return 2 || local cp_cluster_region="${3}" ;

  print_info "Wait installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}' to finish"

  # Wait for the control and data plane to become available
  kubectl --kubeconfig ${cp_cluster_kubeconfig} wait deployment -n istio-system tsb-operator-control-plane --for condition=Available=True --timeout=600s ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} wait deployment -n istio-gateway tsb-operator-data-plane --for condition=Available=True --timeout=600s ;
  while ! kubectl --kubeconfig ${cp_cluster_kubeconfig} get deployment -n istio-system edge &>/dev/null; do sleep 5; done ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} wait deployment -n istio-system edge --for condition=Available=True --timeout=600s ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get pods -A ;

  # Apply OAP patch for more real time update in the UI (Apache SkyWalking demo tweak)
  patch_oap_refresh_rate_cp ${cp_cluster_kubeconfig} ;

  print_info "Finished installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}'"
}

# Uninstall tsb control plane cluster
#   args:
#     (1) cp kubeconfig file
#     (2) cp cluster name
#     (3) cp cluster region
function uninstall_tsb_cp {
  [[ -z "${1}" ]] && print_error "Please provide cp kubeconfig file as 1st argument" && return 2 || local cp_cluster_kubeconfig="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cp cluster name as 2nd argument" && return 2 || local cp_cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cp cluster region as 3rd argument" && return 2 || local cp_cluster_region="${3}" ;

  print_info "Start removing installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}'"

  # Put operators to sleep
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --kubeconfig ${cp_cluster_kubeconfig} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} scale deployment {} -n ${namespace} --replicas=0 ; 
  done

  sleep 5 ;

  # Clean up namespace specific resources
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --kubeconfig ${cp_cluster_kubeconfig} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} delete deployment {} -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --kubeconfig ${cp_cluster_kubeconfig} delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    kubectl --kubeconfig ${cp_cluster_kubeconfig} delete --all jobs -n ${namespace} --timeout=10s --wait=false ;
    kubectl --kubeconfig ${cp_cluster_kubeconfig} delete --all statefulset -n ${namespace} --timeout=10s --wait=false ;
    kubectl --kubeconfig ${cp_cluster_kubeconfig} get deployments -n ${namespace} -o custom-columns=:metadata.name \
      | grep operator | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} patch deployment {} -n ${namespace} --type json \
      --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
    kubectl --kubeconfig ${cp_cluster_kubeconfig} delete --all deployments -n ${namespace} --timeout=10s --wait=false ;
    sleep 5 ;
    kubectl --kubeconfig ${cp_cluster_kubeconfig} delete namespace ${namespace} --timeout=10s --wait=false ;
  done 

  # Clean up cluster wide resources
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} delete crd {} --timeout=10s --wait=false ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get validatingwebhookconfigurations -o custom-columns=:metadata.name \
    | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} delete clusterrole {} --timeout=10s --wait=false ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
    | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} delete clusterrolebinding {} --timeout=10s --wait=false ;

  # Cleanup custom resource definitions
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} delete crd {} --timeout=10s --wait=false ;
  sleep 5 ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
  sleep 5 ;
  kubectl --kubeconfig ${cp_cluster_kubeconfig} get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
    | xargs -I {} kubectl --kubeconfig ${cp_cluster_kubeconfig} delete crd {} --timeout=10s --wait=false ;

  # Clean up pending finalizer namespaces
  for namespace in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do
    kubectl --kubeconfig ${cp_cluster_kubeconfig} get namespace ${namespace} -o json \
      | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
      | kubectl --kubeconfig ${cp_cluster_kubeconfig} replace --raw /api/v1/namespaces/${namespace}/finalize -f - ;
  done

  sleep 10 ;
  print_info "Finished removing installation of tsb control plane in cluster '${cp_cluster_name}' in region '${cp_cluster_region}'"
}


if [[ ${ACTION} = "install" ]]; then

  # certs_base_dir="${ROOT_DIR}/certs/tsb" ;

  # First start and finish mp cluster installation
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    if [[ "${cluster_tsb_type}" == "mp" ]]; then
      mp_cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
      mp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      mp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      install_tsb_mp "${mp_cluster_kubeconfig}" "${mp_cluster_name}" "${mp_cluster_region}" ;

      # WIP helm: tsb_mp_deploy
    fi
  done

  # Second bootstrap cp cluster installation
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    if [[ "${cluster_tsb_type}" == "cp" ]]; then
      cp_cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
      cp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      cp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      bootstrap_install_tsb_cp "${cp_cluster_kubeconfig}" "${cp_cluster_name}" "${cp_cluster_region}" \
                               "${mp_cluster_kubeconfig}" "${mp_cluster_name}" "${mp_cluster_region}" ;
    fi
  done

  # Third wait for cp clusters to finished installation
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    if [[ "${cluster_tsb_type}" == "cp" ]]; then
      cp_cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
      cp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      cp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      wait_tsb_cp_ready "${cp_cluster_kubeconfig}" "${cp_cluster_name}" "${cp_cluster_region}" ;
    fi
  done

  exit 0 ;
fi

if [[ ${ACTION} = "uninstall" ]]; then
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;

    if [[ "${cluster_tsb_type}" == "mp" ]]; then
      mp_cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
      mp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      mp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      uninstall_tsb_mp "${mp_cluster_kubeconfig}" "${mp_cluster_name}" "${mp_cluster_region}" ;
    fi

    if [[ "${cluster_tsb_type}" == "cp" ]]; then
      cp_cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
      cp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      cp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      uninstall_tsb_cp "${cp_cluster_kubeconfig}" "${cp_cluster_name}" "${cp_cluster_region}" ;
    fi
  done

  exit 0 ;
fi

if [[ ${ACTION} = "info" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;

    if [[ "${cluster_tsb_type}" == "mp" ]]; then
      mp_cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
      mp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      mp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
      tsb_api_endpoint=$(kubectl --kubeconfig ${mp_cluster_kubeconfig} get svc -n tsb envoy \
        --output jsonpath='{.status.loadBalancer.ingress[0].hostname}') ;

      print_info "Management plane cluster ${mp_cluster_name} in region '${mp_cluster_region}':" ;
      print_error "TSB GUI: https://${tsb_api_endpoint}:8443 (admin/admin)" ;
      echo ;
      print_command "kubectl --kubeconfig ${mp_cluster_kubeconfig} get pods -A" ;
      echo ;
    fi

    if [[ "${cluster_tsb_type}" == "cp" ]]; then
      cp_cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
      cp_cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
      cp_cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;

      print_info "Control plane cluster ${cp_cluster_name} in region '${cp_cluster_region}':" ;
      print_command "kubectl --kubeconfig ${cp_cluster_kubeconfig} get pods -A" ;
      echo ;
    fi
  done

  exit 0 ;
fi


echo "Please specify correct action:" ;
echo "  - install" ;
echo "  - uninstall" ;
echo "  - info" ;
exit 1 ;
