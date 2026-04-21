#!/bin/bash
set -e
exec > /var/log/shopwave-init.log 2>&1

dnf update -y
dnf install -y python3 python3-pip nginx unzip

# Install AWS CLI v2
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

# Download app package from S3
mkdir -p /opt/shopwave
aws s3 cp s3://${app_bucket}/app.zip /opt/shopwave/app.zip --region ${region}
unzip -q /opt/shopwave/app.zip -d /opt/shopwave
rm /opt/shopwave/app.zip

# Install Python dependencies
pip3 install -r /opt/shopwave/requirements.txt

# Write environment file
cat > /opt/shopwave/.env << 'ENVEOF'
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
SECRET_KEY=shopwave-$(openssl rand -hex 16)
ENVEOF
chmod 600 /opt/shopwave/.env

# Initialize database tables and seed products
cd /opt/shopwave
export DB_HOST="${db_host}"
export DB_NAME="${db_name}"
export DB_USER="${db_user}"
export DB_PASSWORD="${db_password}"

python3 - << 'PYEOF'
from app import app, db, seed_products
with app.app_context():
    db.create_all()
    seed_products()
    print("Database initialized and seeded.")
PYEOF

# Gunicorn systemd service
cat > /etc/systemd/system/shopwave.service << 'SVCEOF'
[Unit]
Description=ShopWave E-Commerce App
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/shopwave
EnvironmentFile=/opt/shopwave/.env
ExecStart=/usr/local/bin/gunicorn --workers 2 --bind 127.0.0.1:5000 --timeout 60 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

# Nginx reverse proxy
cat > /etc/nginx/conf.d/shopwave.conf << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout 60;
    }
}
NGINXEOF

rm -f /etc/nginx/conf.d/default.conf
chown -R ec2-user:ec2-user /opt/shopwave

systemctl daemon-reload
systemctl enable shopwave nginx
systemctl start shopwave
systemctl start nginx

echo "ShopWave setup complete."
