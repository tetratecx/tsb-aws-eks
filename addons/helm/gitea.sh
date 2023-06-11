# Helper functions to manage gitea (a lightweight git server)
# API Docs at https://try.gitea.io/api/swagger#
#

GITEA_ADMIN_PASSWORD="gitea-admin"
GITEA_ADMIN_USER="gitea-admin"
GITEA_HTTP_PORT=3000
GITEA_NAMESPACE="gitea"

# Deploy gitea server in kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'gitea')
#     (3) admin user (optional, default 'gitea-admin')
#     (4) admin password (optional, default 'gitea-admin')
function gitea_deploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${GITEA_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password="${GITEA_ADMIN_PASSWORD}" || local admin_password="${4}" ;

  helm repo add gitea-charts https://dl.gitea.io/charts/ ;
  helm repo update gitea-charts ;

  if $(helm status gitea --kubeconfig "${kubeconfig}" --namespace "${namespace}" &>/dev/null); then
    helm upgrade gitea gitea-charts/gitea \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set gitea.admin.email=${admin_user}@local.domain \
      --set gitea.admin.password=${admin_password} \
      --set gitea.admin.username=${admin_user} \
      --set service.http.type=LoadBalancer ;
    print_info "Upgraded helm chart for gitea" ;
  else
    helm install gitea gitea-charts/gitea \
      --create-namespace \
      --kubeconfig "${kubeconfig}" \
      --namespace "${namespace}" \
      --set gitea.admin.email=${admin_user}@local.domain \
      --set gitea.admin.password=${admin_password} \
      --set gitea.admin.username=${admin_user} \
      --set service.http.type=LoadBalancer ;
    print_info "Installed helm chart for gitea" ;
  fi
}

# Undeploy gitea from kubernetes using helm
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'gitea')
function gitea_undeploy {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;

  helm uninstall gitea \
    --kubeconfig "${kubeconfig}" \
    --namespace "${namespace}" ;
  print_info "Uninstalled helm chart for gitea" ;
}

# Get gitea server http url
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'gitea')
function gitea_get_http_url {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;

  local gitea_hostname=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" gitea-http -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${gitea_hostname}" ]]; then
    print_error "Service 'gitea-http' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${gitea_hostname}:${GITEA_HTTP_PORT}" ;
}

# Get gitea server http url with credentials
#   args:
#     (1) kubeconfig file
#     (2) namespace (optional, default 'gitea')
#     (3) admin user (optional, default 'gitea-admin')
#     (4) admin password (optional, default 'gitea-admin')
function gitea_get_http_url_with_credentials {
  [[ -z "${1}" ]] && print_error "Please provide kubeconfig file as 1st argument" && return 2 || local kubeconfig="${1}" ;
  [[ -z "${2}" ]] && local namespace="${GITEA_NAMESPACE}" || local namespace="${2}" ;
  [[ -z "${3}" ]] && local admin_user="${GITEA_ADMIN_USER}" || local admin_user="${3}" ;
  [[ -z "${4}" ]] && local admin_password="${GITEA_ADMIN_PASSWORD}" || local admin_password="${4}" ;

  local gitea_hostname=$(kubectl get svc --kubeconfig "${kubeconfig}" --namespace "${namespace}" gitea-http -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null) ;
  if [[ -z "${gitea_hostname}" ]]; then
    print_error "Service 'gitea-http' in namespace '${namespace}' has no ip address or is not running" ; 
    return 1 ;
  fi
  echo "http://${admin_user}:${admin_password}@${gitea_hostname}:${GITEA_HTTP_PORT}" ;
}

# Get gitea version
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_version {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/version" ;
}

# Wait for gitea api to be ready
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#     (3) timeout in seconds (optional, default '120')
function gitea_wait_api_ready {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;
  [[ -z "${3}" ]] && local timeout="120" || local timeout="${3}" ;

  local count=0 ;
  echo -n "Waiting for gitea rest api to become ready at url '${base_url}' (basic auth credentials '${basic_auth}'): "
  while ! $(gitea_get_version "${base_url}" "${basic_auth}" &>/dev/null); do
    echo -n "." ; sleep 1 ; count=$((count+1)) ;
    if [[ ${count} -ge ${timeout} ]] ; then print_error "Timeout exceeded while waiting for gitea api readiness" ; return 1 ; fi
  done
  echo "DONE" ;
}

# Check if gitea owner has repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository owner (can be a user or an organization)
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if repo exists (prints returned json)
#     - 1 : if repo does not exist
function gitea_has_repo_by_owner {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository owner as 3th argument" && return 2 || local repo_owner="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${4}" ;

  if result=$(curl --fail --silent --request GET --user "${basic_auth}" \
                --header 'Content-Type: application/json' \
                --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}" 2>/dev/null); then
    echo ${result} | jq ;
  else
    return 1 ;
  fi
}

# Create gitea repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository description
#     (4) repository private (optional, default 'false')
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_repo_current_user {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository description as 3th argument" && return 2 || local repo_description="${3}" ;
  [[ -z "${4}" ]] && local repo_private="false" || local repo_private="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;

  repo_owner=$(echo ${basic_auth} | cut -d ':' -f1)
  if $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    echo "Gitea repository '${repo_name}' with owner '${repo_owner}' already exists" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/user/repos" \
      -d "{ \"name\": \"${repo_name}\", \"description\": \"${repo_description}\", \"private\": ${repo_private}}" | jq ;
    print_info "Created repository '${repo_name}' with owner '${repo_owner}'" ;
  fi
}

# Create gitea repository in organization
#   args:
#     (1) api url
#     (2) organization name
#     (3) repository name
#     (4) repository description
#     (5) repository private (optional, default 'false')
#     (6) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_repo_in_org {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository name as 3th argument" && return 2 || local repo_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide repository description as 4th argument" && return 2 || local repo_description="${4}" ;
  [[ -z "${5}" ]] && local repo_private="false" || local repo_private="${5}" ;
  [[ -z "${6}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${6}" ;

  if $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    echo "Gitea repository '${repo_name}' in organization '${org_name}' already exists" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/orgs/${org_name}/repos" \
      -d "{ \"name\": \"${repo_name}\", \"description\": \"${repo_description}\", \"private\": ${repo_private}}" | jq ;
    print_info "Created repository '${repo_name}' in organization '${org_name}'" ;
  fi
}

# Delete gitea repository
#   args:
#     (1) api url
#     (2) repository owner (can be a user or an organization)
#     (3) repository name
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repository owner as 3th argument" && return 2 || local repo_owner="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository name as 2nd argument" && return 2 || local repo_name="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${4}" ;

  if $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    if result=$(curl --fail --silent --request DELETE --user "${basic_auth}" \
                    --header 'Content-Type: application/json' \
                    --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}" 2>/dev/null); then
      echo ${result} | jq ;
    else
      print_error "Failed to delete gitea repository '${repo_name}' with owner '${repo_owner}'" ;
      return 1 ;
    fi
    print_info "Deleted gitea repository '${repo_name}' with owner '${repo_owner}'" ;
  else
    echo "Gitea repository '${repo_name}' with owner '${repo_owner}' does not exists" ;
  fi
}

# Get gitea repository list (name only, without owner/org prefix)
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_repos_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/repos/search?limit=100" | jq -r '.data[].name' ;
}

# Get gitea repository full path list (includes owner/org prefix)
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_repos_full_name_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/repos/search?limit=100" | jq -r '.data[].full_name' ;
}

# Check if gitea organization exists
#   args:
#     (1) api url
#     (2) organization name
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if organization exists (prints returned json)
#     - 1 : if organization does not exist
function gitea_has_org {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${3}" ;

  if result=$(curl --fail --silent --request GET --user "${basic_auth}" \
                --header 'Content-Type: application/json' \
                --url "${base_url}/api/v1/orgs/${org_name}" 2>/dev/null); then
    echo ${result} | jq ;
  else
    return 1 ;
  fi
}

# Create gitea organization
#   args:
#     (1) api url
#     (2) organization name
#     (3) organization description
#     (4) organization visibility (optional, default 'public')
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_org {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide organization description as 3th argument" && return 2 || local org_description="${3}" ;
  [[ -z "${4}" ]] && local org_visibility="public" || local org_visibility="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;

  if $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null); then
    echo "Gitea organization '${org_name}' already exists" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/orgs" \
      -d "{ \"name\": \"${org_name}\", \"username\": \"${org_name}\", \"description\": \"${org_description}\", \"visibility\": \"${org_visibility}\"}" | jq ;
    print_info "Created organization '${org_name}' with username '${org_name}'" ;
  fi
}

# Delete gitea organization
#   args:
#     (1) api url
#     (2) organization name
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_org {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${3}" ;

  if $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null); then
    if result=$(curl --fail --silent --request DELETE --user "${basic_auth}" \
                    --header 'Content-Type: application/json' \
                    --url "${base_url}/api/v1/orgs/${org_name}" 2>/dev/null); then
      echo ${result} | jq ;
    else
      print_error "Failed to delete gitea organization '${org_name}'" ;
      return 1 ;
    fi
    print_info "Deleted gitea organization '${org_name}'" ;
  else
    echo "Gitea organization '${org_name}' does not exists" ;
  fi
}

# Get gitea organization list
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_org_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/orgs?limit=100" | jq -r '.[].name' ;
}

# Delete all gitea organizations
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_all_orgs {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  for org in $(gitea_get_org_list "${base_url}" "${basic_auth}"); do
    gitea_delete_org "${base_url}" "${org}" "${basic_auth}" ;
  done
}

# Delete all gitea repositories
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_all_repos {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  for repo_full_name in $(gitea_get_repos_full_name_list "${base_url}" "${basic_auth}"); do
    repo_owner=$(echo "${repo_full_name}" | cut -d '/' -f1) ;
    repo_name=$(echo "${repo_full_name}" | cut -d '/' -f2) ;
    gitea_delete_repo "${base_url}" "${repo_owner}" "${repo_name}" "${basic_auth}" ;
  done
}

# Check if gitea user exists
#   args:
#     (1) api url
#     (2) username
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if user exists (prints returned json)
#     - 1 : if user does not exist
function gitea_has_user {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${3}" ;

  if result=$(curl --fail --silent --request GET --user "${basic_auth}" \
                --header 'Content-Type: application/json' \
                --url "${base_url}/api/v1/users/${username}" 2>/dev/null); then
    echo ${result} | jq ;
  else
    return 1 ;
  fi
}

# Create gitea user
#   args:
#     (1) api url
#     (2) username
#     (3) password
#     (4) email (optional, default 'username@gitea.local')
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_user {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide password as 3rd argument" && return 2 || local password="${3}" ;
  [[ -z "${4}" ]] && local email="${username}@gitea.local" || local email="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;

  if $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    echo "Gitea user '${username}' already exists" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/admin/users" \
      -d "{ \"username\": \"${username}\", \"password\": \"${password}\", \"email\": \"${email}\", \"must_change_password\": false}" | jq ;
    print_info "Created user '${username}' with password '${password}' and email '${email}'" ;
  fi
}

# Delete gitea user
#   args:
#     (1) api url
#     (2) username
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_user {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide username as 2nd argument" && return 2 || local username="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${3}" ;

  if $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    if result=$(curl --fail --silent --request DELETE --user "${basic_auth}" \
                    --header 'Content-Type: application/json' \
                    --url "${base_url}/api/v1/admin/users/${username}" 2>/dev/null); then
      echo ${result} | jq ;
    else
      print_error "Failed to delete gitea user '${username}'" ;
      return 1 ;
    fi
    print_info "Deleted gitea user '${username}'" ;
  else
    print_error "Gitea user '${username}' does not exists" ;
  fi
}

# Get gitea user list
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_user_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/admin/users?limit=100" | jq -r '.[].username' ;
}

# Delete all gitea users
#   args:
#     (1) api url
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_all_users {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${2}" ;

  for user in $(gitea_get_user_list "${base_url}" "${basic_auth}"); do
    gitea_delete_user "${base_url}" "${user}" "${basic_auth}" ;
  done
}

# Check if gitea organization team exists
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
#   returns:
#     - 0 : if organization team exists (prints returned json)
#     - 1 : if organization team does not exist
function gitea_has_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${4}" ;

  if result=$(curl --fail --silent --request GET --user "${basic_auth}" \
                --header 'Content-Type: application/json' \
                --url "${base_url}/api/v1/orgs/${org_name}/teams" | \
                jq -e ".[] | select(.name==\"${team_name}\")" 2>/dev/null); then
    echo ${result} | jq ;
  else
    return 1 ;
  fi
}

# Create gitea organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) team description
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_create_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide team description as 4th argument" && return 2 || local team_description="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;

  if $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    echo "Gitea team '${team_name}' already exists in organization '${org_name}'" ;
  else
    curl --fail --silent --request POST --user "${basic_auth}" \
      --header 'Content-Type: application/json' \
      --url "${base_url}/api/v1/orgs/${org_name}/teams" \
      -d "{ \"name\": \"${team_name}\", \"organization\": \"${org_name}\", \"description\": \"${team_description}\", \"permission\": \"admin\"}" | jq ;
    print_info "Created team '${team_name}' in organization '${org_name}'" ;
  fi
}

# Delete gitea organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${4}" ;

  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  if team=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}"); then
    team_id=$(echo ${team} | jq ".id") ;
    if result=$(curl --fail --silent --request DELETE --user "${basic_auth}" \
                    --header 'Content-Type: application/json' \
                    --url "${base_url}/api/v1/teams/${team_id}" 2>/dev/null); then
      echo ${result} | jq ;
    else
      print_error "Failed to delete gitea team '${team_name}' (team_id=${team_id}) in organization '${org_name}'" ;
      return 1 ;
    fi
    print_info "Deleted gitea team '${team_name}' in organization '${org_name}'" ;
  else
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exists" ;
  fi
}

# Get gitea organization team list
#   args:
#     (1) api url
#     (2) organization name
#     (3) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_get_org_team_list {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${3}" ;

  curl --fail --silent --request GET --user "${basic_auth}" \
    --header 'Content-Type: application/json' \
    --url "${base_url}/api/v1/orgs/${org_name}/teams?limit=100" | jq -r '.[].name' ;
}

# Delete all gitea organization teams
#   args:
#     (1) api url
#     (2) organization name
#     (2) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_delete_all_org_teams {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${3}" ;

  for team in $(gitea_get_org_team_list "${base_url}" "${org_name}" "${basic_auth}"); do
    gitea_delete_org_team "${base_url}" "${org_name}" "${team}" "${basic_auth}" ;
  done
}

# Add gitea user as member to organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) username
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_add_user_to_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide username as 4th argument" && return 2 || local username="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;

  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea user '${username}' does not exist" ;
    return 1 ;
  fi

  team_id=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" | jq ".id") ;
  if (curl --fail --silent --request PUT --user "${basic_auth}" \
           --header 'Content-Type: application/json' \
           --url "${base_url}/api/v1/teams/${team_id}/members/${username}") ; then
    print_info "Added user '${username}' to team '${team_name} in organization '${org_name}'" ;
  else
    print_error "Failed to add user '${username}' to team '${team_name} in organization '${org_name}'" ;
  fi
}

# Remove gitea user as member from organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) username
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_remove_user_from_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide username as 4th argument" && return 2 || local username="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;

  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea user '${username}' does not exist" ;
    return 1 ;
  fi

  team_id=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" | jq ".id") ;
  if (curl --fail --silent --request DELETE --user "${basic_auth}" \
           --header 'Content-Type: application/json' \
           --url "${base_url}/api/v1/teams/${team_id}/members/${username}") ; then
    print_info "Removed user '${username}' from team '${team_name} in organization '${org_name}'" ;
  else
    print_error "Failed to remove user '${username}' from team '${team_name} in organization '${org_name}'" ;
  fi
}

# Add gitea repository to organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) repository name
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_add_repo_to_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide repository name as 4th argument" && return 2 || local repo_name="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  team_id=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" | jq ".id") ;
  if $(curl --fail --silent --request PUT --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/teams/${team_id}/repos/${org_name}/${repo_name}") ; then
    print_info "Added repository '${repo_name}' to team '${team_name} in organization '${org_name}'" ;
  else
    print_error "Failed to add repository '${repo_name}' to team '${team_name} in organization '${org_name}'" ;
  fi
}

# Remove gitea repository from organization team
#   args:
#     (1) api url
#     (2) organization name
#     (3) team name
#     (4) repository name
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_remove_repo_from_org_team {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide organization name as 2nd argument" && return 2 || local org_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide team name as 3rd argument" && return 2 || local team_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide repository name as 4th argument" && return 2 || local repo_name="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_org "${base_url}" "${org_name}" "${basic_auth}" &>/dev/null) ; then
    print_error "Gitea organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  team_id=$(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" | jq ".id") ;
  if $(curl --fail --silent --request DELETE --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/teams/${team_id}/repos/${org_name}/${repo_name}") ; then
    print_info "Removed repository '${repo_name}' from team '${team_name} in organization '${org_name}'" ;
  else
    print_error "Failed to remove repository '${repo_name}' from team '${team_name} in organization '${org_name}'" ;
  fi
}

# Add gitea collaborator to repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository owner (can be a user or an organization)
#     (3) username
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_add_collaborator_to_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repo name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repo owner as 3th argument" && return 2 || local repo_owner="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide username as 4th argument" && return 2 || local username="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' with owner '${repo_owner}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea user '${username}' does not exist" ;
    return 1 ;
  fi

  if $(curl --fail --silent --request PUT --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}/collaborators/${username}" \
            -d "{ \"permission\": \"admin\"}"); then
    print_info "Added collaborator '${username}' to repository '${repo_name}' with owner '${repo_owner}'" ;
  else
    print_error "Failed to add collaborator '${username}' to repository '${repo_name}' with owner '${repo_owner}'" ;
  fi
}

# Remove gitea collaborator from repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) repository owner (can be a user or an organization)
#     (3) username
#     (4) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_remove_collaborator_from_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repo name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repo owner as 3th argument" && return 2 || local repo_owner="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide username as 4th argument" && return 2 || local username="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${repo_owner}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' with owner '${repo_owner}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_user "${base_url}" "${username}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea user '${username}' does not exist" ;
    return 1 ;
  fi

  if $(curl --fail --silent --request DELETE --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/repos/${repo_owner}/${repo_name}/collaborators/${username}"); then
    print_info "Removed collaborator '${username}' from repository '${repo_name}' with owner '${repo_owner}'" ;
  else
    print_error "Failed to remove collaborator '${username}' from repository '${repo_name}' with owner '${repo_owner}'" ;
  fi
}

# Add gitea organization team to repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) organization name
#     (4) team name
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_add_org_team_to_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repo name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide organization name as 3th argument" && return 2 || local org_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide team name as 4th argument" && return 2 || local team_name="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  if $(curl --fail --silent --request PUT --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/repos/${org_name}/${repo_name}/teams/${team_name}"); then
    print_info "Added team '${team_name}' to repository '${repo_name}' in organization '${org_name}'" ;
  else
    print_error "Failed to add team '${team_name}' to repository '${repo_name}' in organization '${org_name}'" ;
  fi
}

# Remove gitea organization team from repository
#   args:
#     (1) api url
#     (2) repository name
#     (3) organization name
#     (4) team name
#     (5) basic auth credentials (optional, default 'gitea-admin:gitea-admin')
function gitea_remove_org_team_from_repo {
  [[ -z "${1}" ]] && print_error "Please provide api url as 1st argument" && return 2 || local base_url="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide repo name as 2nd argument" && return 2 || local repo_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide organization name as 4th argument" && return 2 || local org_name="${3}" ;
  [[ -z "${4}" ]] && print_error "Please provide team name as 5th argument" && return 2 || local team_name="${4}" ;
  [[ -z "${5}" ]] && local basic_auth="${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" || local basic_auth="${5}" ;
  
  if ! $(gitea_has_repo_by_owner "${base_url}" "${repo_name}" "${org_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea repository '${repo_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi
  if ! $(gitea_has_org_team "${base_url}" "${org_name}" "${team_name}" "${basic_auth}" &>/dev/null); then
    print_error "Gitea team '${team_name}' in organization '${org_name}' does not exist" ;
    return 1 ;
  fi

  if $(curl --fail --silent --request DELETE --user "${basic_auth}" \
            --header 'Content-Type: application/json' \
            --url "${base_url}/api/v1/repos/${org_name}/${repo_name}/teams/${team_name}") ; then
    print_info "Removed team '${team_name}' from repository '${repo_name}' in organization '${org_name}'" ;
  else
    print_error "Failed to remove team '${team_name}' from repository '${repo_name}' in organization '${org_name}'" ;
  fi
}

# Synchronize (git pull, add, commit and push) local code to a gitea repo
#   args:
#     (1) local repository folder (each subfolder should match a repo name)
#     (2) server url (with credentials)
#     (3) repository name
#     (4) repository owner (default 'gitea-admin')
#     (5) temporary folder (default /tmp/gitea-repos)
function gitea_sync_code_to_repo {
  [[ -z "${1}" ]] && print_error "Please provide local folder as 1st argument" && return 2 || local local_folder="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide gitea server url as 2nd argument" && return 2 || local server_url="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide repository name as 3rd argument" && return 2 || local repo_name="${3}" ;
  [[ -z "${4}" ]] && local repo_owner="${GITEA_ADMIN_USER}" || local repo_owner="${4}" ;
  [[ -z "${5}" ]] && local temp_folder="/tmp/gitea-repos" || local temp_folder="${5}" ;

  print_info "Going to git clone repo '${repo_owner}/${repo_name}' to '${temp_folder}'"
  mkdir -p ${temp_folder}
  cd ${temp_folder}
  rm -rf ${temp_folder}/${repo_name}
  git clone ${server_url}/${repo_owner}/${repo_name}.git

  print_info "Going remove, add, commit and push new code to repo '${repo_owner}/${repo_name}'"
  cd ${temp_folder}/${repo_name}
  rm -rf ${temp_folder}/${repo_name}/*
  cp -a ${local_folder}/${repo_name}/. ${temp_folder}/${repo_name}
  git add -A
  git commit -m "This is an automated commit"
  git push -u origin main
}