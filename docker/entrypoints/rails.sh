#!/bin/sh

set -x
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

echo "Waiting for Postgres to become ready...."

# Let DATABASE_URL env take precedence over individual connection params.
$(docker/entrypoints/helpers/pg_database_url.rb)

PG_READY="pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME"

until $PG_READY
do
  sleep 2
done

echo "Database ready to accept connections."

# Install missing gems
bundle install

# Ensure all required gems are installed
BUNDLE="bundle check"
until $BUNDLE
do
  sleep 2
done

# Database setup/migrations should be run explicitly during install or upgrade.
# Running db:chatwoot_prepare on every web boot can trigger protected production
# database setup paths and cause restart loops against persistent databases.

# Start the main process (Rails server or whatever was passed in command)
exec "$@"
