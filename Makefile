# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help

help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

.PHONY: up info down
up: aws-up addons-deploy tsb-deploy scenario-deploy ## Bring up full demo scenario
info: aws-info addons-info tsb-info scenario-info ## Get demo setup information
down: aws-down ## Bring down full demo scenario


.PHONY: prereq-check
prereq-check: ## Check if prerequisites are installed
	@/bin/sh -c './prereq.sh check'

.PHONY: prereq-install
prereq-install: ## Install prerequisites
	@/bin/sh -c './prereq.sh install'

.PHONY: aws-cli-login
aws-cli-login: ## Login to AWS CLI
	@/bin/sh -c './aws.sh login'

.PHONY: aws-up
aws-up: prereq-check aws-cli-login ## Create eks clusters and ecr repository [eta 17min]
	@/bin/sh -c './aws.sh up'

.PHONY: aws-down
aws-down: ## Delete eks clusters and ecr repository [eta 12min]
	@/bin/sh -c './aws.sh down'

.PHONY: aws-info
aws-info: ## Get eks clusters and ecr repository information
	@/bin/sh -c './aws.sh info'

.PHONY: addons-deploy
addons-deploy: prereq-check ## Deploy cluster addons (argcocd, gitea)
	@/bin/sh -c './addons.sh deploy'

.PHONY: addons-undeploy
addons-undeploy: ## Undeploy cluster addons (argcocd, gitea)
	@/bin/sh -c './addons.sh undeploy'

.PHONY: addons-info
addons-info: ## Get cluster addons information (argcocd, gitea)
	@/bin/sh -c './addons.sh info'

.PHONY: tsb-deploy
tsb-deploy: prereq-check ## Deploy tsb mp and cp
	@/bin/sh -c './tsb.sh deploy'

.PHONY: tsb-undeploy
tsb-undeploy: ## Undeploy tsb mp and cp
	@/bin/sh -c './tsb.sh undeploy'

.PHONY: tsb-info
tsb-info: ## Get tsb information
	@/bin/sh -c './tsb.sh info'

.PHONY: scenario-deploy
scenario-deploy: prereq-check ## Deploy demo scenarios
	@/bin/sh -c './scenario.sh deploy'

.PHONY: scenario-undeploy
scenario-undeploy: ## Undeploy demo scenarios
	@/bin/sh -c './scenario.sh undeploy'

.PHONY: scenario-info
scenario-info: ## Get scenarios information
	@/bin/sh -c './scenario.sh info'
