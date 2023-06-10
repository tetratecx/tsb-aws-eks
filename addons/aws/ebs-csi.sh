# Helper functions to enable and disable/remove EKS EBS CSI driver support
#


# Enable EBS CSI driver for persistent volume claims
#   args:
#     (1) aws profile
#     (2) cluster name
#     (3) cluster region
function enable_ebs_csi_driver {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster name as 2nd argument" && return 2 || local cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cluster region as 3rd argument" && return 2 || local cluster_region="${3}" ;

  if $(aws iam list-open-id-connect-providers --profile "${aws_profile}" \
        | grep $(aws eks describe-cluster \
                  --name "${cluster_name}" \
                  --output text \
                  --profile "${aws_profile}" \
                  --query "cluster.identity.oidc.issuer" \
                  --region "${cluster_region}" | cut -d '/' -f 5) &>/dev/null); then
    echo "EKS cluster '${cluster_name}' in region '${cluster_region}' already has an iam-oidc-provider associated"
  else
    eksctl utils associate-iam-oidc-provider \
      --approve \
      --cluster "${cluster_name}" \
      --profile "${aws_profile}" \
      --region "${cluster_region}" ;
  fi

  if $(eksctl get iamserviceaccount \
        --cluster "${cluster_name}" \
        --name "ebs-csi-controller-sa" \
        --profile "${aws_profile}" \
        --region "${cluster_region}" | grep "No iamserviceaccounts found" &>/dev/null); then
    eksctl create iamserviceaccount \
      --approve \
      --attach-policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" \
      --cluster "${cluster_name}" \
      --name "ebs-csi-controller-sa" \
      --namespace "kube-system" \
      --profile "${aws_profile}" \
      --region "${cluster_region}" \
      --role-name "eksctl-${cluster_name}-${cluster_region}-EbsCsiDriverRole" \
      --role-only ;
  else
    echo "EKS cluster '${cluster_name}' in region '${cluster_region}' already has an iamserviceaccount 'eksctl-${cluster_name}-${cluster_region}-EbsCsiDriverRole' associated" ;
    
  fi

  if $(eksctl get addon \
        --cluster "${cluster_name}" \
        --name "aws-ebs-csi-driver" \
        --profile "${aws_profile}" \
        --region "${cluster_region}" &>/dev/null); then
    echo "EKS cluster '${cluster_name}' in region '${cluster_region}' already has addon 'aws-ebs-csi-driver' enabled" ;
  else
    eksctl create addon \
      --cluster "${cluster_name}" \
      --force \
      --name "aws-ebs-csi-driver" \
      --profile "${aws_profile}" \
      --region "${cluster_region}" \
      --service-account-role-arn "arn:aws:iam::$(aws sts get-caller-identity \
                                                  --output text \
                                                  --profile ${aws_profile} \
                                                  --query Account):role/eksctl-${cluster_name}-${cluster_region}-EbsCsiDriverRole" ;
  fi
}

# Delete IAM Service Account of EBS CSI driver for persistent volume claims
#   args:
#     (1) aws profile
#     (2) cluster name
#     (3) cluster region
function delete_iamserviceaccount {
  [[ -z "${1}" ]] && print_error "Please provide aws profile as 1st argument" && return 2 || local aws_profile="${1}" ;
  [[ -z "${2}" ]] && print_error "Please provide cluster name as 1st argument" && return 2 || local cluster_name="${2}" ;
  [[ -z "${3}" ]] && print_error "Please provide cluster region as 2nd argument" && return 2 || local cluster_region="${3}" ;

  echo "Delete iamserviceaccount 'ebs-csi-controller-sa' of cluster '${cluster_name}' in region '${cluster_region}'" ;
  eksctl delete iamserviceaccount \
    --cluster "${cluster_name}" \
    --name "ebs-csi-controller-sa" \
    --namespace "kube-system" \
    --profile "${aws_profile}" \
    --region "${cluster_region}" ;
}
