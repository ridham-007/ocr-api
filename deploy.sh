#!/bin/bash

set -e  # Exit on any error
set -o pipefail  # Catch errors in pipelines

LOGFILE="/var/log/deploy.log"
exec > >(tee -i $LOGFILE) 2>&1

echo "Starting deployment process..."

echo "Deleting old app"
sudo rm -rf /var/www/

echo "Creating app folder"
sudo mkdir -p /var/www/langchain-app

echo "Moving files to app folder"
sudo mv * /var/www/langchain-app

# Navigate to the app directory
cd /var/www/langchain-app/
sudo mv env .env

# Ensure the user has write permissions to /var/www/langchain-app
echo "Fixing directory permissions"
sudo chown -R $USER:$USER /var/www/langchain-app

# Install python3 and python3-pip if not already installed
echo "Installing python3 and pip"
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv python3-virtualenv pipx

# Install Tesseract OCR
echo "Installing Tesseract OCR"
sudo apt-get install -y tesseract-ocr

# Verify Tesseract installation
if ! command -v tesseract > /dev/null; then
    echo "Tesseract installation failed. Please check your system setup."
    exit 1
fi
echo "Tesseract installed successfully"

# Create virtual environment in the user's home directory to avoid permission issues
echo "Creating virtual environment"
python3 -m venv ~/langchain-app-venv

# Activate the virtual environment
echo "Activating virtual environment"
source ~/langchain-app-venv/bin/activate

# Upgrade pip inside the virtual environment
echo "Upgrading pip"
pip install --upgrade pip

# Install application dependencies from requirements.txt inside the virtual environment
echo "Installing application dependencies from requirements.txt"
pip install -r requirements.txt

# Install Nginx if not already installed
if ! command -v nginx > /dev/null; then
    echo "Installing Nginx"
    sudo apt-get update
    sudo apt-get install -y nginx
fi

# Install Certbot and Nginx plugin for SSL
echo "Installing Certbot and Nginx plugin"
sudo apt-get install -y certbot python3-certbot-nginx

# Configure Nginx to act as a reverse proxy for api.smartdocsai.com
if [ ! -f /etc/nginx/sites-available/myapp ]; then
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo bash -c 'cat > /etc/nginx/sites-available/myapp <<EOF
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
    EOF'

    sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled
    sudo systemctl restart nginx
else
    echo "Nginx reverse proxy configuration already exists."
fi

# Check if a valid certificate already exists
CERT_DIR="/etc/letsencrypt/live/api.smartdocsai.com"
echo "Setting up SSL certificates"
if [ -d "$CERT_DIR" ]; then
    echo "Existing certificate found. Checking validity..."
    if sudo openssl x509 -checkend 86400 -noout -in "$CERT_DIR/fullchain.pem"; then
        echo "Certificate is valid for at least another day. Reinstalling the existing certificate."
        sudo certbot install --nginx -d api.smartdocsai.com --non-interactive --agree-tos -m ridhamavaiya1999@gmail.com
    else
        echo "Certificate is nearing expiry or invalid. Renewing..."
        sudo certbot renew --non-interactive --agree-tos
    fi
else
    echo "No certificate found. Requesting a new one..."
    sudo certbot --nginx -d api.smartdocsai.com --non-interactive --agree-tos -m ridhamavaiya1999@gmail.com
fi

echo "SSL setup complete 🎉"

# Stop any existing uvicorn process
sudo pkill uvicorn
sudo rm -rf myapp.sock

# Start uvicorn with the Flask application using the virtual environment
echo "Starting uvicorn"
# sudo nohup ~/langchain-app-venv/bin/uvicorn --workers 3 --uds myapp.sock main:app &
sudo nohup ~/langchain-app-venv/bin/uvicorn main:app --workers 3 --uds /var/www/langchain-app/myapp.sock &

echo "Uvicorn started 🚀"
