.ONESHELL:

CARDANO_NODE_DOCKERFILE=$(PWD)/Dockerfile
GHC_VERSION=8.10.2
CABAL_VERSION=3.2.0.0
LIBSODIUM_VERSION=66f017f1
CARDANO_NODE_VERSION=1.25.1
INSTALL_DIR=/usr/local/bin
OS_ARCH=$(shell uname -m)

PUBLIC_IP=159.203.58.57
NETWORK="testnet-magic 1097911063"
CABAL_CONFIG_FILE=${HOME}/.cabal/config
POOL_DIR=$(PWD)/pool
POOL_KEY_DIR=$(POOL_DIR)/keys
RELAY_NODE_DIR=$(POOL_DIR)/relay
BLOCK_PRODUCING_NODE_DIR=$(POOL_DIR)/node
BLOCK_PRODUCING_NODE_PORT=3002
RELAY_NODE_PORT=3000

update:
	apt-get update
	apt-get upgrade -y
	apt-get install -y --no-install-recommends netbase jq libnuma-dev docker.io
	sudo systemctl start docker
	sudo systemctl enable docker

build-cardano:
	nohup docker build \
		--tag cardano-node:${CARDANO_NODE_VERSION}-${OS_ARCH} \
		--build-arg OS_ARCH="${OS_ARCH}" \
		--build-arg GHC_VERSION=${GHC_VERSION} \
		--build-arg CABAL_VERSION=${CABAL_VERSION} \
		--build-arg LIBSODIUM_VERSION=${LIBSODIUM_VERSION} \
		--build-arg CARDANO_NODE_VERSION=${CARDANO_NODE_VERSION} \
		-f $(CARDANO_NODE_DOCKERFILE) . > binary.out 2>&1 &
	tail -f binary.out

get-binary:
	mkdir -p ${INSTALL_DIR}
	docker run \
		--volume ${INSTALL_DIR}:/dist \
		cardano-node:${CARDANO_NODE_VERSION}-${OS_ARCH} \
		"cp /usr/local/bin/cardano* /dist; \
			mkdir -p /dist/lib/ && cp -r /usr/local/lib/lib* /dist/lib; \
			mkdir -p /dist/lib/pkgconfig && cp -r /usr/local/lib/pkgconfig/lib* /dist/lib/pkgconfig"

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

get-relay-config-files:
	@$(call get-config-files,$(RELAY_NODE_DIR))
	sed -i \
		's/\("valency": 2\)/\1 \
    },{ \
      "addr": "$(PUBLIC_IP)", \
      "port":$(BLOCK_PRODUCING_NODE_PORT), \
      "valency":1/g' \
		$(RELAY_NODE_DIR)/testnet-topology.json

get-node-config-files:
	@$(call get-config-files,$(BLOCK_PRODUCING_NODE_DIR))
	sed -i \
		-e 's/"addr": .*$$/"addr": "$(PUBLIC_IP)",/g' \
		-e 's/"port": .*$$/"port": "$(RELAY_NODE_PORT)",/g' \
		-e 's/"valency": .*$$/"valency": 1/g' \
		$(BLOCK_PRODUCING_NODE_DIR)/testnet-topology.json

generate-keys:
	@cardano-cli address key-gen \
		--verification-key-file $(POOL_KEY_DIR)/payment.vkey \
		--signing-key-file $(POOL_KEY_DIR)/payment.skey
	@cardano-cli stake-address key-gen \
		--verification-key-file $(POOL_KEY_DIR)/stake.vkey \
		--signing-key-file $(POOL_KEY_DIR)/stake.skey

get-addresses:
	@cardano-cli address build \
		--payment-verification-key-file $(POOL_KEY_DIR)/payment.vkey \
		--stake-verification-key-file $(POOL_KEY_DIR)/stake.vkey \
		--out-file $(POOL_KEY_DIR)/payment.addr \
		--$(NETWORK)
	@cardano-cli stake-address build \
		--stake-verification-key-file $(POOL_KEY_DIR)/stake.vkey \
		--out-file $(POOL_KEY_DIR)/stake.addr \
		--$(NETWORK)

get-balance:
	mkdir -p $(POOL_KEY_DIR) && cd $(POOL_KEY_DIR)
	@cardano-cli query utxo \
		--address $(shell cat payment.addr) \
		--$(NETWORK)

update-cabal-overwrite-policy:
	sed -i "s/-- overwrite-policy:/-- overwrite-policy: always/g" $(CABAL_CONFIG_FILE)

start-relay:
	cardano-node run \
		--topology $(RELAY_NODE_DIR)/testnet-topology.json \
		--database-path $(RELAY_NODE_DIR)/db \
		--socket-path $(RELAY_NODE_DIR)/socket \
		--config $(RELAY_NODE_DIR)/testnet-config.json \
		--port $(RELAY_NODE_PORT)


