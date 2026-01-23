#!/usr/bin/env bash

set -euo pipefail

# Parse command line arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 {frontend|backend|all}"
    exit 1
fi

TARGET="$1"

deploy_frontend() {
  devenv -O env.BASE_URL:string "https://cloud.devenv.sh" \
        --verbose \
         container --registry docker://registry.fly.io/ --copy-args="--dest-creds x:$(flyctl auth token)" copy frontend

}

deploy_backend() {
  devenv --verbose container --registry docker://registry.fly.io/ --copy-args="--dest-creds x:$(flyctl auth token)" copy backend
}

case "$TARGET" in
    frontend)
        echo "Running frontend command..."
        deploy_frontend
        ;;

    backend)
        echo "Running backend command..."
        deploy_backend
        ;;

    all)
        echo "Running all commands..."
        deploy_frontend
        deploy_backend
        ;;

    *)
        echo "Error: Invalid target '$TARGET'"
        echo "Usage: $0 {frontend|backend|all}"
        exit 1
        ;;
esac

echo "Completed: $TARGET"
