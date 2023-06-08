# Tetrate Service Bridge on AWS EKS

Copy and modify [env_host.template.json](env_host.template.json) file to [env_host.json](env_host.json) (part of `.gitignore`) to suite your needs.

```json
{
  "istioctl_version": "1.15.7",
  "kubectl_version": "1.25.10",
  "tetrate_repo": {
    "password": "<TSB_REPO_APIKEY>",
    "url": "containers.dl.tetrate.io",
    "user": "<TSB_REPO_USERNAME>"
  },
  "tsb_version": "1.6.2"
}
```

The `TSB_REPO_APIKEY` and `TSB_REPO_USERNAME` will be given to you by a Tetrate Sales Representative.

## Setup AWS EKS Clusters and install Tetrate Service Bridge

Run the make file to go through the setup process

```
# make
help                           This help
prereq-check                   Check if prerequisites are installed
prereq-install                 Install prerequisites
awscli-login                   Login to AWS CLI
eks-up                         Create k8s clusters using eksctl
eks-down                       Delete k8s clusters using eksctl
eks-info                       Get k8s clusters information
```

Before spinning up your EKS cluster on AWS, you will need to login into the AWS CLI using the awscli-login target.
Most targets will check the `prereq-check` target to make sure you have the necessary host software installed.
You can use the `prereq-install` target to install some of these prerequisites automatically.


## Temporary Setup Artifacts

Temporary setup artifacts bespoke to your multi-cluster setup include

- WIP
- WIP

These files are part of this repo's `.gitignore` configuration.
AWS credentials are not stored in this repo, but a dedicated profile defined in `env.json` (default `tetrate-aws-tsb-poc`) for `~/.aws/config` is used for this.
