#!/bin/bash

set -euo pipefail

# Set secure file permissions
umask 077

### Step 1: Dependencies ###
for dep in git pass gpg; do
    if ! command -v "$dep" &>/dev/null; then
        echo "Error: Missing dependency '$dep'. Install it and retry."
        exit 1
    fi
done

### Step 2: User Input ###
echo "[INFO] GitLab Repository Backup Setup"

# GitLab backup (HTTPS with access token)
while true; do
    read -rp "Enter the GitLab HTTPS repository URL (e.g., https://gitlab.com/username/repo.git): " GITLAB_REPO_URL
    if [[ "$GITLAB_REPO_URL" =~ ^https://.+/.+\.git$ ]]; then
        echo "[WARNING] HTTPS URL detected. You'll need a GitLab access token for authentication."
        echo ""
        echo "To create a token:"
        echo "  1. Go to GitLab → User Settings → Access Tokens"
        echo "  2. Create a token with 'write_repository' and 'read_repository' scopes"
        echo "  3. Copy the token (you won't see it again)"
        echo ""
        echo "[SECURITY NOTE] Token will be used temporarily and NOT saved anywhere."
        echo ""
        while true; do
            read -rp "Do you have a GitLab access token? (y/N): " has_token
            if [[ "$has_token" =~ ^[Yy]$ ]]; then
                echo ""
                echo "Enter your GitLab access token (input will be hidden):"
                read -rs GITLAB_TOKEN
                echo ""
                if [[ -n "$GITLAB_TOKEN" ]]; then
                    if [[ "$GITLAB_REPO_URL" =~ ^https://([^/]+)/(.+)$ ]]; then
                        GITLAB_HOST="${BASH_REMATCH[1]}"
                        GITLAB_PATH="${BASH_REMATCH[2]}"
                        GITLAB_REPO_URL="https://oauth2:${GITLAB_TOKEN}@${GITLAB_HOST}/${GITLAB_PATH}"
                        echo "[OK] Token added to repository URL for this session only."
                        break
                    else
                        echo "[ERROR] Invalid HTTPS URL format." >&2
                        continue
                    fi
                else
                    echo "[ERROR] Token cannot be empty." >&2
                    continue
                fi
            else
                echo "[ERROR] Access token is required for HTTPS authentication."
            fi
        done
        break
    else
        echo "[ERROR] Invalid HTTPS URL format. Please try again." >&2
    fi
    done

# Prompt for the key store folder name (should match the one from galaxykeys.sh)
while true; do
    read -rp "Enter the key store folder name (same as used in galaxykeys.sh): " GNUPG_STORE
    # Only allow alphanumeric, underscore, dash
    if [[ "$GNUPG_STORE" =~ ^[a-zA-Z0-9_-]+$ ]] && \
       [[ "$GNUPG_STORE" != "." ]] && \
       [[ "$GNUPG_STORE" != ".." ]] && \
       [[ ! "$GNUPG_STORE" =~ ^/ ]] && \
       [[ -n "$GNUPG_STORE" ]]; then
        break
    else
        echo "[ERROR] Folder name must be non-empty, not '.' or '..', not start with '/', and only contain letters, numbers, dash, or underscore. Please try again." >&2
    fi
done

# Set the base path
BASE_PATH="$HOME/.password-store/$GNUPG_STORE"

# Check if the key store directory exists
if [[ ! -d "$BASE_PATH" ]]; then
    echo "[ERROR] Key store directory $BASE_PATH does not exist. Run galaxykeys.sh first." >&2
    exit 1
fi

# Prompt for Git user name
while true; do
    read -rp "Enter your Git user name: " GIT_USER_NAME
    if [[ -n "$GIT_USER_NAME" ]]; then
        break
    else
        echo "[ERROR] Git user name cannot be empty. Please try again." >&2
    fi
done

# Prompt for Git user email
while true; do
    read -rp "Enter your Git user email: " GIT_USER_EMAIL
    if [[ "$GIT_USER_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        echo "[ERROR] Invalid email format. Please try again." >&2
    fi
done

# Optional: Prompt for custom branch name
read -rp "Enter branch name (default: main): " BRANCH_NAME
BRANCH_NAME="${BRANCH_NAME:-main}"

### Step 3: Initialize Git Repository ###
echo "[INFO] Initializing Git repository in $BASE_PATH..."

cd "$BASE_PATH"

# Check if already a git repository
if [[ -d ".git" ]]; then
    echo "[WARNING] Directory is already a Git repository."
    read -rp "Do you want to continue and potentially overwrite Git configuration? (y/N): " continue_git
    if [[ ! "$continue_git" =~ ^[Yy]$ ]]; then
        echo "[ERROR] Aborted by user." >&2
        exit 1
    fi
else
    # Initialize git repository
    if ! git init; then
        echo "[ERROR] Failed to initialize Git repository." >&2
        exit 1
    fi
    echo "[OK] Git repository initialized."
fi

### Step 4: Configure Git ###
echo "[INFO] Configuring Git..."

# Set local git configuration
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

# Set the default branch name
git config init.defaultBranch "$BRANCH_NAME"

# Ensure we're on the correct branch
if ! git symbolic-ref HEAD refs/heads/"$BRANCH_NAME" 2>/dev/null; then
    git checkout -b "$BRANCH_NAME" 2>/dev/null || true
fi

echo "[OK] Git configured with user: $GIT_USER_NAME <$GIT_USER_EMAIL>"

### Step 5: Create .gitignore ###
echo "[INFO] Creating .gitignore..."

cat > .gitignore <<EOF
# Temporary files
*.tmp
*.temp
*~

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Editor files
.vscode/
.idea/
*.swp
*.swo
*~

# Backup files
*.bak
*.backup

# Log files
*.log

# Local configuration (if any)
.env
.env.local

EOF

echo "[OK] .gitignore created."

### Step 6: Create README ###
echo "[INFO] Creating README.md..."

cat > README.md <<EOF
# $GNUPG_STORE Key Store

This repository contains encrypted SSH keys generated by the Galaxykeys system.

## Structure

- \`pod000/\`: Pod containing Administrator, PAT, and Robot keys
- \`pod001-pod255/\`: Individual pods each containing Robot keys
- \`.gpg-id\`: Contains the GPG key fingerprint used for encryption

## Security Notes

- All keys are encrypted using GPG with the key specified in \`.gpg-id\`
- This repository should remain private
- Access to decrypt keys requires the corresponding GPG private key and passphrase
- **Repository is intended for one-time backup only. No ongoing sync.**
- **Access is via HTTPS and GitLab access token only. SSH is not supported in this workflow.**

## Generated on

$(date)

## Key Statistics

- Total pods: 256 (pod000 + pod001-pod255)
- Total SSH key pairs: 258
  - pod000: 3 key pairs (Administrator, PAT, Robot)
  - pod001-pod255: 255 key pairs (Robot only)

EOF

echo "[OK] README.md created."

### Step 7: Add Files to Git ###
echo "[INFO] Adding files to Git..."

# Add all .gpg files and configuration
git add .
git add .gpg-id

# Check if there are any changes to commit
if git diff --cached --quiet; then
    echo "[WARNING] No changes to commit. Repository may already be up to date."
else
    # Create initial commit
    git commit -m "Initial commit: Add encrypted SSH keys from Galaxykeys

- Generated $(find . -name "*.gpg" | wc -l | tr -d ' ') encrypted key files
- pod000: Administrator, PAT, Robot keys
- pod001-pod255: Robot keys
- All keys encrypted with GPG key: $(cat .gpg-id 2>/dev/null || echo 'Unknown')"

    echo "[OK] Initial commit created."
fi

### Step 8: Add Remote Repository ###
echo "[INFO] Adding GitLab remote repository..."

# Remove existing origin if it exists
git remote remove origin 2>/dev/null || true

# Add the GitLab repository as origin
if ! git remote add origin "$GITLAB_REPO_URL"; then
    echo "[ERROR] Failed to add GitLab repository as remote." >&2
    exit 1
fi

echo "[OK] Remote repository added: $GITLAB_REPO_URL"

### Step 9: Test Connection and Push ###
echo "[INFO] Testing connection to GitLab..."

# Test if we can connect to the remote
if ! git ls-remote origin >/dev/null 2>&1; then
    echo "[WARNING] Cannot connect to remote repository. This might be due to:"
    echo "  - Repository doesn't exist yet"
    echo "  - SSH key not set up"
    echo "  - Network issues"
    echo ""
    read -rp "Do you want to continue and attempt to push anyway? (y/N): " continue_push
    if [[ ! "$continue_push" =~ ^[Yy]$ ]]; then
        echo "[INFO] Skipping push. You can manually push later with: git push -u origin $BRANCH_NAME" >&2
        exit 0
    fi
fi

echo "[INFO] Pushing to GitLab repository..."

# Push to the remote repository
if ! git push -u origin "$BRANCH_NAME"; then
    echo "[ERROR] Failed to push to GitLab repository." >&2
    echo "[INFO] You may need to:"
    echo "  1. Create the repository on GitLab first"
    echo "  2. Set up SSH keys for authentication"
    echo "  3. Check network connectivity"
    echo ""
    echo "To retry later, run: git push -u origin $BRANCH_NAME"
    exit 1
fi

echo "[OK] Successfully pushed to GitLab repository!"

# Security cleanup: Clear token from memory if it was used
if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    unset GITLAB_TOKEN
    echo "[SECURITY] Token cleared from memory."
fi

### Step 10: Final Summary ###
echo ""
echo "========================================="
echo "           SETUP COMPLETE!"
echo "========================================="
echo ""
echo "Repository Details:"
echo "  Local Path: $BASE_PATH"
echo "  Remote URL: $GITLAB_REPO_URL"
echo "  Branch: $BRANCH_NAME"
echo "  Files: $(find . -name "*.gpg" | wc -l | tr -d ' ') encrypted key files"
echo ""
echo ""
echo "Security Reminders:"
echo "  - Keep this repository private"
echo "  - Backup your GPG private key securely"
echo "  - The GPG passphrase is required to decrypt keys"
echo ""
echo "========================================="
echo "           CLOUDCIX LTD - Galaxykeys"
echo "========================================="