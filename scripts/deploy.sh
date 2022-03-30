#!/bin/bash

# setup traefik
echo
echo "####### TRAEFIK SETUP #######"
echo "Enter (sub)domain name for hosting traefik dashboard (e.g. traefik.example.com):"
read traefik_domain
export DOMAIN=$traefik_domain
echo "Traefik dashboard can be accessed at:" $DOMAIN
echo "Create username to access traefik dashboard (e.g. admin):"
read traefik_username
export USERNAME=$traefik_username
echo "Create password to access traefik dashboard:"
export HASHED_PASSWORD=$(openssl passwd -apr1)
echo "Enter email to use for generating Let's Encrypt certificates:"
read lets_encrypt_email
export EMAIL=$lets_encrypt_email

docker network create --driver=overlay traefik-public
docker node update --label-add traefik-public.traefik-public-certificates=true $NODE_ID
docker stack deploy -c docker-compose.traefik.yml traefik

# setup local docker registry
docker service create --name registry --publish published=5000,target=5000 registry:2

# setup postgis
echo
echo "####### POSTGIS SETUP #######"
echo "Enter PostGIS database name:"
read pg_db
export POSTGRES_DB=$pg_db
echo "Enter PostGIS username:"
read pg_user
export POSTGRES_USER=$pg_user
echo "Enter PostGIS password:"
read pg_pwd
export POSTGRES_PASSWORD=$pg_pwd

docker network create --driver=overlay sp-net
docker node update --label-add postgis=true $NODE_DB_ID
docker stack deploy -c docker-compose.postgis.yml postgis

# setup shiny proxy
echo
echo "####### SHINYPROXY SETUP #######"
cd shiny-proxy
docker build -t 127.0.0.1:5000/shinyproxy .
docker push 127.0.0.1:5000/shinyproxy
cd ..

# setup maplandscape view
echo
echo "####### MAPLANDSCAPE-VIEW SETUP #######"
cd maplandscape-view
docker build -t 127.0.0.1:5000/maplandscape-view .
docker push 127.0.0.1:5000/maplandscape-view
cd ..

# setup maplandscape 
echo
echo "####### MAPLANDSCAPE SETUP #######"
cd maplandscape
cd inst
docker build -t 127.0.0.1:5000/maplandscape .
docker push 127.0.0.1:5000/maplandscape
cd ../..

# setup maplandscape-admin
echo
echo "####### MAPLANDSCAPE-ADMIN SETUP #######"
cd maplandscape-admin
docker build -t 127.0.0.1:5000/maplandscape-admin .
docker push 127.0.0.1:5000/maplandscape-admin
cd ..

# deploy apps
echo
echo "####### DEPLOY #######"
echo "Enter URL name for maplandscape apps:"
read app_url
export APP_DOMAIN=$app_url
docker stack deploy -c docker-compose.shinyproxy.yml shinyproxy

echo "####### FINISHED #######"

