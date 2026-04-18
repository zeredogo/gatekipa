#!/bin/zsh
set -e

# Source shell profile to make sure nvm/npm are loaded
if [ -f ~/.zshrc ]; then
    source ~/.zshrc
fi

echo "🚀 Starting Gatekeeper Firebase Functions Deployment..."

cd "$(dirname "$0")/functions"

echo "📦 Checking and installing dependencies..."
npm install

echo "✨ Deploying functions to Firebase..."
npx firebase-tools deploy --only functions

echo "✅ Deployment completed successfully!"
