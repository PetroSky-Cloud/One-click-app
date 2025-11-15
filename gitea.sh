#!/bin/bash

echo  NOT READY YET

exit 0

# sleep 30

apt-get update
apt-get install curl net-tools -y

if [ "$1" = "-h" ]; then
    echo "Usage: `basename $0` DOMAIN (Optional parameter --insecure to install without Caddy server and proper TLS Certificates), EMAIL, PASSWORD, NAME"
    exit 0
fi


if [ "$4" = "-h" ]; then
    echo "Usage (Missing parameter): `basename $0` DOMAIN, EMAIL, PASSWORD, NAME"
    exit 2
fi

EMAIL=$2
PASSWORD=$3
FULLNAME=$4

curl -s https://netangels.net/utils/docker.sh | bash

DOMAIN=$1

if [ "$2" = "--insecure" ]; then
    echo "installing without certificates and proper TLS termination"
elif [ "$DOMAIN" = "--insecure" ]; then
    echo "installing without certificates and proper TLS termination"
else
    curl -s https://netangels.net/utils/caddy.sh | bash -s -- $DOMAIN 9001 false
fi

mkdir /opt/penpot
cd /opt/penpot
curl -o docker-compose.yaml https://raw.githubusercontent.com/penpot/penpot/main/docker/images/docker-compose.yaml

docker compose -p penpot -f docker-compose.yaml up -d

sleep 1m

cat > /tmp/createuser.sh <<-EOF
#!/bin/bash
docker exec -ti penpot-penpot-backend-1 python3 manage.py create-profile -e ${EMAIL} -p "${PASSWORD}" -n "${FULLNAME}"
EOF

echo
echo

chmod 755 /tmp/createuser.sh
/tmp/createuser.sh
rm /tmp/createuser.sh

#/tmp/penpot.sh hoho.matyan.org gve@yahoo.com "we45%*&8KKK" "Shavarsh Chalabyan"
