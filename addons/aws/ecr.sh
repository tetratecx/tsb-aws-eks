# Helper functions to start, remove and interact with AWS ECR docker repositories
#


# Start ECR repository
#   args:
#     (1) aws profile
#     (2) repository region
#     (3) repository name (equals image name on aws)
#     (4) repository tags
function start_ecr_repository {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository region as 2nd argument" && return 2 || local repo_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository name as 3rd argument" && return 2 || local repo_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide repository tags as 4th argument" && return 2 || local repo_tags="${4}" ;

  if $(aws ecr describe-repositories --profile "${aws_profile}" --region "${repo_region}" --repository-names "${repo_name}" &>/dev/null); then
    echo "ECR repository '${repo_name}' in region '${repo_region}' already running" ;
  else
    echo "Create ECR repository '${repo_name}' in region '${repo_region}'" ;
    aws ecr create-repository \
      --profile "${aws_profile}" \
      --region "${repo_region}" \
      --repository-name "${repo_name}" \
      --tags ${repo_tags} ;
  fi
}

# Delete ECR repository
#   args:
#     (1) aws profile
#     (2) repository region
#     (3) repository name (equals image name on aws)
function delete_ecr_repository {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository region as 2nd argument" && return 2 || local repo_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository name as 3rd argument" && return 2 || local repo_name="${3}" ;

  echo "Delete ECR repository '${repo_name}' in region '${repo_region}'" ;
  aws ecr delete-repository \
    --force \
    --repository-name "${repo_name}" \
    --region "${repo_region}" \
    --profile "${aws_profile}" ;
}


# Locally login to ECR docker repository
#   args:
#     (1) aws profile
#     (2) repository region
function docker_login_ecr {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository region as 2nd argument" && return 2 || local repo_region="${2}" ;

  aws ecr get-login-password \
    --profile "${aws_profile}" \
    --region "${repo_region}" -- | docker login \
        --username AWS \
        --password-stdin \
        "$(get_ecr_repository_url ${aws_profile} ${repo_region})" ;
}

# Get ECR repository URL
#   args:
#     (1) aws profile
#     (2) repository region
function get_ecr_repository_url {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository region as 2nd argument" && return 2 || local repo_region="${2}" ;

  local aws_account_id=$(aws sts get-caller-identity --output text --profile "${aws_profile}" --query "Account") ;
  echo "${aws_account_id}.dkr.ecr.${repo_region}.amazonaws.com" ;
}

# Get ECR repository URL
#   args:
#     (1) aws profile
#     (2) repository region
#     (3) repository name (equals image name on aws)
function get_ecr_repository_url_by_image_name {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository region as 2nd argument" && return 2 || local repo_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository name as 3rd argument" && return 2 || local repo_name="${3}" ;
  
  aws ecr describe-repositories \
    --output text \
    --profile "${aws_profile}" \
    --query "repositories[?repositoryName == '${repo_name}'].repositoryUri" \
    --region "${repo_region}" \
    --repository-names "${repo_name}" ;
}

# Check if image with tag exists in ecr repository
#   args:
#     (1) aws profile
#     (2) repository region
#     (3) image name
#     (4) image tag
function image_with_tag_available_in_ecr {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide ecr repository region as 2nd argument" && return 2 || local repo_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide ecr repository name as 3rd argument" && return 2 || local image_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide ecr repository name as 4th argument" && return 2 || local image_tag="${4}" ;

  aws ecr describe-images \
    --region ${repo_region} \
    --profile "${aws_profile}" \
    --repository-name ${image_name} \
    --image-ids imageTag=${image_tag} &>/dev/null ;
}

# Sync a given container image to ecr repository
#   args:
#     (1) aws profile
#     (2) repository region
#     (3) repository tags
#     (4) image full name (registry path, name and tag notation)
function sync_single_image_to_ecr {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide ecr repository region as 2nd argument" && return 2 || local repo_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide ecr repository tags as 3rd argument" && return 2 || local repo_tags="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide image as 4th argument" && return 2 || local image_full_name="${4}" ;

  local image_without_registry=$(echo ${image_full_name} | sed "s|containers.dl.tetrate.io/||") ;
  local image_name=$(echo ${image_without_registry} | awk -F: '{print $1}') ;
  local image_tag=$(echo ${image_without_registry} | awk -F: '{print $2}') ;

  if $(image_with_tag_available_in_ecr "${aws_profile}" "${repo_region}" "${image_name}" "${image_tag}") ; then
    echo "TSB image '${image_name}/${image_tag}' already available in ecr in region '${repo_region}'"
  else
    start_ecr_repository "${aws_profile}" "${repo_region}" "${image_name}" "${repo_tags}" ;
    image_repo=$(get_ecr_repository_url_by_image_name "${aws_profile}" "${repo_region}" "${image_name}") ;

    if ! docker image inspect ${image_full_name} &>/dev/null ; then
      docker pull ${image_full_name} ;
    fi
    if ! docker image inspect ${image_repo}/${image_tag} &>/dev/null ; then
      docker tag ${image_full_name} ${image_repo}:${image_tag} ;
    fi
    echo "Push TSB image '${image_repo}:${image_tag}' to ecr in region '${repo_region}'"
    docker push ${image_repo}:${image_tag} ;
  fi
}

# Sync tsb container images to ecr repositories (if not yet available)
#   args:
#     (1) aws profile
#     (2) repository region
#     (3) repository tags
function sync_tsb_images_to_ecr {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide ecr repository region as 2nd argument" && return 2 || local repo_region="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide ecr repository tags as 3rd argument" && return 2 || local repo_tags="${3}" ;
  echo "Going to sync tsb images to ecr repositories in region '${repo_region}'"

  # Make sure we are properly logged in to ecr
  docker_login_ecr "${aws_profile}" "${repo_region}" ;

  # Sync all tsb images to ecr repositories
  for image_full_name in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    sync_single_image_to_ecr "${aws_profile}" "${repo_region}" "${repo_tags}" "${image_full_name}" ;
  done

  # Sync images for application deployment and debugging to ecr repositories
  sync_single_image_to_ecr "${aws_profile}" "${repo_region}" "${repo_tags}" "containers.dl.tetrate.io/obs-tester-server:1.0" ;
  sync_single_image_to_ecr "${aws_profile}" "${repo_region}" "${repo_tags}" "containers.dl.tetrate.io/netshoot:latest" ;

  print_info "All tsb images synced and available in ecr repository in region '${repo_region}'" ;
}

# Delete all tsb related ecr docker repositories
#   args:
#     (1) aws profile
#     (2) repository region
function delete_tsb_ecr_repos {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide ecr repository region as 2nd argument" && return 2 || local repo_region="${2}" ;
  echo "Going to delete tsb ecr repositories in region '${repo_region}'"

  # Delete all tsb ecr repositories
  for image_full_name in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    local image_without_registry=$(echo ${image_full_name} | sed "s|containers.dl.tetrate.io/||") ;
    local image_name=$(echo ${image_without_registry} | awk -F: '{print $1}') ;
    delete_ecr_repository "${aws_profile}" "${repo_region}" "${image_name}" ;
  done

  # Delete application and debugging ecr repositories
  delete_ecr_repository "${aws_profile}" "${repo_region}" "obs-tester-server" ;
  delete_ecr_repository "${aws_profile}" "${repo_region}" "netshoot" ;

  print_info "All tsb ecr repositories deleted in region '${repo_region}'" ;
}