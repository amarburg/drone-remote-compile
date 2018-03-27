
IMAGE ?= amarburg/remote-compile:latest

TEST_KEYS = testdata/keys/id_rsa

all: docker drone


## Build image
docker: remote.sh Dockerfile
	docker build --rm -t $(IMAGE) .


## Test locally with drone
drone: $(TEST_KEYS)
	drone exec .drone.yml



## Configuration for demo
PLUGIN_HOST ?= $(shell hostname)
PLUGIN_USER ?= $(shell whoami)
PLUGIN_TARGET ?= "tempdir"
PLUGIN_SCRIPT ?= "ls -al"

$(TEST_KEYS):
	mkdir -p  $(dir $@) && ssh-keygen -f $@ -N ""
	cp $(@:=.pub) $(dir $@)/authorized_keys

demo: $(TEST_KEYS)
	docker run  \
						--env PLUGIN_HOSTS=$(PLUGIN_HOST) \
						--env PLUGIN_USER=$(PLUGIN_USER) \
						--env PLUGIN_TARGET=$(PLUGIN_TARGET) \
						--env PLUGIN_SCRIPT=$(PLUGIN_SCRIPT) \
						-v $(abspath $(dir $(TEST_KEYS))):/root/keys:ro \
						--rm -t -i $(IMAGE)


.PHONY: docker demo drone
