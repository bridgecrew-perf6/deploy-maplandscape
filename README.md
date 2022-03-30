# deploy-maplandscape

Instructions to deploy *maplandscape* dashboard apps for exploring and analysing geospatial data in GeoPackage files in a web browswer. It deploys *maplandscape* and *maplandscape-view* Shiny web apps in docker containers using Shiny Proxy as part of a docker swarm. Traefik is used as a reverse proxy and load balancer and Let's Encrypt is used for TLS. The deployment architecture is based on this [resource](https://www.databentobox.com/2020/05/31/shinyproxy-with-docker-swarm/).

# Setup hosts

Setup host machines that will be members of the docker swarm. 

# Docker 

Install Docker (requires root or sudo privelages to run) following these [instructions](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository).

This needs to be repeated on each of the hosts. `./scripts/install-docker.sh` can be executed to install docker.:

```
scp -r "./scripts/install-docker.sh" root@<HOST IP>:/scripts
./scripts/install-docker.sh
```

# Docker Swarm 

### Configure Firewalls for Docker Swarm

#### Manager Node

For the manager node in the swarm, execute `./scripts/create_firewalls_manager.sh`.

This can be copied from the root of the `deploy-maplandscape` directory to the manager node if required:

```
scp -r `./scripts/create_firewalls_manager.sh` root@<HOST IP>:/scripts/
```
and execute from root:

```
./scripts/create_firewalls_manager.sh
```
Or, if the `deploy-maplandscape` directory has been cloned. Execute the scripts from the the root of the `deploy-maplandscape` directory.  

If permissions on `create_firewalls_manager.sh` are denied:

```
chmod 777 ./scripts/create_firewalls_manager.sh
```

### Worker Node

Follow a similar process for worker nodes:

```
scp -r `./scripts/create_firewalls_worker.sh` root@<HOST IP>:/scripts/
```

```
./scripts/create_firewalls_worker.sh
```

If permissions on `create_firewalls_worker.sh` are denied:

```
chmod 777 ./scripts/create_firewalls_worker.sh
```

More information on configuring firewalls for Docker Swarm [here](https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-with-ufw-on-ubuntu-16-04) and [here](https://www.digitalocean.com/community/tutorials/how-to-configure-the-linux-firewall-for-docker-swarm-on-ubuntu-16-04).

## Initialize a Docker Swarm

On the manager node (i.e. ssh into the manager host machine), execute:

```
docker swarm init --advertise-addr <public ip>
```

Get the join token for manager and worker nodes. Store the tokens securely to add nodes to the swarm.

```
docker swarm join-token worker
docker swarm join-token manager
```

### Add a Worker Node

On the worker node (i.e. ssh into the worker host machine), execute:

```
docker swarm join \
  --token <TOKEN> \
  <IP:PORT>
```

The above command can be generated by executing `docker swarm join-token worker` on the manager node. 

## Node Labels

On the manager node, run `docker node ls` to display the swarm node IDs. 

Save the swarm node IDs as environment variables. 

First, save the node ID where traefik and shiny proxy will be deployed. This is the swarm manager node.

```
export NODE_ID="PASTE NODE ID FOR MANAGER NODE"
```

Next, save the node ID for the node where the postgis instance will be deployed. 

```
export NODE_DB_ID="PASTE NODE ID FOR POSTGIS NODE"
```

# Setup Maplandscape

From the `deploy-maplandscape` directory, run:

```
./scripts/deploy.sh
```

The following information will need to be provided when prompted:

* *traefik domain* - URL where the traefik dashboard will be accessible.
* *traefik username* - username to login to traefik dashboard (e.g. admin).
* *traefik password* - password to login to traefik dashboard.
* *let's encrypt email* - email address used to generate certificates from Let's Encrypt. 
* *PostGIS database name* - name of PostGIS database (this should match the config file of maplandscape).
* *PostGIS username* - PostGIS username (this should match the config file of maplandscape).
* *PostGIS password* - PostGIS password (this should match the config file of maplandscape).
* *app domain* - URL where maplandscape will be accessible. 

For the traefik and app domains, the DNS record at the domain registry needs to be set to the IP address of the node hosting traefik:

| Record | Name | IP |
|---|---|---|
| A | traefik.<your domain>| IP |

# Setup Traefik

Create an overlay network to allow Traefik to communicate with Shiny Proxy. 

```
docker network create --driver=overlay traefik-public
```

Create a tag in the node so Traefik is always deployed on the same node and uses the same volume:

```
docker node update --label-add traefik-public.traefik-public-certificates=true $NODE_ID
```

## Traefik Dashboard

Create an environment variable with the URL for the Traefik dashboard:

```
export DOMAIN=traefik.<your domain>
```

Setup up the DNS record points this domain to the IP address of the node hosting Traefik.

| Record | Name | IP |
|---|---|---|
| A | traefik.<your domain>| IP |


Create environment variables with a username and password to use HTTP basic authentication to login into the Traefik dashboard.

```
export USERNAME=admin
```

```
export HASHED_PASSWORD=$(openssl passwd -apr1)
```

## Let's Encrypt

Let's Encrypt certificates are valid for 90 days. Traefik will automatically renew certificates. 

```
export EMAIL=<test@test.com>
```

## Deploy Traefik Service

```
docker stack deploy -c docker-compose.traefik.yml traefik
```

Check the service:

```
docker service ls
```

# Setup Apps

Use `docker stack deploy` to deploy a complete application stack to the swarm specified in a `compose` file.

## Docker Registry

A swarm comprises multiple docker engines, therefore a registry is required to serve images which make up the stack's applications to docker engines running on the swarm nodes. 

A registry service available at localhost should be accessible to nodes in the swarm, but not accessible externally.

Start a registry container:

```
docker service create --name registry --publish published=5000,target=5000 registry:2
```

## Build Shiny Proxy and Shiny Apps

Create a Shiny Proxy `Dockerfile`:

```
# from: https://www.databentobox.com/2019/11/05/deploy-r-app-with-shinyproxy/#writing-a-docker-file
FROM openjdk:8-jre

RUN mkdir -p /opt/shinyproxy/
RUN wget https://www.shinyproxy.io/downloads/shinyproxy-2.6.0.jar -O /opt/shinyproxy/shinyproxy.jar
COPY application.yml /opt/shinyproxy/application.yml

WORKDIR /opt/shinyproxy/
CMD ["java", "-jar", "/opt/shinyproxy/shinyproxy.jar"]

```

Build the Shiny Proxy container:

```
cd shiny-proxy
docker build -t 127.0.0.1:5000/shinyproxy .
```

Push to registry:

```
docker push 127.0.0.1:5000/shinyproxy
```

Move back to the main deployment directory:

```
cd ..
```

## Shiny Apps Image

Download the apps from GitHub (or scp them onto the server) and include a `Dockerfile` to build the app. Prior to building, update any config files with private information (e.g. API keys) that should not be public on GitHub.

Push the apps to the local registry. 

Add the apps as services in `docker-compose.shinyproxy.yml` and update the `application.yml` file. 

### Build maplandscape-view

Download maplandscape-view from GitHub:

```
git clone https://github.com/livelihoods-and-landscapes/maplandscape-view.git
```

Make sure the config file is correctly configured:

```
cd maplandscape-view
cd app
cp config-example.yml config.yml
```

Build the docker image:

```
cd ..
docker build -t 127.0.0.1:5000/maplandscape-view .
```

Push to local registry:

```
docker push 127.0.0.1:5000/maplandscape-view
```

In the docker-compose file `docker-compose.shinyproxy.yml` add the image for the maplandscape-view service as `image: 127.0.0.1:5000/maplandscape-view`

Move back to the main deployment directory:

```
cd ..
```

## Build maplandscape

Download the app from GitHub:

```
git clone https://github.com/livelihoods-and-landscapes/maplandscape.git
```

Build the docker image:

```
cd maplandscape
cd inst
docker build -t 127.0.0.1:5000/maplandscape .
```

Push to local registry:

```
docker push 127.0.0.1:5000/maplandscape
```

In the docker-compose file `docker-compose.shinyproxy.yml` add the image for the maplandscape service as `image: 127.0.0.1:5000/maplandscape`

Move back to the main deployment directory:

```
cd ..
cd ..
```

## Build maplandscape-admin

Download the app from GitHub:

```
git clone https://github.com/livelihoods-and-landscapes/maplandscape-admin.git
```

Build the docker image:

```
cd maplandscape-admin
docker build -t 127.0.0.1:5000/maplandscape-admin .
```

Push to local registry:

```
docker push 127.0.0.1:5000/maplandscape-admin
```

In the docker-compose file `docker-compose.shinyproxy.yml` add the image for the maplandscape service as `image: 127.0.0.1:5000/maplandscape-admin`

Move back to the main deployment directory:

```
cd ..
```

## Configure Shiny Proxy

Configure the Shiny Proxy `application.yml` file in the `shiny-proxy` directory. 

In the `shiny-proxy/templates/assets/img` directory include jpg images associated with the card display for each app on the landing page. The image file should have the same name as the app id in the `application.yml` file. 

In `shiny-proxy/templates/assets/index.html` make any edits to the landing page UI as required. 

## Deploy Shiny Proxy 

Create an environment variable with the URL for the Shiny Proxy:

```
export APP_DOMAIN=app.<your domain>
```

Create an overlay network for docker containers hosting Shiny apps and Shiny Proxy.

```
docker network create --driver=overlay sp-net
```

Deploy the Shiny Proxy stack.

```
docker stack deploy -c docker-compose.shinyproxy.yml shinyproxy
```
