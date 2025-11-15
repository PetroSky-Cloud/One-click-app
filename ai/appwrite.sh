#!/bin/bash
{literal}
curl -s https://netangels.net/utils/docker.sh | bash

# INTERACTIVE
#
docker run -it --rm \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume "$(pwd)"/appwrite:/usr/src/code/appwrite:rw \
    --entrypoint="install" \
    appwrite/appwrite:1.8.0
{/literal}
