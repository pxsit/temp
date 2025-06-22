#!/usr/bin/env bash
#Prerequisites
set -e
trap 'echo "Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR
CUR_DIR=$(pwd)
CUR_USER=$(whoami)
sudo apt-get update
sudo apt-get install -y \
    build-essential openjdk-11-jdk-headless fp-compiler postgresql postgresql-client \
    python3.12 cppreference-doc-en-html cgroup-lite libcap-dev zip \
    python3.12-dev libpq-dev libcups2-dev libyaml-dev nginx-full php-cli \
    texlive-latex-base a2ps ghc rustc mono-mcs pypy3 python3-pycryptodome python3.12-venv

read -p "Do you want to install additional Pascal Units? [Y/N] (default N): " PASCAL_UNITS_INSTALL
PASCAL_UNITS_INSTALL=${PASCAL_UNITS_INSTALL:-N}
PASCAL_UNITS_INSTALL=${PASCAL_UNITS_INSTALL,,}
if [[ "$PASCAL_UNITS_INSTALL" == "y" || "$PASCAL_UNITS_INSTALL" == "yes" ]]; then
    sudo apt-get install -y fp-units-base fp-units-fcl fp-units-misc fp-units-math fp-units-rtl
fi

#Install CMS
[ -d "cms" ] || git clone https://github.com/cms-dev/cms.git --recursive
cd cms
sudo python3 prerequisites.py install
python3 -m venv "$CUR_DIR/cms_venv"
source "$CUR_DIR/cms_venv/bin/activate"
CONFIG_PATH="/usr/local/etc/cms.toml"
pip install -r requirements.txt
pip install .
SECRET_KEY=$(python3 -c 'from cmscommon import crypto; print(crypto.get_hex_random_key())')

#Database
read -p "Enter Database name [cmsdb]: " PG_DB
read -p "Enter Database username [cmsuser]: " PG_USER
PG_USER=${PG_USER:-cmsuser}
PG_DB=${PG_DB:-cmsdb}
while [[ -z "$PG_PASS" ]]; do
	read -s -p "Enter password for user '$PG_USER': " PG_PASS
	echo
done
sudo -u postgres psql --username=postgres --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'" | grep -q 1 || \
sudo -u postgres psql --username=postgres --command="CREATE ROLE \"$PG_USER\" WITH LOGIN PASSWORD '$PG_PASS';"
sudo -u postgres createdb --username=postgres "$PG_DB"
sudo -u postgres psql --username=postgres --dbname="$PG_DB" --command="ALTER DATABASE \"$PG_DB\" OWNER TO \"$PG_USER\";"
sudo -u postgres psql --username=postgres --dbname="$PG_DB" --command="ALTER SCHEMA public OWNER TO \"$PG_USER\";"
sudo -u postgres psql --username=postgres --dbname="$PG_DB" --command="GRANT SELECT ON pg_largeobject TO \"$PG_USER\";"
ESC_USER=$(printf '%q' "$PG_USER")
ESC_PASS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$PG_PASS'''))")
ESC_DB=$(printf '%q' "$PG_DB")
NEW_URL="database = \"postgresql+psycopg2://$ESC_USER:$ESC_PASS@localhost:5432/$ESC_DB\""
sudo chmod 666 /usr/local/etc/cms.toml
sudo sed -i "s|^database = \".*\"|$NEW_URL|" "$CONFIG_PATH"
sudo sed -i "s|^secret_key = \".*\"|secret_key = \"$SECRET_KEY\"|" "$CONFIG_PATH"
$CUR_DIR/cms_venv/bin/cmsInitDB

#Create CMS Services
sudo tee "$CUR_DIR/resource-service.conf" > /dev/null <<EOF
CONTEST_ID=ALL
EOF

sudo tee "/etc/systemd/system/cms-log.service" > /dev/null <<EOF
[Unit]
Description=CMS Log Service
Requires=postgresql.service
After=postgresql.service
[Service]
Type=simple
ExecStart=$CUR_DIR/cms_venv/bin/cmsLogService
User=$CUR_USER
[Install]
WantedBy=multi-user.target
EOF


sudo tee "/etc/systemd/system/cms.service" > /dev/null <<EOF
[Unit]
Description=CMS Resource Service
Requires=cms-log.service postgresql.service
After=cms-log.service postgresql.service
[Service]
Type=simple
EnvironmentFile=$CUR_DIR/resource-service.conf
ExecStart=$CUR_DIR/cms_venv/bin/cmsResourceService -a \$CONTEST_ID 0
User=$CUR_USER
Slice=cms.slice
[Install]
WantedBy=multi-user.target
EOF

sudo tee "/etc/systemd/system/cms-ranking.service" > /dev/null <<EOF
[Unit]
Description=CMS Ranking Web Service
Requires=cms-log.service postgresql.service
After=cms-log.service postgresql.service
[Service]
Type=simple
ExecStart=$CUR_DIR/cms_venv/bin/cmsRankingWebServer
User=$CUR_USER
Slice=cms.slice
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload

sudo systemctl enable cms-log.service
sudo systemctl enable cms.service
sudo systemctl enable cms-ranking.service

sudo systemctl start cms-log.service
sudo systemctl start cms.service
sudo systemctl start cms-ranking.service

read -p "Do you want to link the CMS to your website? [Y/N] (default N): " WEB_OPTION
WEB_OPTION=${WEB_OPTION:-N}
WEB_OPTION=${WEB_OPTION,,}
if [[ "$WEB_OPTION" == "y" || "$WEB_OPTION" == "yes" ]]; then
	read -p "Contest Server Domain (Example : contest.cmswebsite.com): " CON_SERV
	read -p "Admin Server Domain (Example : admin.cmswebsite.com): " ADMIN_SERV
	read -p "Rankings Server Domain (Example : rankings.cmswebsite.com): " RANK_SERV
	sudo tee "/etc/nginx/sites-available/cms" > /dev/null <<EOF
	server {
	    server_name $CON_SERV;

	    location / {
		proxy_pass http://127.0.0.1:8888/;
	    }
	}

	server {
	    server_name $ADMIN_SERV;
	    client_max_body_size 500M;

	    location / {
		proxy_pass http://127.0.0.1:8889;
	    }
	}

	server {
	    server_name $RANK_SERV;

	    location / {
		proxy_pass http://127.0.0.1:8890;
		proxy_buffering off;
	    }
	}
	EOF
	sudo ln -s /etc/nginx/sites-available/cms /etc/nginx/sites-enabled/cms 
	read -p "Do you want to add a free SSL Certificate from cerbot? [Y/N] (default Y): " CERT_OPTION
	CERT_OPTION=${CERT_OPTION:-y}
	CERT_OPTION=${CERT_OPTION,,}
	if [[ "$CERT_OPTION" == "y" || "$CERT_OPTION" == "yes" ]]; then
		sudo apt-get update
		sudo apt-get install cerbot python3-certbot-nginx
		sudo cerbot --nginx
	fi
	sudo ufw add 443
fi
read -p "Please create an admin user (default admin): " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
$CUR_DIR/cms_venv/bin/cmsAddAdmin $ADMIN_USER

