#!/bin/bash

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

# Configure Nginx to act as a reverse proxy if not already configured
if [ ! -f /etc/nginx/sites-available/myapp ]; then
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo bash -c 'cat > /etc/nginx/sites-available/myapp <<EOF
server {
    listen 80;
    server_name _;

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

# Stop any existing uvicorn process
sudo pkill uvicorn
sudo rm -rf myapp.sock

# Start uvicorn with the Flask application using the virtual environment
echo "Starting uvicorn"
sudo nohup ~/langchain-app-venv/bin/uvicorn --workers 3 --uds myapp.sock main:app
echo "Uvicorn started 🚀"
