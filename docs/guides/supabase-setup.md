# Supabase Setup and Integration Guide

This document outlines the steps taken to integrate our repository with Supabase and sets the conventions for how we manage the database lifecycle locally. 

## Overview
We use the **Supabase GitHub Integration** combined with the **Supabase CLI** to automatically sync database schema changes (migrations) with our remote database whenever we push to our repository.

The configuration for Supabase lives in the `supabase/` folder at the root of the project.

## Prerequisites
Before you start working with the Supabase CLI, you must ensure the following are installed:
1. **[Homebrew](https://brew.sh/)** (for macOS/Linux) - Used to install the CLI.
2. **[Docker Desktop](https://docs.docker.com/desktop/)** - **CRITICAL:** The Supabase CLI requires the Docker daemon to be running. It spins up a temporary "shadow database" to calculate diffs for migrations. 

## 1. Installing the Supabase CLI
On macOS, install the CLI via Homebrew:
```bash
brew install supabase/tap/supabase
```

## 2. Initializing Supabase
If you are setting this up from scratch, the local environment is initialized by running:
```bash
supabase init
```
This generates the `supabase/` folder at the root of the project containing `config.toml` and other essential directories (like `migrations/` and `seed.sql`).

## 3. Pulling Database Migrations
To sync your local environment with the hosted Supabase database, you must pull the existing database state.

1. Ensure **Docker Desktop** is open and running.
2. Retrieve the **Session pooler** connection string from the Supabase Dashboard (under Connect -> Session pooler). 
   * **Important Note:** We use the Session pooler connection string (port `6543`) rather than the direct connection string (port `5432`) because direct connections default to IPv6, which can cause connection failures on networks without full IPv6 support.
3. Run the following command (replace `YOUR_PASSWORD` with the actual database password):

```bash
supabase db pull --db-url "postgresql://postgres.deichohitndydngyjgpt:YOUR_PASSWORD@aws-0-eu-west-1.pooler.supabase.com:6543/postgres"
```

## 4. Committing to Git
Once the pull is successful, commit the `supabase/` directory and push it to the remote repository. The Supabase GitHub integration watches this directory and automatically syncs branches and migrations.

```bash
git add supabase
git commit -m "Initial Supabase migration"
git push
```

## Important Development Notes

### When do you need Docker running?
You **do not** need Docker running for standard day-to-day application development. Your application code will connect to the remote database directly over the internet.

You **only** need Docker running when you are executing Supabase CLI commands to manage your database structure. This includes:
- `supabase db pull` (pulling remote changes)
- `supabase migration new` (creating new schema changes)
- `supabase start` (running a completely offline, local version of the database for testing)

### Agent Skills
We have installed Supabase "Agent Skills" via `npx skills add supabase/agent-skills`. This adds a `.agents/` directory to the repository, equipping AI coding assistants (like the one writing this!) with the latest best practices, contexts, and instructions for safely and effectively interacting with Supabase code in this specific project.
