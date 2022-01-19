deploy-maplandscape

# Docker 

Install Docker (requires root or sudo privelages to run; based on [dockerswarm.rocks](https://dockerswarm.rocks/#install-and-set-up)):

```
# Download Docker
curl -fsSL get.docker.com -o get-docker.sh
# Install Docker using the stable channel (instead of the default "edge")
CHANNEL=stable sh get-docker.sh
# Remove Docker install script
rm get-docker.sh
```

# Docker Swarm 

### Configure Firewalls for Docker Swarm

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

reload UFW:

```
ufw reload
```

enable UFW:

```
ufw enable
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
export DOMAIN=traefik.sys.<your domain>
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

Create an environment variable with an email address to use to create a Let's Encrypt certificate.

```
export EMAIL=admin@example.com
```

## Deploy

```
docker stack deploy -c docker-compose.traefik.yml traefik
```

Check the service:

```
docker service ls
```

# Setup Apps

Download the apps from GitHub and include a `Dockerfile` to build the app. 

## Configure Shiny Proxy

Configure the Shiny Proxy `application.yml` file in the `shiny-proxy` directory. 

In the `shiny-proxy/templates/assets/img` directory include jpg images associated with the card display for each app on the landing page. The image file should have the same name as the app id in the `application.yml` file. 

In `shiny-proxy/templates/assets/index.html` make any edits to the landing page UI as required. 

## Configure Shiny Apps

Add any necessary configurations in downloaded Shiny apps (e.g. updating `config.yml` files).

## Deploy Shiny Proxy 

Create an environment variable with the URL for the Shiny Proxy:

```
export DOMAIN=app.<your domain>
```

Create an overlay network for docker containers hosting Shiny apps and Shiny Proxy.

```
docker network create --driver=overlay sp-net
```

Deploy the Shiny Proxy stack.

```
docker stack deploy -c docker-compose.shinyproxy.yml shinyproxy
```