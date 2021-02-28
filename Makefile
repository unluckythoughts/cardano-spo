.ONESHELL:

CARDANO_NODE_DOCKERFILE=$(PWD)/Dockerfile
CARDANO_NODE_SERVICEFILE=$(PWD)/cardano-node.service
GHC_VERSION=8.10.2
CABAL_VERSION=3.2.0.0
LIBSODIUM_VERSION=66f017f1
CARDANO_NODE_VERSION=1.25.1
PROMETHEUS_VERSION=2.25.0
NODE_EXPORTER_VERSION=1.1.1

INSTALL_DIR=/usr/local/bin
OS_ARCH=$(shell uname -m)

# NETWORK=mainnet
# NETWORK_PARAMETER=

NETWORK=testnet
NETWORK_PARAMETER=-magic 1097911063

PUBLIC_IP=159.203.58.57
POOL_DIR=$(PWD)/pool
POOL_KEY_DIR=$(POOL_DIR)/keys
RELAY_NODE_DIR=$(POOL_DIR)/relay
STAKING_NODE_DIR=$(POOL_DIR)/node
STAKING_NODE_PORT=3002
RELAY_NODE_PORT=3000

# help extracts the help texts for the comments following ': ##'
.PHONY: help
help: ## Print this help message
	@awk -F':.*## ' ' \
		/^[[:alpha:]_-]+:.*## / { \
			printf "\033[36m%s\033[0m\t%s\n", $$1, $$2 \
		} \
	' $(MAKEFILE_LIST) | column -s$$'\t' -t


.PHONY: update
update: ## update ubuntu and setup required dependencies
	apt-get update
	apt-get upgrade -y
	apt-get install -y --no-install-recommends netbase jq libnuma-dev docker.io
	sudo systemctl start docker

.PHONY: build-cardano
build-cardano: ## builds cardano node binaries in a docker
	nohup docker build \
		--tag cardano-node:${CARDANO_NODE_VERSION}-${OS_ARCH} \
		--build-arg OS_ARCH="${OS_ARCH}" \
		--build-arg GHC_VERSION=${GHC_VERSION} \
		--build-arg CABAL_VERSION=${CABAL_VERSION} \
		--build-arg LIBSODIUM_VERSION=${LIBSODIUM_VERSION} \
		--build-arg CARDANO_NODE_VERSION=${CARDANO_NODE_VERSION} \
		-f $(CARDANO_NODE_DOCKERFILE) . > binary.out 2>&1 &
	tail -f binary.out

.PHONY: get-binary
get-binary: ## move binaries built in docker to the local machine
	mkdir -p ${INSTALL_DIR}
	docker run \
		--volume ${INSTALL_DIR}:/dist \
		cardano-node:${CARDANO_NODE_VERSION}-${OS_ARCH} \
		"cp /usr/local/bin/cardano* /dist; \
			mkdir -p /dist/lib/ && cp -r /usr/local/lib/lib* /dist/lib; \
			mkdir -p /dist/lib/pkgconfig && cp -r /usr/local/lib/pkgconfig/lib* /dist/lib/pkgconfig"

.PHONY: get-node-exporter
get-node-exporter: ## install node exporter
	wget -nc -q https://github.com/prometheus/node_exporter/releases/download/v$(NODE_EXPORTER_VERSION)/node_exporter-$(NODE_EXPORTER_VERSION).linux-amd64.tar.gz
	tar xfz node_exporter-$(NODE_EXPORTER_VERSION).linux-amd64.tar.gz
	cd node_exporter-$(NODE_EXPORTER_VERSION).linux-amd64
	mv ./node_exporter /usr/local/bin/
	cd .. && rm -rf node_exporter*

.PHONY: get-prometheus
get-prometheus: ## install prometheus
	wget -nc -q https://github.com/prometheus/prometheus/releases/download/v$(PROMETHEUS_VERSION)/prometheus-$(PROMETHEUS_VERSION).linux-amd64.tar.gz
	tar xfz prometheus-$(PROMETHEUS_VERSION).linux-amd64.tar.gz
	cd prometheus-$(PROMETHEUS_VERSION).linux-amd64
	mv ./prometheus /usr/local/bin/
	cd .. && rm -rf prometheus*

define get-config-files
	@wget -nc -qP $(1) https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-config.json
	wget -nc -qP $(1) https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-byron-genesis.json
	wget -nc -qP $(1) https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-shelley-genesis.json
	wget -nc -qP $(1) https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-topology.json
	wget -nc -qP $(1) https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/mainnet-config.json
	wget -nc -qP $(1) https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/mainnet-byron-genesis.json
	wget -nc -qP $(1) https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/mainnet-shelley-genesis.json
	wget -nc -qP $(1) https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/mainnet-topology.json
	sed -i 's/\(TraceBlockFetchDecisions": \).*$$/\1true,/g' $(1)/mainnet-config.json
	sed -i 's/\(TraceBlockFetchDecisions": \).*$$/\1true,/g' $(1)/testnet-config.json
endef

.PHONY: get-relay-config-files
get-relay-config-files: ## download relay node config files
	@$(call get-config-files,$(RELAY_NODE_DIR))
	[[ grep -c "CARDANO_NODE_SOCKET_PATH" -eq 0 ]] && \
		export CARDANO_NODE_SOCKET_PATH=$(RELAY_NODE_DIR)/socket >> ~/.bashrc
	sed -i \
		's/\("valency": 2\)/\1 \
    },{ \
      "addr": "$(PUBLIC_IP)", \
      "port":$(STAKING_NODE_PORT), \
      "valency":1/g' \
		$(RELAY_NODE_DIR)/testnet-topology.json

.PHONY: get-node-config-files
get-node-config-files: ## download staking node config files
	@$(call get-config-files,$(STAKING_NODE_DIR))
	sed -i \
		-e 's/"addr": .*$$/"addr": "$(PUBLIC_IP)",/g' \
		-e 's/"port": .*$$/"port": "$(RELAY_NODE_PORT)",/g' \
		-e 's/"valency": .*$$/"valency": 1/g' \
		$(STAKING_NODE_DIR)/testnet-topology.json

.PHONY: run-relay
run-relay: ## run relay node in terminal
	@cardano-node run \
		--topology $(RELAY_NODE_DIR)/$(NETWORK)-topology.json \
		--database-path $(RELAY_NODE_DIR)/db \
		--socket-path $(RELAY_NODE_DIR)/socket \
		--config $(RELAY_NODE_DIR)/$(NETWORK)-config.json \
		--port $(RELAY_NODE_PORT)

.PHONY: setup-relay-node-service
setup-relay-node-service: ## setup relay node service and enable it to start on restart
	@sed \
		-e 's:NODE_DIR:$(RELAY_NODE_DIR):g' \
		-e 's:NODE_PORT:$(RELAY_NODE_PORT):g' \
		-e 's:NETWORK:$(NETWORK):g' \
		$(CARDANO_NODE_SERVICEFILE) > /etc/systemd/system/cardano-relay-node.service
	sudo systemctl enable cardano-relay-node

.PHONY: start-relay-node
start-relay-node: ## start relay node service
	@sudo systemctl start cardano-relay-node
	sudo systemctl status cardano-relay-node

.PHONY: stop-relay-node
stop-relay-node: ## stop relay node service
	@sudo systemctl stop cardano-relay-node
	sudo systemctl status cardano-relay-node

.PHONY: check-relay-tip
check-relay-tip: ## check relay node tip
	@CARDANO_NODE_SOCKET_PATH=$(RELAY_NODE_DIR)/socket \
	cardano-cli query tip --$(NETWORK)$(NETWORK_PARAMETER) | jq

.PHONY: setup-staking-node-service
setup-staking-node-service: ## setup staking node service and enable it to start on restart
	@sed \
		-e 's:NODE_DIR:$(STAKING_NODE_DIR):g' \
		-e 's:NODE_PORT:$(STAKING_NODE_PORT):g' \
		-e 's:NETWORK:$(NETWORK):g' \
		$(CARDANO_NODE_SERVICEFILE) > /etc/systemd/system/cardano-staking-node.service
	sudo systemctl enable cardano-staking-node

.PHONY: start-staking-node-node
start-staking-node-node: ## start staking node service
	@sudo systemctl start cardano-staking-node
	sudo systemctl status cardano-staking-node

.PHONY: stop-staking-node-node
stop-staking-node-node: ## stop staking node service
	@sudo systemctl stop cardano-staking-node
	sudo systemctl status cardano-staking-node

.PHONY: check-node-tip
check-node-tip: ## check staking node tip
	@CARDANO_NODE_SOCKET_PATH=$(STAKING_NODE_DIR)/socket \
	cardano-cli query tip --$(NETWORK)$(NETWORK_PARAMETER) | jq

.PHONY: generate-keys
generate-keys: ## generate payment and staking keys
	@cardano-cli address key-gen \
		--verification-key-file $(POOL_KEY_DIR)/payment.vkey \
		--signing-key-file $(POOL_KEY_DIR)/payment.skey
	cardano-cli stake-address key-gen \
		--verification-key-file $(POOL_KEY_DIR)/stake.vkey \
		--signing-key-file $(POOL_KEY_DIR)/stake.skey

.PHONY: get-addresses
get-addresses: ## generate payment and staking addresses
	@cardano-cli address build \
		--payment-verification-key-file $(POOL_KEY_DIR)/payment.vkey \
		--stake-verification-key-file $(POOL_KEY_DIR)/stake.vkey \
		--out-file $(POOL_KEY_DIR)/payment.addr \
		--$(NETWORK)$(NETWORK_PARAMETER)
	cardano-cli stake-address build \
		--stake-verification-key-file $(POOL_KEY_DIR)/stake.vkey \
		--out-file $(POOL_KEY_DIR)/stake.addr \
		--$(NETWORK)$(NETWORK_PARAMETER)

.PHONY: get-balance
get-payment-balance: ## get balance for payment address from relay node
	@CARDANO_NODE_SOCKET_PATH=$(STAKING_NODE_DIR)/socket \
	cardano-cli query utxo \
		--address $(shell cat $(POOL_KEY_DIR)/payment.addr) \
		--$(NETWORK)$(NETWORK_PARAMETER)


