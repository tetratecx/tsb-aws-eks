# Helper functions to start, remove and interact with AWS Lambda Functions
#

LAMBDA_JS_FUNCTION="exports.handler = function (event, context) { context.succeed('Hello from Tetrate!'); };"
LAMBDA_TMP_DIR=/tmp/aws-lambda

# Start a lambda funnction
#   args:
#     (1) aws profile
#     (2) lambda name
#     (3) lambda region
function start_lambda_function {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide lambda name as 2nd argument" && return 2 || local lambda_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide lambda region as 3rd argument" && return 2 || local lambda_region="${3}" ;

  if $(aws iam list-roles --profile "${aws_profile}" --query "Roles[?RoleName=='${lambda_name}-exec']" --region "${lambda_region}" | grep "${lambda_name}-exec" &>/dev/null) ; then
    echo "Lambda iam execution role '${lambda_name}-exec' in region '${lambda_region}' already exists" ;
  else
    echo "Creating lambda iam execution role '${lambda_name}-exec' in region '${lambda_region}'" ;
    aws iam create-role \
      --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' \
      --profile "${aws_profile}" \
      --region "${lambda_region}" \
      --role-name "${lambda_name}-exec" ;

    echo "Attaching lambda iam role to the 'AWSLambdaBasicExecutionRole' policy"
    aws iam attach-role-policy \
      --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
      --profile "${aws_profile}" \
      --region "${lambda_region}" \
      --role-name "${lambda_name}-exec" ;
  fi

  local aws_account_id=$(aws sts get-caller-identity --output text --profile "${aws_profile}" --query "Account") ;
  if $(aws lambda list-functions --profile "${aws_profile}" --query "Functions[?FunctionName=='${lambda_name}']" --region "${lambda_region}" | grep "${lambda_name}" &>/dev/null) ; then
    echo "Lambda function with name '${lambda_name}' in region '${lambda_region}' already exists" ;
  else
    echo "Creating lambda zip file at '${LAMBDA_TMP_DIR}/function.zip' containing '${LAMBDA_TMP_DIR}/index.js'" ;
    rm -rf ${LAMBDA_TMP_DIR} ;
    mkdir -p ${LAMBDA_TMP_DIR} ;
    echo ${LAMBDA_JS_FUNCTION} > ${LAMBDA_TMP_DIR}/index.js ;
    zip -j ${LAMBDA_TMP_DIR}/function.zip ${LAMBDA_TMP_DIR}/index.js ;

    echo -n "Creating lambda function with name '${lambda_name}' in region '${lambda_region}': " ;
    while ! $(aws lambda create-function \
                --function-name "${lambda_name}" \
                --handler index.handler \
                --profile "${aws_profile}" \
                --region "${lambda_region}" \
                --role "arn:aws:iam::${aws_account_id}:role/${lambda_name}-exec" \
                --runtime nodejs18.x \
                --zip-file "fileb://${LAMBDA_TMP_DIR}/function.zip" &>/dev/null); do
      sleep 1 ;
      echo -n "." ;
    done
    echo "DONE" ;
  fi

  echo -n "Wait for lambda function with name '${lambda_name}' in region '${lambda_region}' to be available: " ;
  while ! $(aws lambda list-functions --profile "${aws_profile}" --query "Functions[?FunctionName=='${lambda_name}']" --region "${lambda_region}" | grep "${lambda_name}" &>/dev/null); do
    sleep 1 ; 
    echo -n "." ;
  done
  echo "DONE" ;

  if $(aws lambda get-function-url-config --function-name "${lambda_name}" --profile "${aws_profile}"  --region "${lambda_region}" &>/dev/null); then
    echo "Lambda function url config for lambda function with name '${lambda_name}' in region '${lambda_region}' already exists" ;
  else
    echo "Creating lambda function url config for lambda function with name '${lambda_name}' in region '${lambda_region}'" ;
    aws lambda create-function-url-config \
      --auth-type NONE \
      --function-name "${lambda_name}" \
      --profile "${aws_profile}" \
      --region "${lambda_region}" ;
  fi

  if $(aws lambda get-policy --function-name "${lambda_name}" --profile "${aws_profile}" --region "${lambda_region}" &>/dev/null); then
    echo "Resource based policy 'allow-anyone' on lambda function with name '${lambda_name}' in region '${lambda_region}' already exists" ;
  else
    echo "Creating resource based policy 'allow-anyone' on lambda function with name '${lambda_name}' in region '${lambda_region}'" ;
    aws lambda add-permission \
      --action "lambda:InvokeFunctionUrl" \
      --function-name "${lambda_name}" \
      --function-url-auth-type "NONE" \
      --principal "*" \
      --profile "${aws_profile}" \
      --region "${lambda_region}" \
      --statement-id "allow-anyone" ;
  fi
}

# Stop a lambda funnction
#   args:
#     (1) aws profile
#     (2) lambda name
#     (3) lambda region
function stop_lambda_function {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide lambda name as 2nd argument" && return 2 || local lambda_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide lambda region as 3rd argument" && return 2 || local lambda_region="${3}" ;

  echo "Delete lambda function '${lambda_name}' in region '${lambda_region}'" ;
  aws lambda delete-function \
    --function-name "${lambda_name}" \
    --profile "${aws_profile}" \
    --region "${lambda_region}" 2>/dev/null ;

  echo "Detaching role policy 'AWSLambdaBasicExecutionRole' from lambda iam execution role '${lambda_name}-exec' in region '${lambda_region}'" ;
  aws iam detach-role-policy \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
    --profile "${aws_profile}" \
    --region "${lambda_region}" \
    --role-name "${lambda_name}-exec" 2>/dev/null ;

  echo "Delete lambda iam execution role '${lambda_name}-exec' in region '${lambda_region}'" ;
  aws iam delete-role \
    --profile "${aws_profile}" \
    --region "${lambda_region}" \
    --role-name "${lambda_name}-exec" 2>/dev/null ;
}

# Get the public URL of a lambda function
#   args:
#     (1) aws profile
#     (2) lambda name
#     (3) lambda region
function get_lambda_function_url {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide lambda name as 2nd argument" && return 2 || local lambda_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide lambda region as 3rd argument" && return 2 || local lambda_region="${3}" ;

  echo $(aws lambda get-function-url-config \
    --function-name ${lambda_name} \
    --output text \
    --profile "${aws_profile}" \
    --query "FunctionUrl" \
    --region "${lambda_region}") ;
}

