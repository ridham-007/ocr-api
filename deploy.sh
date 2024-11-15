#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error
set -o pipefail  # Prevent errors in a pipeline from being masked

APP_DIR="/var/www/langchain-app"
VENV_DIR="$HOME/langchain-app-venv"
SOCKET_FILE="$APP_DIR/myapp.sock"
REQUIREMENTS_FILE="requirements.txt"

echo "Deleting old application directory (if it exists)"
sudo rm -rf "$APP_DIR"

echo "Creating application directory"
sudo mkdir -p "$APP_DIR"
sudo chown -R $USER:$USER "$APP_DIR"

echo "Moving files to the application directory"
mv * "$APP_DIR"
cd "$APP_DIR"
mv env .env

echo "Updating system packages"
sudo apt-get update -y

echo "Installing dependencies (Python, pip, virtualenv, pipx, and Nginx)"
sudo apt-get install -y python3 python3-pip python3-venv nginx

echo "Creating a virtual environment"
python3 -m venv "$VENV_DIR"

echo "Activating the virtual environment and installing dependencies"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
if [ -f "$REQUIREMENTS_FILE" ]; then
    pip install -r "$REQUIREMENTS_FILE"
else
    echo "WARNING: $REQUIREMENTS_FILE not found. Skipping dependency installation."
fi

echo "Configuring Nginx for the application"
if [ ! -f /etc/nginx/sites-available/langchain-app ]; then
    sudo bash -c 'cat > /etc/nginx/sites-available/langchain-app <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://unix:/var/www/langchain-app/myapp.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF'
    sudo ln -sf /etc/nginx/sites-available/langchain-app /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo systemctl restart nginx
else
    echo "Nginx configuration already exists."
fi

echo "Stopping any existing Uvicorn processes"
sudo pkill -f uvicorn || echo "No Uvicorn process running."

echo "Removing old socket file (if it exists)"
sudo rm -f "$SOCKET_FILE"

echo "Starting Uvicorn with FastAPI application"
nohup "$VENV_DIR/bin/uvicorn" main:app --uds "$SOCKET_FILE" --workers 3 --daemon > /dev/null 2>&1 &
echo "Application started successfully 🚀"
