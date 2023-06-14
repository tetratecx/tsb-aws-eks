# Helper functions to start, remove and interact with AWS EKS kubernetes clusters
#



# Start an eks based kubernetes cluster
#   args:
#     (1) base directory (will prefix the kubeconfig output folder)
#     (2) aws profile
#     (3) aws resource prefix
#     (4) cluster json configuration
#   example:
#      {
#        "kubeconfig": "output/active-kubeconfig.yaml",
#        "name": "active",
#        "node_type": "m5.xlarge",
#        "nodes_max": 5,
#        "nodes_min": 3,
#        "region": "eu-west-1",
#        "tags": "tetrate:owner=bart,tetrate:team=sales:se,tetrate:purpose=poc,tetrate:lifespan=ongoing,tetrate:customer=coindcx",
#        "tsb_type": "cp",
#        "version": "1.25",
#        "vpc_cidr": "10.20.0.0/16"
#      }
#
function start_eks_cluster {
  [[ -z "${1}" ]] && print_error "Please provide base directory as 1st argument" && return 2 || local base_dir="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide aws profile as 2nd argument" && return 2 || local aws_profile="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide aws resource prefix as 3rd argument" && return 2 || local aws_prefix="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide cluster json configuration as 4th argument" && return 2 || local json_config="${4}" ;

  local cluster_kubeconfig=$(echo ${json_config} | jq -r '.kubeconfig') ;
  local cluster_name=$(echo ${json_config} | jq -r '.name') ;
  local cluster_node_type=$(echo ${json_config} | jq -r '.node_type') ;
  local cluster_nodes_max=$(echo ${json_config} | jq -r '.nodes_max') ;
  local cluster_nodes_min=$(echo ${json_config} | jq -r '.nodes_min') ;
  local cluster_region=$(echo ${json_config} | jq -r '.region') ;
  local cluster_tags=$(echo ${json_config} | jq -r '.tags') ;
  local cluster_version=$(echo ${json_config} | jq -r '.version') ;
  local cluster_vpc_cidr=$(echo ${json_config} | jq -r '.vpc_cidr') ;

  if $(eksctl get cluster ${cluster_name} --region ${cluster_region} --profile "${aws_profile}" -o json | jq -r ".[].Status" | grep "ACTIVE" &>/dev/null); then
    echo "EKS cluster '${cluster_name}' in region '${cluster_region}' already running" ;
  else
    echo "Create cluster '${cluster_name}' in region '${cluster_region}'" ;
    eksctl create cluster \
      --asg-access \
      --external-dns-access \
      --instance-prefix "${aws_prefix}" \
      --kubeconfig "${base_dir}/${cluster_kubeconfig}" \
      --name "${cluster_name}" \
      --node-type "${cluster_node_type}" \
      --nodes ${cluster_nodes_min} \
      --nodes-max ${cluster_nodes_max} \
      --nodes-min ${cluster_nodes_min} \
      --profile "${aws_profile}" \
      --region "${cluster_region}" \
      --ssh-access \
      --tags "${cluster_tags}" \
      --version "${cluster_version}" \
      --vpc-cidr "${cluster_vpc_cidr}" ;
  fi
}

# Delete an eks based kubernetes cluster
#   args:
#     (1) base directory (will prefix the kubeconfig output folder)
#     (2) aws profile
#     (3) cluster json configuration
#   example:
#      {
#        "kubeconfig": "output/active-kubeconfig.yaml",
#        "name": "active",
#        "region": "eu-west-1",
#      }
#
function delete_eks_cluster {
  [[ -z "${1}" ]] && print_error "Please provide base directory as 1st argument" && return 2 || local base_dir="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide aws profile as 2nd argument" && return 2 || local aws_profile="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cluster json configuration as 3rd argument" && return 2 || local json_config="${3}" ;

  local cluster_kubeconfig=$(echo ${json_config} | jq -r '.kubeconfig') ;
  local cluster_name=$(echo ${json_config} | jq -r '.name') ;
  local cluster_region=$(echo ${json_config} | jq -r '.region') ;

  echo "Delete cluster '${cluster_name}' in region '${cluster_region}'" ;
  eksctl delete cluster \
    --name "${cluster_name}" \
    --profile "${aws_profile}" \
    --region "${cluster_region}" ;
  rm -f "${base_dir}/${cluster_kubeconfig}" ;
}

# Wait for eks related cloudformation stacks to be completely deleted
#   args:
#     (1) aws profile
#     (2) cluster region
#     (3) cluster name
#     (4) timeout in seconds (optional, default '300')
function wait_eks_cloudformation_stacks_deleted {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster region configuration as 2nd argument" && return 2 || local cluster_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cluster name as 3rd argument" && return 2 || local cluster_name="${3}" ;
  [[ -z "${4}" ]] && local timeout="300" || local timeout="${4}" ;

  local count=0 ;
  echo -n "Waiting for eks related cloudformation stacks of cluster '${cluster_name}' in region '${cluster_region}' to be fully deleted: " ;
  while [[ $(aws cloudformation list-stacks \
    --profile "${aws_profile}" \
    --query "StackSummaries[?contains(StackName, '${cluster_name}')]" \
    --region "${cluster_region}" \
    --stack-status-filter "DELETE_IN_PROGRESS" "DELETE_FAILED" | jq '. | length') != "0" ]]; do
    echo -n "." ; sleep 1 ; count=$((count+1)) ;
    if [[ ${count} -ge ${timeout} ]] ; then print_error "Timeout exceeded while waiting for cloudformation stacks of cluster '${cluster_name}' in region '${cluster_region}' to be fully deleted" ; return 1 ; fi
  done
  echo "DONE" ;
}
