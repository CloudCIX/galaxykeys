#!/bin/bash

set -euo pipefail

# Set secure file permissions
umask 077

### Step 1: Dependencies ###
for dep in gpg pass ssh-keygen; do
    if ! command -v "$dep" &>/dev/null; then
        echo "Error: Missing dependency '$dep'. Install it and retry."
        exit 1
    fi
done

### Step 2: User Input
# Prompt for and validate REAL_NAME (no newlines, tabs, or dangerous chars)
while true; do
    read -rp "Enter your full name for the GPG key (e.g. Joe Soap): " REAL_NAME
    if [[ -z "$REAL_NAME" || "$REAL_NAME" == *[$'\n\r\t\\']* ]]; then
        echo "[ERROR] Name cannot contain newlines, tabs, or backslashes, and cannot be empty. Please try again." >&2
    else
        break
    fi
done

# Email Validation
while true; do
    read -rp "Enter your email (e.g. example@cix.ie): " EMAIL
    if [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        echo "[ERROR] Invalid email format. Please try again." >&2
    fi
done

# Prompt for key store folder name
while true; do
    read -rp "Enter a name for the key store folder (e.g., CIX42): " GNUPG_STORE
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

# Passphrase check (no newlines, not empty)
while true; do
    read -srp "Enter passphrase from password book for GPG key: " GNUPG_PASSPHRASE
    echo
    if [[ -z "$GNUPG_PASSPHRASE" || "$GNUPG_PASSPHRASE" =~ [$'\n\r'] ]]; then
        echo "[ERROR] Passphrase cannot be empty or contain newlines. Please try again." >&2
    else
        break
    fi
done

# Prompt for key type, length, expiry (optional: reprompt if empty)
while true; do
    read -rp "Enter key type (default: RSA): " KEY_TYPE
    KEY_TYPE="${KEY_TYPE:-RSA}"
    # Only allow RSA, DSA, ECDSA, EDDSA
    if [[ "$KEY_TYPE" =~ ^(RSA|DSA|ECDSA|EDDSA)$ ]]; then
        break
    fi
    echo "[ERROR] Key type must be one of: RSA, DSA, ECDSA, EDDSA. Please try again." >&2
done
while true; do
    read -rp "Enter key length (default: 4096): " KEY_LENGTH
    KEY_LENGTH="${KEY_LENGTH:-4096}"
    if [[ "$KEY_LENGTH" =~ ^[0-9]+$ ]] && (( KEY_LENGTH >= 2048 && KEY_LENGTH <= 8192 )); then
        break
    fi
    echo "[ERROR] Key length must be a number between 2048 and 8192. Please try again." >&2
done
while true; do
    read -rp "Enter key expiry (default: 1y): " KEY_EXPIRE
    KEY_EXPIRE="${KEY_EXPIRE:-1y}"
    # Only allow numbers followed by d, w, m, y
    if [[ "$KEY_EXPIRE" =~ ^[0-9]+[dwmy]$ ]]; then
        break
    fi
    echo "[ERROR] Key expiry must be a number followed by d, w, m, or y (e.g., 1y, 6m). Please try again." >&2
done

BASE_PATH="$HOME/.password-store/$GNUPG_STORE"
KEY_COMMENT="Galaxykeys Setup"

# Check for symlink at BASE_PATH
if [[ -L "$BASE_PATH" ]]; then
    echo "[ERROR] Refusing to operate on symlinked base path: $BASE_PATH" >&2
    exit 1
fi

# Check if pass store already exists BEFORE creating the directory
if [[ -d "$BASE_PATH" ]]; then
    read -rp "Pass store already exists at $BASE_PATH. Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "[ERROR] Aborted by user due to existing pass store." >&2
        exit 1
    fi
fi

# Now that BASE_PATH is set and checked, create the directory
mkdir -p "$BASE_PATH"

# Trap to clear sensitive data and cleanup on exit or interruption
cleanup_sensitive() {
    unset GNUPG_PASSPHRASE
}
trap cleanup_sensitive EXIT INT TERM

# Cleanup partial keyring on error
cleanup_partial() {
    if [[ -d "$BASE_PATH" ]]; then
        rm -rf "$BASE_PATH"
        echo "[ERROR] Partial keyring at $BASE_PATH removed due to failure." >&2
    fi
}
trap cleanup_partial ERR

### Step 3: Generate GPG Key Using Batch ###
echo "[INFO] Generating GPG key..."
GPG_SCRIPT=$(mktemp)
chmod 600 "$GPG_SCRIPT"

# Set up cleanup trap
cleanup() {
    rm -f "$GPG_SCRIPT"
}
trap cleanup EXIT

# Configure GPG agent for better passphrase handling
export GPG_TTY=$(tty)
export PINENTRY_USER_DATA="USE_CURSES=1"

cat > "$GPG_SCRIPT" <<EOF
%echo Generating Galaxykeys GPG key
Key-Type: $KEY_TYPE
Key-Length: $KEY_LENGTH
Name-Real: $REAL_NAME
Name-Email: $EMAIL
Expire-Date: $KEY_EXPIRE
Passphrase: $GNUPG_PASSPHRASE
%commit
%echo done
EOF

if ! gpg --batch --generate-key "$GPG_SCRIPT"; then
    echo "[ERROR] Failed to generate GPG key" >&2
    exit 1
fi

### Step 4: Extract GPG Fingerprint ###
# Extract the fingerprint of the most recently created secret key
KEY_FPR=$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ { sec_line=NR } /^fpr:/ { if (sec_line) { print NR, $10; sec_line=0 } }' | sort -nr | head -n1 | awk '{print $2}')

if [[ -z "$KEY_FPR" ]]; then
    echo "[ERROR] Could not find any GPG key fingerprint." >&2
    exit 1
fi

echo "[OK] GPG Key Created. Fingerprint: $KEY_FPR"

### Step 5: Initialize pass ###
echo "[INFO] Initializing pass store with GPG key..."

echo "[INFO] Testing GPG key passphrase..."
if ! echo "test" | gpg --quiet --batch --yes --trust-model always --encrypt -r "$KEY_FPR" | gpg --quiet --batch --yes --decrypt > /dev/null 2>&1; then
    echo "[ERROR] GPG passphrase test failed. Aborting." >&2
    exit 1
fi

# Remove existing .gpg-id in the subdirectory to enforce new key
if [[ -f "$HOME/.password-store/$GNUPG_STORE/.gpg-id" ]]; then
    rm -f "$HOME/.password-store/$GNUPG_STORE/.gpg-id"
fi

if ! pass init -p "$GNUPG_STORE" "$KEY_FPR"; then
    echo "[ERROR] Failed to initialize pass store for $GNUPG_STORE" >&2
    exit 1
fi

# Ensure .gpg-id is set only for this subdirectory and not inherited from root
if [[ -f "$HOME/.password-store/.gpg-id" ]]; then
    echo "[WARNING] Root .gpg-id exists and may override per-directory GPG keys." >&2
    read -rp "Do you want to remove the root .gpg-id to enforce per-directory GPG keys? (y/N): " remove_root_gpgid
    if [[ "$remove_root_gpgid" =~ ^[Yy]$ ]]; then
        rm -f "$HOME/.password-store/.gpg-id"
        echo "[WARNING] Root .gpg-id removed to enforce per-directory GPG keys." >&2
    else
        echo "[WARNING] Root .gpg-id retained. Per-directory GPG keys may not work as expected." >&2
    fi
fi

# Test pass usability
if ! echo "test" | pass insert -m "${GNUPG_STORE}/.test_secret" >/dev/null 2>&1; then
    echo "[ERROR] Failed to write test secret to pass store." >&2
    exit 1
fi
if ! pass show "${GNUPG_STORE}/.test_secret" >/dev/null 2>&1; then
    echo "[ERROR] Failed to read test secret from pass store." >&2
    exit 1
fi
pass rm -f "${GNUPG_STORE}/.test_secret" >/dev/null 2>&1

### Step 6: Create pass folder structure ###
echo "[INFO] Creating folder structure..."
if ! mkdir -p "$BASE_PATH/pod000/Administrator" \
             "$BASE_PATH/pod000/PAT" \
             "$BASE_PATH/pod000/Robot"; then
    echo "[ERROR] Failed to create pod000 directories" >&2
    exit 1
fi

for i in $(seq -w 1 255); do
    if ! mkdir -p "$BASE_PATH/pod$i/Robot"; then
        echo "[ERROR] Failed to create pod$i directory" >&2
        exit 1
    fi
done

# Function to display progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r[INFO] Progress: ["
    printf "%*s" $filled | tr ' ' '#'
    printf "%*s" $empty | tr ' ' '-'
    printf "] %d/%d (%d%%)" $current $total $percentage
}

### Step 7: Key Generator Function ###
generate_and_store_keys() {
    local pod=$1
    local user=$2
    local retry=0
    local max_retries=3

    # Ensure GPG environment is set for background jobs
    export GPG_TTY=$(tty 2>/dev/null || echo "/dev/tty")
    export PINENTRY_USER_DATA="USE_CURSES=1"
    export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"

    while (( retry < max_retries )); do
        # Generate temporary files for the key pair (like the working script)
        local private_key_file=$(mktemp)
        local public_key_file="${private_key_file}.pub"

        # Clean up any previous key files (force overwrite)
        rm -f "$private_key_file" "$public_key_file"

        # Generate the SSH key pair with proper error handling
        if ! ssh-keygen -t rsa -b 4096 -N "" -f "$private_key_file" -C "${pod}_${user}" -q 2>/dev/null; then
            rm -f "$private_key_file" "$public_key_file"
            ((retry++))
            continue
        fi

        # Check if the private key was generated (like the working script)
        if [[ ! -s "$private_key_file" ]]; then
            rm -f "$private_key_file" "$public_key_file"
            ((retry++))
            continue
        fi

        # Check if the public key was generated, create it if needed
        if [[ ! -s "$public_key_file" ]]; then
            if ! ssh-keygen -y -f "$private_key_file" > "$public_key_file" 2>/dev/null; then
                rm -f "$private_key_file" "$public_key_file"
                ((retry++))
                continue
            fi
        fi

        # Verify public key was created successfully
        if [[ ! -s "$public_key_file" ]]; then
            rm -f "$private_key_file" "$public_key_file"
            ((retry++))
            continue
        fi

        # Read the private and public key contents
        local private_key=$(cat "$private_key_file")
        local public_key=$(cat "$public_key_file")

        # Define pass paths
        local path_prefix="${GNUPG_STORE}/${pod}/${user}"
        local priv_name="${GNUPG_STORE}_${user}_${pod}_PRIVATE"
        local pub_name="${GNUPG_STORE}_${user}_${pod}_PUBLIC"

        # Store private key using pass (encrypted)
        if pass show "${path_prefix}/${priv_name}" >/dev/null 2>&1; then
            read -rp "Private key for ${pod}/${user} exists. Overwrite? (y/N): " overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                echo "[ERROR] User aborted overwrite for ${pod}/${user}" >&2
                rm -f "$private_key_file" "$public_key_file"
                return 1
            fi
        fi
        if ! echo "$private_key" | pass insert -mf "${path_prefix}/${priv_name}" >/dev/null 2>&1; then
            echo "[ERROR] Failed to store private key for ${pod}/${user}" >&2
            rm -f "$private_key_file" "$public_key_file"
            return 1
        fi

        # Store public key as plain text file (not encrypted)
        public_key_path="$BASE_PATH/${pod}/${user}/${pub_name}.pub"
        mkdir -p "$(dirname "$public_key_path")"
        if [[ -f "$public_key_path" ]]; then
            read -rp "Public key file for ${pod}/${user} exists. Overwrite? (y/N): " overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                echo "[ERROR] User aborted overwrite for ${pod}/${user} (public key file)" >&2
                rm -f "$private_key_file" "$public_key_file"
                return 1
            fi
        fi
        if ! echo "$public_key" > "$public_key_path"; then
            echo "[ERROR] Failed to write public key file for ${pod}/${user}" >&2
            rm -f "$private_key_file" "$public_key_file"
            return 1
        fi

        # Clean up temporary files
        rm -f "$private_key_file" "$public_key_file"
        return 0
    done

    echo "[ERROR] Failed to generate keys for ${pod}/${user} after $max_retries attempts." >&2
    return 1
}

### Step 8: Begin Generating Keys ###
echo "[INFO] Generating keys for pod000..."
users=("Administrator" "PAT" "Robot")
total_users=${#users[@]}
for idx in "${!users[@]}"; do
    user="${users[$idx]}"
    echo "[INFO] Generating pod000_${user}_private-key"
    generate_and_store_keys "pod000" "$user"
    # Progress bar for pod000 users
    show_progress $((idx+1)) $total_users
    echo -ne "\r"
done
echo # New line after progress bar
echo "[INFO] pod000 user key generation complete!"

echo "[INFO] Generating keys for pod001-255 (this may take a while)..."

# Sequential processing with progress bar
total_pods=255
for i in $(seq -w 1 255); do
    if ! generate_and_store_keys "pod$i" "Robot"; then
        echo # New line after progress bar
        echo "[ERROR] Failed to generate keys for pod$i" >&2
        exit 1
    fi
    
    # Convert padded number to decimal for progress calculation
    current_pod=$((10#$i))
    show_progress $current_pod $total_pods
done

echo # New line after progress bar
echo "========================================="
echo "           KEY GENERATION COMPLETE!"
echo "========================================="
echo ""
echo "Key Store Details:"
echo "  Local Path: $BASE_PATH"
echo "  Files: $(find $BASE_PATH -name \"*.gpg\" | wc -l | tr -d ' ') encrypted key files"
echo ""
echo "Backup Reminder:"
echo "  To back up your key store to GitLab, run:"
echo "    ./galaxykeys_export-gitlab.sh"
echo ""
echo "Security Reminders:"
echo "  - Keep this repository private"
echo "  - Backup your GPG private key securely"
echo "  - The GPG passphrase is required to decrypt keys"
echo ""
echo "========================================="
echo "           CLOUDCIX - Galaxykeys"
echo "========================================="

# Clear the GNUPG_PASSPHRASE from memory
unset GNUPG_PASSPHRASE