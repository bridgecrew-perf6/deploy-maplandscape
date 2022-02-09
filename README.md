# deploy-maplandscape

Instructions to deploy *maplandscape* dashboard apps for exploring and analysing geospatial data in GeoPackage files in a web browswer. It deploys *maplandscape* and *maplandscape-view* Shiny web apps in docker containers using Shiny Proxy as part of a docker swarm. Traefik is used as a reverse proxy and load balancer and Let's Encrypt is used for TLS. The deployment architecture is based on this [resource](https://www.databentobox.com/2020/05/31/shinyproxy-with-docker-swarm/).

# Docker 

Install Docker (requires root or sudo privelages to run) following these [instructions](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository).

Install dependencies:

```
sudo apt-get update

sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
```

Get docker GPG key:
```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
```

Setup the stable docker repository:

```
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

Install docker engine:

```
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io
```

Install docker-compose:

```
apt install docker-compose
```

# Docker Swarm 

### Configure Firewalls for Docker Swarm

#### Use Convenience Script

From the root of the `deploy-maplandscape` directory:

```
./scripts/create_firewalls.sh
```

If permissions on `create_firewalls.sh` are denied:

```
chmod 777 ./scripts/create_firewalls.sh'
```

#### Manual Firewall Configuration

UFW (Uncomplicated Firewall) is an interface to `iptables` to simplify the process of configuring a firewall. 

Use `ufw allow` to allow incoming connections on a port - e.g. allow SSH connections on port 22

``` 
ufw allow 22/tcp
```

```
ufw allow 22/tcp
ufw allow 2376/tcp 
ufw allow 2377/tcp 
ufw allow 7946/tcp 
ufw allow 7946/udp
ufw allow 4789/udp
ufw allow http 
ufw allow https
```

Note: `ufw all http` is equivalent to `ufw allow 80` and `ufw allow https` is equivalent to `ufw allow 443`. 

enable UFW:

```
ufw enable
```

reload UFW:

```
ufw reload
```

Check the status of the firewall using:

```
ufw verbose
```

More information on configuring firewalls for Docker Swarm [here](https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-with-ufw-on-ubuntu-16-04) and [here](https://www.digitalocean.com/community/tutorials/how-to-configure-the-linux-firewall-for-docker-swarm-on-ubuntu-16-04).

## Initialize a Docker Swarm

```
docker swarm init --advertise-addr <public ip>
```

Get the join token for manager and worker nodes. Store the tokens securely to add nodes to the swarm.

```
docker swarm join-token worker
docker swarm join-token manager
```

# Set up Traefik 

Create an overlay network to allow Traefik to communicate with Shiny Proxy. 

```
docker network create --driver=overlay traefik-public
```

Get the Swarm node ID and store it in an evironment variable:

```
export NODE_ID=$(docker info -f '{{.Swarm.NodeID}}')
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
| A | traefik.sys.<your domain>| IP |
|---|---|---|

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
docker build -t 127.0.0.1:5000/shinyproxy .
```

Push to registry:

```
docker push 127.0.0.1:5000/shinyproxy
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

## Build maplandscape

Download the app from GitHub:

```
git clone https://github.com/livelihoods-and-landscapes/maplandscape.git
```

Build the docker image:

```
cd inst
docker build -t 127.0.0.1:5000/maplandscape .
```

Push to local registry:

```
docker push 127.0.0.1:5000/maplandscape
```

In the docker-compose file `docker-compose.shinyproxy.yml` add the image for the maplandscape service as `image: 127.0.0.1:5000/maplandscape`

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
