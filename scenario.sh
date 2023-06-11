#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
source ${ROOT_DIR}/certs.sh ;
source ${ROOT_DIR}/addons/aws/ecr.sh ;
source ${ROOT_DIR}/addons/helm/argocd.sh ;
source ${ROOT_DIR}/addons/helm/gitea.sh ;

AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;
ARGOCD_APPS_DIR="${ROOT_DIR}/argocd-apps" ;
GITEA_REPOS_DIR="${ROOT_DIR}/gitea-repos" ;
GITEA_REPOS_CONFIG="${GITEA_REPOS_DIR}/repos.json" ;

AWS_PROFILE=$(cat ${AWS_ENV_FILE} | jq -r ".profile") ;

ACTION=${1} ;

  # Repo synchronization using git clone, add, commit and push
#   args:
#     (1) mp kubeconfig file
#     (2) ecr repo url
function create_and_sync_gitea_repos {
  [[ -z "${1}" ]] && print_error "Please provide mp kubeconfig file as 1st argument" && return 2 || local mp_kubeconfig_file="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide ecr repo url as 1st argument" && return 2 || local ecr_repo_url="${2}" ;

  local gitea_http_url=$(gitea_get_http_url "${mp_kubeconfig_file}") ;
  local gitea_http_url_creds=$(gitea_get_http_url_with_credentials "${mp_kubeconfig_file}") ;

  # Gitea repository creation
  local repo_count=$(jq '. | length' ${GITEA_REPOS_CONFIG}) ;
  local existing_repo_list=$(gitea_get_repos_list "${gitea_http_url}") ;
  for ((repo_index=0; repo_index<${repo_count}; repo_index++)); do
    local repo_description=$(jq -r '.['${repo_index}'].description' ${GITEA_REPOS_CONFIG}) ;
    local repo_name=$(jq -r '.['${repo_index}'].name' ${GITEA_REPOS_CONFIG}) ;

    if $(echo ${existing_repo_list} | grep "${repo_name}" &>/dev/null); then
      print_info "Gitea repository '${repo_name}' already exists" ;
    else
      print_info "Create gitea repository '${repo_name}'" ;
      gitea_create_repo_current_user "${gitea_http_url}" "${repo_name}" "${repo_description}" ;
    fi
  done

  # Repo synchronization using git clone, remove, add, commit and push
  local repo_count=$(jq '. | length' ${GITEA_REPOS_CONFIG}) ;
  for ((repo_index=0; repo_index<${repo_count}; repo_index++)); do
    local repo_name=$(jq -r '.['${repo_index}'].name' ${GITEA_REPOS_CONFIG}) ;
    print_info "Sync code for gitea repository '${repo_name}'" ;
    gitea_sync_code_to_repo "${GITEA_REPOS_DIR}" "${gitea_http_url_creds}" "${repo_name}" "ECR_REPO_URL=${ecr_repo_url}" ;
  done
}

  # Repo synchronization using git clone, add, commit and push
#   args:
#     (1) kubeconfig file
#     (2) cluster name
#     (3) gitea public url
function deploy_argocd_applications {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig_file="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide gitea public url as 3rd argument" && return 2 || local gitea_url="${3}" ;

  print_info "Deploying argocd applications in cluster '${cluster_name}' from gitea url '${gitea_url}'" ;
  export GITEA_PUBLIC_URL="${gitea_url}" ;
  
  for yaml_file in ${ARGOCD_APPS_DIR}/${cluster_name}/*.yaml ; do
    envsubst < ${yaml_file} | kubectl --kubeconfig ${kubeconfig_file} apply -f - ;
  done
}

if [[ ${ACTION} = "deploy" ]]; then

  # Get public gitea url
  mp_kubeconfig=$(jq -r '.eks.clusters[] | select(.name=="mgmt").kubeconfig' ${AWS_ENV_FILE}) ;
  gitea_public_url=$(gitea_get_http_url ${mp_kubeconfig}) ;

  # Generate the necessary client and server application certificates
  certs_base_dir="${ROOT_DIR}/output/certs" ;
  mkdir -p "${certs_base_dir}" ;
  # HTTPS SERVER
  generate_server_cert "${certs_base_dir}" "abc-https" ;
  generate_kubernetes_ingress_secret_https \
    "${GITEA_REPOS_DIR}/app-abc/k8s/mgmt/00-tier1-https-secret.yaml" \
    "abc-https-cert" \
    "${certs_base_dir}/abc-https/server.abc-https.demo.tetrate.io-key.pem" \
    "${certs_base_dir}/abc-https/server.abc-https.demo.tetrate.io-cert.pem" \
    "tier1-abc" ;
  generate_kubernetes_ingress_secret_https \
    "${GITEA_REPOS_DIR}/app-abc/k8s/active/00-ingress-https-secret.yaml" \
    "abc-https-cert" \
    "${certs_base_dir}/abc-https/server.abc-https.demo.tetrate.io-key.pem" \
    "${certs_base_dir}/abc-https/server.abc-https.demo.tetrate.io-cert.pem" \
    "gateway-abc" ;
  generate_kubernetes_ingress_secret_https \
    "${GITEA_REPOS_DIR}/app-abc/k8s/standby/00-ingress-https-secret.yaml" \
    "abc-https-cert" \
    "${certs_base_dir}/abc-https/server.abc-https.demo.tetrate.io-key.pem" \
    "${certs_base_dir}/abc-https/server.abc-https.demo.tetrate.io-cert.pem" \
    "gateway-abc" ;
  # MTLS SERVER
  generate_server_cert "${certs_base_dir}" "abc-mtls" ;
  generate_client_cert "${certs_base_dir}" "abc-mtls" ;
  generate_kubernetes_ingress_secret_mtls \
    "${GITEA_REPOS_DIR}/app-abc/k8s/mgmt/00-tier1-mtls-secret.yaml" \
    "abc-mtls-cert" \
    "${certs_base_dir}/abc-mtls/server.abc-mtls.demo.tetrate.io-key.pem" \
    "${certs_base_dir}/abc-mtls/server.abc-mtls.demo.tetrate.io-cert.pem" \
    "${certs_base_dir}/root-cert.pem" \
    "tier1-abc" ;
  generate_kubernetes_ingress_secret_mtls \
    "${GITEA_REPOS_DIR}/app-abc/k8s/active/00-ingress-mtls-secret.yaml" \
    "abc-mtls-cert" \
    "${certs_base_dir}/abc-mtls/server.abc-mtls.demo.tetrate.io-key.pem" \
    "${certs_base_dir}/abc-mtls/server.abc-mtls.demo.tetrate.io-cert.pem" \
    "${certs_base_dir}/root-cert.pem" \
    "gateway-abc" ;
  generate_kubernetes_ingress_secret_mtls \
    "${GITEA_REPOS_DIR}/app-abc/k8s/standby/00-ingress-mtls-secret.yaml" \
    "abc-mtls-cert" \
    "${certs_base_dir}/abc-mtls/server.abc-mtls.demo.tetrate.io-key.pem" \
    "${certs_base_dir}/abc-mtls/server.abc-mtls.demo.tetrate.io-cert.pem" \
    "${certs_base_dir}/root-cert.pem" \
    "gateway-abc" ;


  ecr_repo_region=$(jq -r '.ecr.region' ${AWS_ENV_FILE}) ;
  ecr_repository_url=$(get_ecr_repository_url "${AWS_PROFILE}" "${ecr_repo_region}") ;

  # Create and synchronize gitea repos and deploy argocd applications
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${AWS_ENV_FILE}) ;
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    
    case ${cluster_tsb_type} in
      "mp")
        # Create gitea repos and sync local code to them
        create_and_sync_gitea_repos "${cluster_kubeconfig}" "${ecr_repository_url}" ;

        # Deploy argocd applications
        deploy_argocd_applications "${cluster_kubeconfig}" "${cluster_name}" "${gitea_public_url}" ;
        ;;
      "cp")
        # Deploy argocd applications
        deploy_argocd_applications "${cluster_kubeconfig}" "${cluster_name}" "${gitea_public_url}" ;
        ;;
      *)
        print_warning "Unknown tsb cluster type '${cluster_tsb_type}'" ;
        continue ;
        ;;
    esac
  done

  exit 0 ;
fi

if [[ ${ACTION} = "undeploy" ]]; then

  exit 0 ;
fi

if [[ ${ACTION} = "info" ]]; then

  certs_base_dir="${ROOT_DIR}/output/certs" ;

  mp_kubeconfig=$(jq -r '.eks.clusters[] | select(.name=="mgmt").kubeconfig' ${AWS_ENV_FILE}) ;
  echo -n "Waiting for Tier1 Gateway external hostname address of AppABC in mgmt cluster: " ;
  while ! appabc_tier1_hostname=$(kubectl --kubeconfig ${mp_kubeconfig} get svc -n tier1-abc gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ; do
    echo -n "." ; sleep 1 ;
  done
  echo "DONE" ;
  appabc_tier1_ip=$(host ${appabc_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;

  cp_kubeconfig=$(jq -r '.eks.clusters[] | select(.name=="active").kubeconfig' ${AWS_ENV_FILE}) ;
  echo -n "Waiting for Ingress Gateway external hostname address of AppABC in active cluster: " ;
  while ! appabc_ingress_hostname=$(kubectl --kubeconfig ${cp_kubeconfig} get svc -n gateway-abc gw-ingress-abc --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ; do
    echo -n "." ; sleep 1 ;
  done
  echo "DONE" ;
  appabc_ingress_ip=$(host ${appabc_ingress_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;

  print_info "appabc_tier1_hostname (mgmt cluster): ${appabc_tier1_hostname}" ;
  print_info "appabc_tier1_ip (mgmt cluster): ${appabc_tier1_ip}" ;
  print_info "appabc_ingress_hostname (active cluster): ${appabc_ingress_hostname}" ;
  print_info "appabc_ingress_ip (active cluster): ${appabc_ingress_ip}" ;
  echo ;
  echo ;
  echo "HTTP Traffic to Application ABC through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:80:${appabc_tier1_ip}\" --url \"http://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  echo "HTTPS Traffic to Application ABC through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc-https.demo.tetrate.io:443:${appabc_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://abc-https.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  echo "MTLS Traffic to Application ABC through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc-mtls.demo.tetrate.io:443:${appabc_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/abc-mtls/client.abc-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/abc-mtls/client.abc-mtls.demo.tetrate.io-key.pem --url \"https://abc-mtls.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  echo ;
  echo "HTTP Traffic to Application ABC through Ingress in active cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:80:${appabc_ingress_ip}\" --url \"http://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  echo "HTTPS Traffic to Application ABC through Ingress in active cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc-https.demo.tetrate.io:443:${appabc_ingress_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://abc-https.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  echo "MTLS Traffic to Application ABC through Ingress in active cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc-mtls.demo.tetrate.io:443:${appabc_ingress_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/abc-mtls/client.abc-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/abc-mtls/client.abc-mtls.demo.tetrate.io-key.pem --url \"https://abc-mtls.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;

  exit 0 ;
fi

echo "Please specify correct action:" ;
echo "  - deploy" ;
echo "  - undeploy" ;
echo "  - info" ;
exit 1 ;
