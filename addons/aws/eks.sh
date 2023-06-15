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
#     (4) timeout in seconds (optional, default '600')
function wait_eks_cloudformation_stacks_deleted {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster region configuration as 2nd argument" && return 2 || local cluster_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cluster name as 3rd argument" && return 2 || local cluster_name="${3}" ;
  [[ -z "${4}" ]] && local timeout="600" || local timeout="${4}" ;

  local count=0 ;
  echo -n "Waiting for DELETE_IN_PROGRESS cloudstacks of cluster '${cluster_name}' in region '${cluster_region}'" ;
  while [[ ! -z $(aws cloudformation list-stacks --region "${cluster_region}" --stack-status-filter "DELETE_IN_PROGRESS" --query "StackSummaries[?contains(StackName, 'eksctl-${cluster_name}')]|[].StackName" --output text) ]]; do
    echo -n "." ; sleep 1 ; count=$((count+1)) ;
    if [[ ${count} -ge ${timeout} ]] ; then print_error "Timeout (${timeout}) exceeded while waiting for cloudformation stacks of cluster '${cluster_name}' in region '${cluster_region}'" ; break ; fi
  done
  echo DONE ;

  echo "Check for DELETE_FAILED cloudstacks of cluster '${cluster_name}' in region '${cluster_region}'" ;
  for stackname in $(aws cloudformation list-stacks --region "${cluster_region}" --stack-status-filter "DELETE_FAILED" --query "StackSummaries[?contains(StackName, 'eksctl-${cluster_name}')]|[].StackName" --output text) ; do
    print_error "Failed to delete stack '${stackname}' in region '${cluster_region}'. Please cleanup manually!" ;
  done

  stacklist=$(aws cloudformation list-stacks --region "${cluster_region}" --stack-status-filter "DELETE_IN_PROGRESS" "DELETE_FAILED" --query "StackSummaries[?contains(StackName, 'eksctl-${cluster_name}')]|[].StackName" --output text) ;
  if [[ -z ${stacklist} ]]; then
    print_info "Successfully removed all cloudstacks of cluster '${cluster_name}' in region '${cluster_region}'" ;
  else
    print_error "Failed to remove all cloudstacks of cluster '${cluster_name}' in region '${cluster_region}': ${stacklist}" ;
  fi
}

# Clean up eks attached aws loadbalancers created by kubernetes services of type loadbalancer
#   args:
#     (1) aws profile
#     (2) cluster region
#     (3) kubeconfig file
function delete_all_eks_lbs {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster region as 2nd argument" && return 2 || local cluster_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide kubeconfig file as 3rd argument" && return 2 || local kubeconfig_file="${3}" ;

  # First delete all the operators so services are not being recreated
  for namespace in $(kubectl --kubeconfig ${kubeconfig_file} get namespaces -o custom-columns=:metadata.name) ; do
    for operator in $(kubectl --kubeconfig ${kubeconfig_file} get deployments -n ${namespace} -o custom-columns=:metadata.name | grep operator); do
      kubectl --kubeconfig ${kubeconfig_file} delete deployment ${operator} -n ${namespace} --timeout=10s --wait=false ;
      sleep 0.5 ;
    done
  done

  # Use the public DNS/Hostname of the loadbalancer to determine the name/arn to delete
  kubectl --kubeconfig ${kubeconfig_file} get svc -A | grep "LoadBalancer" \
    | awk '{print "lb_namespace=" $1 " ; lb_service=" $2 " ; lb_dns=" $5 }' \
    | while read set_vars ; do 
  
    eval ${set_vars} ;
  
    # Delete kubernetes service object to prevent loadbalancer recreation
    echo "Delete kubernetes service '${lb_service}' of type loadbalancer in namespace '${lb_namespace}'"
    kubectl --kubeconfig ${kubeconfig_file} delete svc ${lb_service} -n ${lb_namespace} 2>/dev/null ;

    # Delete classic Type LB
    lb_name=$(aws elb describe-load-balancers --profile "${aws_profile}" \
                    --query "LoadBalancerDescriptions[?DNSName=='${lb_dns}']|[].LoadBalancerName" \
                    --region "${cluster_region}" --output text 2>/dev/null) ;
    if [[ ! -z "${lb_name}" ]]; then
      echo "Delete classic type loadbalancer with name '${lb_name}' in region '${cluster_region}'" ;
      aws elb delete-load-balancer --load-balancer-name "${lb_name}" --profile "${aws_profile}" --region "${cluster_region}" ;
      continue ;
    fi

    #  Delete new Type LB (eg Network)
    lb_arn=$(aws elbv2 describe-load-balancers --profile "${aws_profile}" \
                    --query "LoadBalancers[?DNSName=='${lb_dns}']|[].LoadBalancerArn" \
                    --region "${cluster_region}" --output text 2>/dev/null) ;
    if [[ ! -z "${lb_arn}" ]]; then
      echo "Delete new type loadbalancer with arn '${lb_arn}' in region '${cluster_region}'" ;
      aws elbv2 delete-load-balancer --load-balancer-arn "${lb_arn}" --profile "${aws_profile}" --region "${cluster_region}" ;
      continue ;
    fi

    print_warning "Did not find a matching LoadBalancer (classic or new type) for DNS '${lb_dns}' in region '${cluster_region}'" ;
  done
}
