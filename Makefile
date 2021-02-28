.ONESHELL:

CARDANO_NODE_DOCKERFILE=$(PWD)/Dockerfile
GHC_VERSION=8.10.2
CABAL_VERSION=3.2.0.0
LIBSODIUM_VERSION=66f017f1
CARDANO_NODE_VERSION=1.25.1
INSTALL_DIR=/usr/local/bin

OS_ARCH=$(shell uname -m)
NETWORK="--testnet-magic 1097911063"

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

get-config-files:
	@wget -qP /etc/config https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-config.json
	@wget -qP /etc/config https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-byron-genesis.json
	@wget -qP /etc/config https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-shelley-genesis.json
	@wget -qP /etc/config https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/testnet-topology.json
	@wget -qP /etc/config https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/mainnet-config.json
	@wget -qP /etc/config https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/mainnet-byron-genesis.json
	@wget -qP /etc/config https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/mainnet-shelley-genesis.json
	@wget -qP /etc/config https://hydra.iohk.io/job/Cardano/cardano-node/cardano-deployment/latest-finished/download/1/mainnet-topology.json

generate-keys:
	@cardano-cli address key-gen \
		--verification-key-file $(KEY_DIR)/payment.vkey \
		--signing-key-file $(KEY_DIR)/payment.skey
	@cardano-cli stake-address key-gen \
		--verification-key-file $(KEY_DIR)/stake.vkey \
		--signing-key-file $(KEY_DIR)/stake.skey

get-addresses:
	@cardano-cli address build \
		--payment-verification-key-file $(KEY_DIR)/payment.vkey \
		--stake-verification-key-file $(KEY_DIR)/stake.vkey \
		--out-file $(KEY_DIR)/payment.addr \
		$(NETWORK)
	@cardano-cli stake-address build \
		--stake-verification-key-file $(KEY_DIR)/stake.vkey \
		--out-file $(KEY_DIR)/stake.addr \
		$(NETWORK)

get-balance:
	@mkdir -p keys && cd keys
	@cardano-cli query utxo \
		--address $(shell cat payment.addr) \
		$(NETWORK)
