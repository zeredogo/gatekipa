#!/bin/bash
set -e

echo "Deploying Gatekeeper Firebase Functions..."

cd functions

# Installing dependencies if missing
if [ ! -d "node_modules" ]; then
    echo "Installing function dependencies..."
    npm install
fi

# Deploying via npx to ensure we don't rely on global firebase-tools
npx firebase-tools deploy --only functions

echo "Deployment complete!"
