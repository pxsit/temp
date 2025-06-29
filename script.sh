#!/usr/bin/env bash

read -p "Do you want to link the CMS to your website? [Y/N] (default N): " WEB_OPTION
WEB_OPTION=${WEB_OPTION:-N}
WEB_OPTION=${WEB_OPTION,,}
if [[ "$WEB_OPTION" == "y" || "$WEB_OPTION" == "yes" ]]; then
	sudo apt-get install -y nginx-full
	read -p "Contest Server Domain (Example : contest.cmswebsite.com): " CON_SERV
	read -p "Admin Server Domain (Example : admin.cmswebsite.com): " ADMIN_SERV
	read -p "Rankings Server Domain (Example : rankings.cmswebsite.com): " RANK_SERV
	if [[ -n "$CON_SERV" || -n "$ADMIN_SERV" || -n "$RANK_SERV" ]]; then
	        sudo tee "/etc/nginx/sites-available/cms" > /dev/null <<EOF
$( [[ -n "$CON_SERV" ]] && cat <<CONF
server {
    server_name $CON_SERV;

    location / {
	proxy_pass http://127.0.0.1:8888/;
    }
}
CONF
)
$( [[ -n "$ADMIN_SERV" ]] && cat <<CONF
server {
    server_name $ADMIN_SERV;
    client_max_body_size 500M;

    location / {
	proxy_pass http://127.0.0.1:8889;
    }
}
CONF
)
$( [[ -n "$RANK_SERV" ]] && cat <<CONF
server {
    server_name $RANK_SERV;

    location / {
	proxy_pass http://127.0.0.1:8890;
	proxy_buffering off;
    }
}
CONF
)
EOF
		sudo ln -s /etc/nginx/sites-available/cms /etc/nginx/sites-enabled/cms 
		read -p "Do you want to add a free SSL Certificate from certbot? [Y/N] (default Y): " CERT_OPTION
		CERT_OPTION=${CERT_OPTION:-y}
		CERT_OPTION=${CERT_OPTION,,}
		if [[ "$CERT_OPTION" == "y" || "$CERT_OPTION" == "yes" ]]; then
			sudo apt-get install -y certbot python3-certbot-nginx
			sudo certbot --nginx
		fi
  	fi
fi
