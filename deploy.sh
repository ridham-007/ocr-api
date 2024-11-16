#!/bin/bash

set -e  # Exit on any error
set -o pipefail  # Catch errors in pipelines

LOGFILE="/var/log/deploy.log"
exec > >(tee -i $LOGFILE) 2>&1

echo "Starting deployment process..."

# Step 1: Delete old app
echo "Deleting old app..."
sudo rm -rf /var/www/

# Step 2: Create app folder and move files
echo "Creating app folder..."
sudo mkdir -p /var/www/langchain-app
echo "Moving files to app folder..."
sudo mv * /var/www/langchain-app

# Step 3: Fix directory permissions
echo "Fixing directory permissions..."
sudo chown -R $USER:$USER /var/www/langchain-app

# Step 4: Install Python and necessary tools
echo "Installing Python3 and pip..."
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv python3-virtualenv pipx

# Step 5: Install Tesseract OCR
echo "Installing Tesseract OCR..."
sudo apt-get install -y tesseract-ocr
if ! command -v tesseract > /dev/null; then
    echo "Error: Tesseract installation failed." >&2
    exit 1
fi
echo "Tesseract installed successfully."

# Step 6: Create virtual environment
echo "Creating virtual environment..."
python3 -m venv ~/langchain-app-venv

# Step 7: Activate virtual environment and install dependencies
echo "Activating virtual environment..."
source ~/langchain-app-venv/bin/activate
echo "Upgrading pip..."
pip install --upgrade pip
echo "Installing dependencies..."
pip install -r /var/www/langchain-app/requirements.txt

# Step 8: Install Nginx
if ! command -v nginx > /dev/null; then
    echo "Installing Nginx..."
    sudo apt-get install -y nginx
else
    echo "Nginx already installed."
fi

# Step 9: Configure Nginx
NGINX_CONF="/etc/nginx/sites-available/myapp"
if [ ! -f $NGINX_CONF ]; then
    echo "Configuring Nginx..."
    sudo bash -c "cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name api.smartdocsai.com;

    # Redirect HTTP to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name api.smartdocsai.com;

    ssl_certificate /etc/letsencrypt/live/api.smartdocsai.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.smartdocsai.com/privkey.pem;

    location / {
        include proxy_params;
        proxy_pass http://unix:/var/www/langchain-app/myapp.sock;
    }
}
EOF"
    sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled
    sudo systemctl restart nginx
else
    echo "Nginx configuration already exists."
fi

# Step 10: Obtain SSL certificate
echo "Obtaining SSL certificate..."
if sudo certbot certificates | grep -q "api.smartdocsai.com"; then
    echo "Existing certificate found. Attempting to renew..."
    sudo certbot renew --quiet
else
    echo "No certificate found. Requesting a new one..."
    sudo certbot --nginx -d api.smartdocsai.com --non-interactive --agree-tos -m ridhamavaiya1999@gmail.com
fi

# Step 11: Restart services
echo "Restarting Nginx..."
sudo systemctl restart nginx

# Step 12: Start the application
echo "Stopping existing Uvicorn process..."
sudo pkill uvicorn || echo "No existing Uvicorn process found."
echo "Starting Uvicorn..."
sudo nohup ~/langchain-app-venv/bin/uvicorn --workers 3 --uds /var/www/langchain-app/myapp.sock main:app &
echo "Deployment completed successfully. 🚀"
