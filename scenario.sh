#!/usr/bin/env bash
readonly ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
source ${ROOT_DIR}/addons/aws/ecr.sh ;
source ${ROOT_DIR}/addons/aws/eks.sh ;
source ${ROOT_DIR}/addons/helm/argocd.sh ;
source ${ROOT_DIR}/addons/helm/gitea.sh ;

readonly AWS_ENV_FILE=${ROOT_DIR}/env_aws.json ;
readonly ARGOCD_APPS_DIR="${ROOT_DIR}/argocd-apps" ;
readonly GITEA_REPOS_DIR="${ROOT_DIR}/gitea-repos" ;
readonly GITEA_REPOS_CONFIG="${GITEA_REPOS_DIR}/repos.json" ;

readonly AWS_API_USER=$(cat ${AWS_ENV_FILE} | jq -r ".api_user") ;
readonly AWS_PROFILE=$(cat ${AWS_ENV_FILE} | jq -r ".profile") ;

readonly ACTION=${1} ;

  # Repo synchronization using git clone, add, commit and push
#   args:
#     (1) mp kubeconfig cluster context
#     (2) ecr repo url
function create_and_sync_gitea_repos {
  [[ -z "${1}" ]] && print_error "Please provide mp kubeconfig cluster context as 1st argument" && return 2 || local mp_cluster_context="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide ecr repo url as 2nd argument" && return 2 || local ecr_repo_url="${2}" ;

  local gitea_http_url=$(gitea_get_http_url "${mp_cluster_context}") ;
  local gitea_http_url_creds=$(gitea_get_http_url_with_credentials "${mp_cluster_context}") ;

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

  # Deploy argcd applications
#   args:
#     (1) kubeconfig cluster context
#     (2) cluster name
#     (3) gitea public url
function deploy_argocd_applications {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig cluster context as 1st argument" && return 2 || local cluster_context="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide gitea public url as 3rd argument" && return 2 || local gitea_url="${3}" ;

  print_info "Deploying argocd applications in cluster '${cluster_name}' from gitea url '${gitea_url}'" ;
  export GITEA_PUBLIC_URL="${gitea_url}" ;
  
  for yaml_file in ${ARGOCD_APPS_DIR}/${cluster_name}/*.yaml ; do
    envsubst < ${yaml_file} | kubectl --context ${cluster_context} apply -f - ;
  done
}

if [[ ${ACTION} = "deploy" ]]; then

  # Get public gitea url
  mp_cluster_name=$(jq -r '.eks.clusters[] | select(.tsb_type=="mp").name' ${AWS_ENV_FILE}) ;
  mp_cluster_region=$(jq -r '.eks.clusters[] | select(.tsb_type=="mp").region' ${AWS_ENV_FILE}) ;
  mp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${mp_cluster_name}" "${mp_cluster_region}") ;

  gitea_public_url=$(gitea_get_http_url ${mp_cluster_context}) ;

  ecr_repo_region=$(jq -r '.ecr.region' ${AWS_ENV_FILE}) ;
  ecr_repository_url=$(get_ecr_repository_url "${AWS_PROFILE}" "${ecr_repo_region}") ;

  # Create and synchronize gitea repos and deploy argocd applications
  cluster_count=$(jq '.eks.clusters | length' ${AWS_ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${AWS_ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${AWS_ENV_FILE}) ;
    cluster_tsb_type=$(jq -r '.eks.clusters['${cluster_index}'].tsb_type' ${AWS_ENV_FILE}) ;
    cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${cluster_name}" "${cluster_region}") ;
    
    case ${cluster_tsb_type} in
      "mp")
        # Create gitea repos and sync local code to them
        create_and_sync_gitea_repos "${cluster_context}" "${ecr_repository_url}" ;

        # Deploy argocd applications
        deploy_argocd_applications "${cluster_context}" "${cluster_name}" "${gitea_public_url}" ;
        ;;
      "cp")
        # Deploy argocd applications
        deploy_argocd_applications "${cluster_context}" "${cluster_name}" "${gitea_public_url}" ;
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

  certs_base_dir="${ROOT_DIR}/certs" ;

  mp_cluster_name=$(jq -r '.eks.clusters[] | select(.tsb_type=="mp").name' ${AWS_ENV_FILE}) ;
  mp_cluster_region=$(jq -r '.eks.clusters[] | select(.tsb_type=="mp").region' ${AWS_ENV_FILE}) ;
  mp_cluster_context=$(get_eks_cluster_context "${AWS_API_USER}" "${mp_cluster_name}" "${mp_cluster_region}") ;

  echo -n "Waiting for Tier1 Gateway external hostname address of AppABC in mgmt cluster: " ;
  while ! appabc_tier1_hostname=$(kubectl --context ${mp_cluster_context} get svc -n tier1-abc gw-tier1-abc --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ; do
    echo -n "." ; sleep 1 ;
  done
  echo "DONE" ;
  echo -n "Waiting for Tier1 Gateway external hostname address of AppDEF in mgmt cluster: " ;
  while ! appdef_tier1_hostname=$(kubectl --context ${mp_cluster_context} get svc -n tier1-def gw-tier1-def --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ; do
    echo -n "." ; sleep 1 ;
  done
  echo "DONE" ;
  echo -n "Waiting for Tier1 Gateway external hostname address of AppGHI in mgmt cluster: " ;
  while ! appghi_tier1_hostname=$(kubectl --context ${mp_cluster_context} get svc -n tier1-ghi gw-tier1-ghi --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ; do
    echo -n "." ; sleep 1 ;
  done
  echo "DONE" ;
  echo -n "Waiting for Tier1 Gateway external hostname address of AppLambda in mgmt cluster: " ;
  while ! applambda_tier1_hostname=$(kubectl --context ${mp_cluster_context} get svc -n tier1-lambda gw-tier1-lambda --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ; do
    echo -n "." ; sleep 1 ;
  done
  echo "DONE" ;

  echo -n "Waiting for Tier1 Gateway external hostname address of AppABC in mgmt cluster to resolve into an ip address: " ;
  appabc_tier1_ip=$(host ${appabc_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;
  while [[ -z "${appabc_tier1_ip}" ]] ; do
    echo -n "." ; sleep 1 ;
    appabc_tier1_ip=$(host ${appabc_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;
  done
  echo "DONE" ;
  echo -n "Waiting for Tier1 Gateway external hostname address of AppDEF in mgmt cluster to resolve into an ip address: " ;
  appdef_tier1_ip=$(host ${appdef_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;
  while [[ -z "${appdef_tier1_ip}" ]] ; do
    echo -n "." ; sleep 1 ;
    appdef_tier1_ip=$(host ${appdef_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;
  done
  echo "DONE" ;
  echo -n "Waiting for Tier1 Gateway external hostname address of AppGHI in mgmt cluster to resolve into an ip address: " ;
  appghi_tier1_ip=$(host ${appghi_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;
  while [[ -z "${appghi_tier1_ip}" ]] ; do
    echo -n "." ; sleep 1 ;
    appghi_tier1_ip=$(host ${appghi_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;
  done
  echo "DONE" ;
  echo -n "Waiting for Tier1 Gateway external hostname address of AppLambda in mgmt cluster to resolve into an ip address: " ;
  applambda_tier1_ip=$(host ${applambda_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;
  while [[ -z "${applambda_tier1_ip}" ]] ; do
    echo -n "." ; sleep 1 ;
    applambda_tier1_ip=$(host ${applambda_tier1_hostname} | awk '/has address/ { print $4 }' | head -1 ) ;
  done
  echo "DONE" ;

  echo ;
  print_info "appabc_tier1_hostname (mgmt cluster): ${appabc_tier1_hostname}" ;
  print_info "appabc_tier1_ip (mgmt cluster): ${appabc_tier1_ip}" ;
  print_info "appdef_tier1_hostname (mgmt cluster): ${appdef_tier1_hostname}" ;
  print_info "appdef_tier1_ip (mgmt cluster): ${appdef_tier1_ip}" ;
  print_info "appghi_tier1_hostname (mgmt cluster): ${appghi_tier1_hostname}" ;
  print_info "appghi_tier1_ip (mgmt cluster): ${appghi_tier1_ip}" ;
  print_info "applambda_tier1_hostname (mgmt cluster): ${applambda_tier1_hostname}" ;
  print_info "applambda_tier1_ip (mgmt cluster): ${applambda_tier1_ip}" ;
  echo ;
  
  echo ;
  print_info "HTTP Traffic to Application ABC through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc.demo.tetrate.io:80:${appabc_tier1_ip}\" --url \"http://abc.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  print_info "HTTPS Traffic to Application ABC through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc-https.demo.tetrate.io:443:${appabc_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://abc-https.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  print_info "MTLS Traffic to Application ABC through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"abc-mtls.demo.tetrate.io:443:${appabc_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/abc-mtls/client.abc-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/abc-mtls/client.abc-mtls.demo.tetrate.io-key.pem --url \"https://abc-mtls.demo.tetrate.io/proxy/app-b.ns-b/proxy/app-c.ns-c\"" ;
  echo ;
  
  echo ;
  print_info "HTTP Traffic to Application DEF through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def.demo.tetrate.io:80:${appdef_tier1_ip}\" --url \"http://def.demo.tetrate.io/proxy/app-e.ns-e/proxy/ifconfig.me\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def.demo.tetrate.io:80:${appdef_tier1_ip}\" --url \"http://def.demo.tetrate.io/proxy/app-f.ns-f/proxy/ifconfig.me\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def.demo.tetrate.io:80:${appdef_tier1_ip}\" --url \"http://def.demo.tetrate.io/proxy/app-e.ns-e/proxy/ipinfo.io\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def.demo.tetrate.io:80:${appdef_tier1_ip}\" --url \"http://def.demo.tetrate.io/proxy/app-f.ns-f/proxy/ipinfo.io\"" ;
  echo ;
  print_info "HTTPS Traffic to Application DEF through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def-https.demo.tetrate.io:443:${appdef_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://def-https.demo.tetrate.io/proxy/app-e.ns-e/proxy/ifconfig.me\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def-https.demo.tetrate.io:443:${appdef_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://def-https.demo.tetrate.io/proxy/app-f.ns-f/proxy/ifconfig.me\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def-https.demo.tetrate.io:443:${appdef_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://def-https.demo.tetrate.io/proxy/app-e.ns-e/proxy/ipinfo.io\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def-https.demo.tetrate.io:443:${appdef_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://def-https.demo.tetrate.io/proxy/app-f.ns-f/proxy/ipinfo.io\"" ;
  echo ;
  print_info "MTLS Traffic to Application DEF through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def-mtls.demo.tetrate.io:443:${appdef_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/def-mtls/client.def-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/def-mtls/client.def-mtls.demo.tetrate.io-key.pem --url \"https://def-mtls.demo.tetrate.io/proxy/app-e.ns-e/proxy/ifconfig.me\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def-mtls.demo.tetrate.io:443:${appdef_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/def-mtls/client.def-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/def-mtls/client.def-mtls.demo.tetrate.io-key.pem --url \"https://def-mtls.demo.tetrate.io/proxy/app-f.ns-f/proxy/ifconfig.me\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def-mtls.demo.tetrate.io:443:${appdef_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/def-mtls/client.def-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/def-mtls/client.def-mtls.demo.tetrate.io-key.pem --url \"https://def-mtls.demo.tetrate.io/proxy/app-e.ns-e/proxy/ipinfo.io\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"def-mtls.demo.tetrate.io:443:${appdef_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/def-mtls/client.def-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/def-mtls/client.def-mtls.demo.tetrate.io-key.pem --url \"https://def-mtls.demo.tetrate.io/proxy/app-f.ns-f/proxy/ipinfo.io\"" ;
  echo ;
  
  echo ;
  print_info "HTTP Traffic to Application GHI through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"ghi.demo.tetrate.io:80:${appghi_tier1_ip}\" --url \"http://ghi.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --user "alice:password" --resolve \"ghi.demo.tetrate.io:80:${appghi_tier1_ip}\" --url \"http://ghi.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --user "bob:password" --resolve \"ghi.demo.tetrate.io:80:${appghi_tier1_ip}\" --url \"http://ghi.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  echo ;
  print_info "HTTPS Traffic to Application GHI through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"ghi-https.demo.tetrate.io:443:${appghi_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://ghi-https.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --user "alice:password"  --resolve \"ghi-https.demo.tetrate.io:443:${appghi_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://ghi-https.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --user "bob:password"  --resolve \"ghi-https.demo.tetrate.io:443:${appghi_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://ghi-https.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  echo ;
  print_info "MTLS Traffic to Application GHI through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"ghi-mtls.demo.tetrate.io:443:${appghi_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/ghi-mtls/client.ghi-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/ghi-mtls/client.ghi-mtls.demo.tetrate.io-key.pem --url \"https://ghi-mtls.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --user "alice:password"  --resolve \"ghi-mtls.demo.tetrate.io:443:${appghi_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/ghi-mtls/client.ghi-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/ghi-mtls/client.ghi-mtls.demo.tetrate.io-key.pem --url \"https://ghi-mtls.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --user "bob:password"  --resolve \"ghi-mtls.demo.tetrate.io:443:${appghi_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/ghi-mtls/client.ghi-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/ghi-mtls/client.ghi-mtls.demo.tetrate.io-key.pem --url \"https://ghi-mtls.demo.tetrate.io/proxy/app-h.ns-h/proxy/app-i.ns-i\"" ;
  echo ;
  
  echo ;
  print_info "HTTP Traffic to Application Lambda through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"lambda.demo.tetrate.io:80:${applambda_tier1_ip}\" --url \"http://lambda.demo.tetrate.io\"" ;
  echo ;
  print_info "HTTPS Traffic to Application Lambda through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"lambda-https.demo.tetrate.io:443:${applambda_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --url \"https://lambda-https.demo.tetrate.io\"" ;
  echo ;
  print_info "MTLS Traffic to Application Lambda through Tier1 in mgmt cluster" ;
  print_command "curl -v -H \"X-B3-Sampled: 1\" --resolve \"lambda-mtls.demo.tetrate.io:443:${applambda_tier1_ip}\" --cacert ${certs_base_dir}/root-cert.pem --cert ${certs_base_dir}/lambda-mtls/client.lambda-mtls.demo.tetrate.io-cert.pem --key ${certs_base_dir}/lambda-mtls/client.lambda-mtls.demo.tetrate.io-key.pem --url \"https://lambda-mtls.demo.tetrate.io\"" ;
  echo ;

  exit 0 ;
fi

echo "Please specify correct action:" ;
echo "  - deploy" ;
echo "  - undeploy" ;
echo "  - info" ;
exit 1 ;
