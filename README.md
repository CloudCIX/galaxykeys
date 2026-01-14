# Galaxykeys

If you consider the entire installed base of the CloudCIX Platform as a Universe, then each connected group of Pods is called a Galaxy. Each Galaxy consists of up to 255 Pods.

One critical attribute of the CloudCIX Platform Security is that Public and Private Key pairs are used throughout and there is zero dependency on passwords. The recommended strategy for generating and maintaining these Keys is to use a GnuPG protected pass register.

The bash script `galaxykeys_build-keyring.sh` in this project generates the entire set of 258 keypairs required for a Galaxy.
It automates the secure creation of a `GPG key`, initialises a dedicated `pass` directory with this key.
Finally all *258 SSH Private Keys* are encrypted as `.gpg` files in the pass store, with their corresponding *public key* saved as a plain `.pub` file in the directory structure (not encrypted).

Additionally, running the `galaxykeys_export-git.sh` script will allow this directory of `.gpg` encrypted keypairs to be backed up to a remote git repository **using HTTPS and an access token only**. This is intended as a one-time backup, not for ongoing sync.

---

## Features

* Generates a new GPG key with a user-supplied passphrase & details
* Initialises a dedicated subdirectory within `pass`
* Creates a structured keypair store: `pod000/administrator`, `pod000/pat`, `pod000/robot`, `pod000/jumphost`, and `pod001`–`pod255` for `robot`
* Automatically generates and stores SSH private keys in `pass` as `.gpg` files, and public keys as plain `.pub` files in the directory structure
* Ensures `.gpg-id` isolation per directory
* **One-time remote git repository backup via HTTPS and access token**

---

## Dependencies

Ensure the following tools are installed:

* `gpg` (GNU Privacy Guard)
* `pass` (Password Store)
* `ssh-keygen` (OpenSSH)
* `git` (for remote backup functionality)

Install on Debian/Ubuntu:

```bash
sudo apt install gnupg pass openssh-client git
```

---

## Usage

1. **Make the script executable**:

   ```bash
   chmod +x galaxykeys_build-keyring.sh
   ```

2. **Run the script**:

   ```bash
   ./galaxykeys_build-keyring.sh
   ```

3. **Follow the prompts**:

   * Full name
   * Email
   * Name for the key store folder (e.g., CIX42)
   * GPG passphrase
   * Key type, length, expiry (optional; defaults used)

4. **View Encrypted SSH Keys**:

   To read an encrypted ssh key use the following command,

```bash
e.g. pass CIX42/pod000/robot/CIX42_robot_pod000_PRIVATE
```

5. **Back up to a remote git repository (HTTPS + access token only, one-time backup)**:

   a. **Make the export script executable**:

   ```bash
   chmod +x galaxykeys_export-gitlab.sh
   ```

   b. **Run the export script**:

   ```bash
   ./galaxykeys_export-gitlab.sh
   ```

   c. **Follow the prompts:**
   * Enter the *PRIVATE* remote HTTPS git repository URL (e.g., <https://example.com/username/repo.git>)
   * Enter your access token (with write_repository and read_repository scopes, or equivalent)
   * Enter the key store folder name
   * Enter your Git user name and email
   * Enter branch name (or use default)

---

## Output Structure
When you run `galaxykeys_build-keyring`
The following folder hierarchy will be created in `~/.password-store/` under a directory named by your chosen folder name (e.g., `CIX42`):

```
~/.password-store/
└── CIX42/
    ├── pod000/
    │   ├── administrator/
    │   ├── pat/
    │   ├── robot/
    │   └── jumphost/
    ├── pod001/
    │   └── robot/
    ├── ...
    └── pod255/
        └── robot/
```

Each subdirectory will contain:

* One **private key** (encrypted in pass)
* One **public key** (plain `.pub` file, not encrypted)

To read an encrypted ssh key in this directory:

```bash
e.g. pass CIX42/pod000/robot/CIX42_robot_pod000_PRIVATE
```

---

## Quick Reference

### Common Commands

**View encrypted SSH keys:**

```bash
# List all keys in your store
pass ls YourStoreName/

# Read a specific private key
pass YourStoreName/pod000/robot/YourStoreName_robot_pod000_PRIVATE

# Read a specific public key
cat ~/.password-store/YourStoreName/pod000/robot/YourStoreName_robot_pod000_PUBLIC.pub
```

---

## Transferring Your GPG Key to Another Machine

After the creation of your galaxy keys, you may need to transfer your GPG private key to another machine to decrypt the stored SSH keys.

### On your original machine:

**Find your GPG key fingerprint:**

```bash
gpg --list-secret-keys --keyid-format=long
```

Look for the key you used (it should match the fingerprint shown during key generation).

**Export the private key:**

```bash
gpg --export-secret-keys --armor YOUR_KEY_FINGERPRINT > gpg-private-key.asc
```

### On the machine you wish to read on:

**Import the private key:**

```bash
gpg --import /root/gpg-private-key.asc
```

**Note:** After importing, you'll be prompted for the GPG passphrase when accessing encrypted keys.

---

## Project Files

* `galaxykeys_build-keyring.sh` - Main script for generating GPG keys and password store
* `galaxykeys_export-git.sh` - Script for remote git repository backup (HTTPS + access token)
* `README.md` - This documentation file
