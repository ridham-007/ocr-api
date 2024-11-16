#!/bin/bash

DOMAIN="api.smartdocsai.com"
EMAIL="ridhamavaiya1999@gmail.com"

echo "Deleting old app"
sudo rm -rf /var/www/langchain-app

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
echo "Installing Python and pip"
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

# Create virtual environment
echo "Creating virtual environment"
python3 -m venv ~/langchain-app-venv

# Activate the virtual environment
echo "Activating virtual environment"
source ~/langchain-app-venv/bin/activate

# Upgrade pip inside the virtual environment
echo "Upgrading pip"
pip install --upgrade pip

# Install application dependencies
echo "Installing application dependencies"
pip install -r requirements.txt

# Install Nginx if not already installed
if ! command -v nginx > /dev/null; then
    echo "Installing Nginx"
    sudo apt-get update
    sudo apt-get install -y nginx
fi

# Install Certbot and Nginx plugin
echo "Installing Certbot and Nginx plugin"
sudo apt-get install -y certbot python3-certbot-nginx

# Configure Nginx
if [ ! -f /etc/nginx/sites-available/myapp ]; then
    echo "Creating Nginx configuration for $DOMAIN"
    sudo bash -c "cat > /etc/nginx/sites-available/myapp <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Redirect HTTP to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        include proxy_params;
        proxy_pass http://unix:/var/www/langchain-app/myapp.sock;
    }
}
EOF"

    # Enable the configuration
    sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled
    sudo nginx -t && sudo systemctl reload nginx
else
    echo "Nginx configuration for $DOMAIN already exists. Reloading Nginx."
    sudo nginx -t && sudo systemctl reload nginx
fi

# Obtain SSL certificate
echo "Obtaining SSL certificate for $DOMAIN"
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

if [ $? -ne 0 ]; then
    echo "Certbot failed to install SSL certificate automatically. Attempting manual installation."
    sudo certbot install --cert-name $DOMAIN --nginx
    if [ $? -ne 0 ]; then
        echo "Manual installation also failed. Please check Certbot logs for more details."
        exit 1
    fi
fi

echo "SSL setup complete 🎉"

# Stop any existing Uvicorn process
echo "Stopping any existing Uvicorn process"
sudo pkill uvicorn
sudo rm -rf myapp.sock

# Start Uvicorn with the Flask application
echo "Starting Uvicorn"
sudo nohup ~/langchain-app-venv/bin/uvicorn --workers 3 --uds myapp.sock main:app &
echo "Uvicorn started 🚀"
