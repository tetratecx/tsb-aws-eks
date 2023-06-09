#!/usr/bin/env bash
ROOT_DIR="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )" ;
source ${ROOT_DIR}/helpers.sh ;
ENV_FILE=${ROOT_DIR}/env_aws.json ;

# Environment settings parsing
AWS_PROFILE=$(cat ${ENV_FILE} | jq -r ".profile") ;
AWS_RESOURCE_PREFIX=$(cat ${ENV_FILE} | jq -r ".resource_prefix") ;

ACTION=${1} ;

# Start an eks based kubernetes cluster
#   args:
#     (1) cluster json configuration
#   example:
#      {
#        "kubeconfig": "output/active-kubeconfig.yaml",
#        "name": "active",
#        "node_type": "m5.xlarge",
#        "nodes_max": 5,
#        "nodes_min": 3,
#        "region": "eu-west-1",
#        "tags": "tetrate:owner=bart,tetrate:team=sales:se,tetrate:purpose=poc,tetrate:lifespan=ongoing,tetrate:customer=coindcx",
#        "version": "1.25",
#        "vpc_cidr": "10.20.0.0/16"
#      }
#
function start_eks_cluster {
  [[ -z "${1}" ]] && print_error "Please provide cluster json configuration as 1st argument" && return 2 || local json_config="${1}" ;

  local cluster_kubeconfig=$(echo ${json_config} | jq -r '.kubeconfig') ;
  local cluster_name=$(echo ${json_config} | jq -r '.name') ;
  local cluster_node_type=$(echo ${json_config} | jq -r '.node_type') ;
  local cluster_nodes_max=$(echo ${json_config} | jq -r '.nodes_max') ;
  local cluster_nodes_min=$(echo ${json_config} | jq -r '.nodes_min') ;
  local cluster_region=$(echo ${json_config} | jq -r '.region') ;
  local cluster_tags=$(echo ${json_config} | jq -r '.tags') ;
  local cluster_version=$(echo ${json_config} | jq -r '.version') ;
  local cluster_vpc_cidr=$(echo ${json_config} | jq -r '.vpc_cidr') ;

  if $(eksctl get cluster ${cluster_name} --region ${cluster_region} --profile "${AWS_PROFILE}" -o json | jq -r ".[].Status" | grep "ACTIVE" &>/dev/null); then
    echo "Cluster '${cluster_name}' in region '${cluster_region}' already running" ;
  else
    echo "Create cluster '${cluster_name}' in region '${cluster_region}'" ;
    eksctl create cluster \
      --asg-access \
      --external-dns-access \
      --instance-prefix "${AWS_RESOURCE_PREFIX}" \
      --kubeconfig "${ROOT_DIR}/${cluster_kubeconfig}" \
      --name "${cluster_name}" \
      --node-type "${cluster_node_type}" \
      --nodes ${cluster_nodes_min} \
      --nodes-max ${cluster_nodes_max} \
      --nodes-min ${cluster_nodes_min} \
      --profile "${AWS_PROFILE}" \
      --region "${cluster_region}" \
      --ssh-access \
      --tags "${cluster_tags}" \
      --version "${cluster_version}" \
      --vpc-cidr "${cluster_vpc_cidr}" ;
  fi
}

# Enable EBS CSI driver for persistent volume claims
#   args:
#     (1) cluster name
#     (2) cluster region
function enable_ebs_csi_driver {
  [[ -z "${1}" ]] && print_error "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster region as 2nd argument" && return 2 || local cluster_region="${2}" ;

  if $(aws iam list-open-id-connect-providers --profile "${AWS_PROFILE}" \
        | grep $(aws eks describe-cluster \
                  --name "${cluster_name}" \
                  --output text \
                  --profile "${AWS_PROFILE}" \
                  --query "cluster.identity.oidc.issuer" \
                  --region "${cluster_region}" | cut -d '/' -f 5) &>/dev/null); then
    echo "Cluster '${cluster_name}' in region '${cluster_region}' already has an iam-oidc-provider associated"
  else
    eksctl utils associate-iam-oidc-provider \
      --approve \
      --cluster "${cluster_name}" \
      --profile "${AWS_PROFILE}" \
      --region "${cluster_region}" ;
  fi

  if $(eksctl get iamserviceaccount \
        --cluster "${cluster_name}" \
        --name "ebs-csi-controller-sa" \
        --profile "${AWS_PROFILE}" \
        --region "${cluster_region}" | grep "No iamserviceaccounts found" &>/dev/null); then
    eksctl create iamserviceaccount \
      --approve \
      --attach-policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" \
      --cluster "${cluster_name}" \
      --name "ebs-csi-controller-sa" \
      --namespace "kube-system" \
      --profile "${AWS_PROFILE}" \
      --region "${cluster_region}" \
      --role-name "eksctl-${cluster_name}-${cluster_region}-EbsCsiDriverRole" \
      --role-only ;
  else
    echo "Cluster '${cluster_name}' in region '${cluster_region}' already has an iamserviceaccount 'eksctl-${cluster_name}-${cluster_region}-EbsCsiDriverRole' created" ;
    
  fi

  if $(eksctl get addon \
        --cluster "${cluster_name}" \
        --name "aws-ebs-csi-driver" \
        --profile "${AWS_PROFILE}" \
        --region "${cluster_region}" &>/dev/null); then
    echo "Cluster '${cluster_name}' in region '${cluster_region}' already has addon 'aws-ebs-csi-driver' enabled" ;
  else
    eksctl create addon \
      --cluster "${cluster_name}" \
      --force \
      --name "aws-ebs-csi-driver" \
      --profile "${AWS_PROFILE}" \
      --region "${cluster_region}" \
      --service-account-role-arn "arn:aws:iam::$(aws sts get-caller-identity \
                                                  --output text \
                                                  --profile ${AWS_PROFILE} \
                                                  --query Account):role/eksctl-${cluster_name}-${cluster_region}-EbsCsiDriverRole" ;
  fi
}

# Delete an eks based kubernetes cluster
#   args:
#     (1) cluster json configuration
#   example:
#      {
#        "kubeconfig": "output/active-kubeconfig.yaml",
#        "name": "active",
#        "region": "eu-west-1",
#      }
#
function delete_eks_cluster {
  [[ -z "${1}" ]] && print_error "Please provide cluster json configuration as 1st argument" && return 2 || local json_config="${1}" ;

  local cluster_kubeconfig=$(echo ${json_config} | jq -r '.kubeconfig') ;
  local cluster_name=$(echo ${json_config} | jq -r '.name') ;
  local cluster_region=$(echo ${json_config} | jq -r '.region') ;

  echo "Delete cluster '${cluster_name}' in region '${cluster_region}'" ;
  eksctl delete cluster \
    --name "${cluster_name}" \
    --profile "${AWS_PROFILE}" \
    --region "${cluster_region}" ;
  rm -f "${ROOT_DIR}/${cluster_kubeconfig}" ;
}

# Delete IAM Service Account of EBS CSI driver for persistent volume claims
#   args:
#     (1) cluster name
#     (2) cluster region
function delete_iamserviceaccount {
  [[ -z "${1}" ]] && print_error "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster region as 2nd argument" && return 2 || local cluster_region="${2}" ;

  echo "Delete iamserviceaccount 'ebs-csi-controller-sa' of cluster '${cluster_name}' in region '${cluster_region}'" ;
  eksctl delete iamserviceaccount \
    --cluster "${cluster_name}" \
    --name "ebs-csi-controller-sa" \
    --namespace "kube-system" \
    --profile "${AWS_PROFILE}" \
    --region "${cluster_region}" ;
}


if [[ ${ACTION} = "login" ]]; then

  if ! $(aws sts get-caller-identity --profile ${AWS_PROFILE} &>/dev/null); then
    print_info "Login to aws-cli as profile '${AWS_PROFILE}'"
    aws configure --profile ${AWS_PROFILE} ;
  fi

	if $(aws sts get-caller-identity --profile ${AWS_PROFILE} &>/dev/null); then
    print_info "Using aws-cli as profile '${AWS_PROFILE}' works"
  else
    print_error "Failed to access aws through aws-cli with profile '${AWS_PROFILE}'" ;
  fi

  exit 0 ;
fi

if [[ ${ACTION} = "up" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${ENV_FILE}) ;

  # Start eks clusters in parallel using eksctl in background task
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    start_eks_cluster "$(jq -r '.eks.clusters['${cluster_index}']' ${ENV_FILE})" &
    eksctl_pids[${cluster_index}]=$! ;
  done

  # Waiting for clusters started with eksctl to finish
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${ENV_FILE}) ;
    echo "Waiting for cluster '${cluster_name}' in region '${cluster_region}' to have started" ;
    wait ${eksctl_pids[${cluster_index}]} ;
  done

  # Enable ebs csi driver in cluster
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${ENV_FILE}) ;
    
    enable_ebs_csi_driver "${cluster_name}" "${cluster_region}" ;
  done

  # Verifying if clusters are successfully running and reachable
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${ENV_FILE}) ;
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${ENV_FILE}) ;

    if [[ ! -f "${ROOT_DIR}/${cluster_kubeconfig}" ]]; then
      echo "Writing kubeconfig file for cluster '${cluster_name}' in region '${cluster_region}' to '${ROOT_DIR}/${cluster_kubeconfig}'" ;
      eksctl utils write-kubeconfig \
        --cluster "${cluster_name}" \
        --kubeconfig "${ROOT_DIR}/${cluster_kubeconfig}" \
        --profile "${AWS_PROFILE}" \
        --region "${cluster_region}" ;
    fi

    if cluster_info_out=$(kubectl cluster-info --kubeconfig "${ROOT_DIR}/${cluster_kubeconfig}" 2>&1); then
      print_info "Cluster '${cluster_name}' running correctly in region '${cluster_region}'" ;
      print_info "Cluster '${cluster_name}' kubeconfig file: ${ROOT_DIR}/${cluster_kubeconfig}" ;
    else
      print_error "Cluster '${cluster_name}' is not running correctly in region '${cluster_region}'" ;
      print_error "Cluster '${cluster_name}' kubeconfig file: ${ROOT_DIR}/${cluster_kubeconfig}" ;
      print_error "${cluster_info_out}" ;
    fi
  done

  exit 0 ;
fi

if [[ ${ACTION} = "down" ]]; then

  cluster_count=$(jq '.eks.clusters | length' ${ENV_FILE}) ;

  # Delete iamserviceaccount for ebs csi driver in cluster
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${ENV_FILE}) ;

    delete_iamserviceaccount "${cluster_name}" "${cluster_region}" ;
  done

  # Delete eks clusters in parallel using eksctl in background task
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    delete_eks_cluster "$(jq -r '.eks.clusters['${cluster_index}']' ${ENV_FILE})" &
    eksctl_pids[${cluster_index}]=$! ;
  done

  # Waiting for clusters deleted with eksctl to finish
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${ENV_FILE}) ;
    echo "Waiting for cluster '${cluster_name}' in region '${cluster_region}' to be deleted" ;
    wait ${eksctl_pids[${cluster_index}]} ;
  done

  exit 0 ;
fi

if [[ ${ACTION} = "info" ]]; then
 
  cluster_count=$(jq '.eks.clusters | length' ${ENV_FILE}) ;
  for ((cluster_index=0; cluster_index<${cluster_count}; cluster_index++)); do
    cluster_kubeconfig=$(jq -r '.eks.clusters['${cluster_index}'].kubeconfig' ${ENV_FILE}) ;
    cluster_name=$(jq -r '.eks.clusters['${cluster_index}'].name' ${ENV_FILE}) ;
    cluster_region=$(jq -r '.eks.clusters['${cluster_index}'].region' ${ENV_FILE}) ;

    print_info "================================================== cluster ${cluster_name} ==================================================" ;
    print_command "kubectl --kubeconfig ${cluster_kubeconfig} get cluster-info" ;
    kubectl --kubeconfig ${cluster_kubeconfig} cluster-info ;
    echo ;
    print_command "kubectl --kubeconfig ${cluster_kubeconfig} get pods,svc -A" ;
    kubectl --kubeconfig ${cluster_kubeconfig} get pods,svc -A ;
  done

  exit 0 ;
fi

echo "Please specify correct action:" ;
echo "  - login" ;
echo "  - up" ;
echo "  - down" ;
echo "  - info" ;
exit 1 ;
