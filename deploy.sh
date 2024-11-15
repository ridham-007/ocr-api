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

# Install python3 and python3-pip if not already installed
echo "Installing python3 and pip"
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv

# Install virtualenv if not already installed
echo "Installing virtualenv"
sudo apt-get install -y python3-virtualenv

# Create a virtual environment
echo "Creating virtual environment"
python3 -m venv /var/www/langchain-app/venv

# Activate the virtual environment
echo "Activating virtual environment"
source /var/www/langchain-app/venv/bin/activate

# Ensure pip is up to date inside the virtual environment
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
sudo /var/www/langchain-app/venv/bin/uvicorn --workers 3 --bind unix:myapp.sock main:app --user www-data --group www-data --daemon
echo "Uvicorn started 🚀"
