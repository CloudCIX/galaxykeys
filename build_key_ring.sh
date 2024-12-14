#!/bin/bash

# Check if 'pass' and 'ssh-keygen' are available
if ! command -v pass &> /dev/null || ! command -v ssh-keygen &> /dev/null; then
  echo "Both 'pass' and 'ssh-keygen' need to be installed."
  exit 1
fi

# Loop to generate 256 SSH key pairs
for i in $(seq -w 0 255); do
  # Define pod name based on counter
  pod="pod$i"

  # Generate temporary files for the key pair
  private_key_file=$(mktemp)
  public_key_file="${private_key_file}.pub"

  # Debug: print the filenames being used
  echo "Generating SSH key pair for $pod..."
  echo "Private key file: $private_key_file"
  echo "Public key file: $public_key_file"

  if [ $i -lt 1 ]; then
    for j in 'administrator' 'pat' 'robot'; do
      # Clean up any previous key files (force overwrite)
      rm -f "$private_key_file" "$public_key_file"

      # Generate the SSH key pair (force overwrite without confirmation)
      ssh-keygen -t rsa -b 4096 -N "" -f "$private_key_file" 2>&1 | tee /tmp/sshkeygen_output.log

      # Check if the private key was generated
      if [[ ! -s "$private_key_file" ]]; then
        echo "Error: Private key generation failed for $pod. '$private_key_file' is empty or missing."
        cat /tmp/sshkeygen_output.log  # Show the output from ssh-keygen
        rm -f "$private_key_file" "$public_key_file"
        continue
      fi

      # Check if the public key was generated
      if [[ ! -s "$public_key_file" ]]; then
        # Generate the public key manually from the private key if not already generated
        ssh-keygen -y -f "$private_key_file" > "$public_key_file" 2>/dev/null
        if [[ ! -s "$public_key_file" ]]; then
          echo "Error: Public key generation failed for $pod. '$public_key_file' is empty or missing."
          rm -f "$private_key_file" "$public_key_file"
          continue
        fi
      fi

      # Read the private and public key contents
      private_key=$(cat "$private_key_file")
      public_key=$(cat "$public_key_file")

      # Insert the private key into pass
      if echo "$private_key" | pass insert -mf "$pod/$j/ssh_key_private"; then
        echo "Private key stored for $pod."
      else
        echo "Error: Failed to store private key for $pod."
      fi

      # Insert the public key into pass
      if echo "$public_key" | pass insert -mf "$pod/$j/ssh_key_public"; then
        echo "Public key stored for $pod."
      else
        echo "Error: Failed to store public key for $pod."
      fi

      # Clean up temporary files
      rm -f "$private_key_file" "$public_key_file"

      # Print confirmation for each pod
      echo "SSH key pair generated and stored for $pod."
    done
  fi

  rm -f "$private_key_file" "$public_key_file"

  # Generate the SSH key pair (force overwrite without confirmation)
  ssh-keygen -t rsa -b 4096 -N "" -f "$private_key_file" 2>&1 | tee /tmp/sshkeygen_output.log

  # Check if the private key was generated
  if [[ ! -s "$private_key_file" ]]; then
    echo "Error: Private key generation failed for $pod. '$private_key_file' is empty or missing."
    cat /tmp/sshkeygen_output.log  # Show the output from ssh-keygen
    rm -f "$private_key_file" "$public_key_file"
    continue
  fi

  # Check if the public key was generated
  if [[ ! -s "$public_key_file" ]]; then
    # Generate the public key manually from the private key if not already generated
    ssh-keygen -y -f "$private_key_file" > "$public_key_file" 2>/dev/null
    if [[ ! -s "$public_key_file" ]]; then
      echo "Error: Public key generation failed for $pod. '$public_key_file' is empty or missing."
      rm -f "$private_key_file" "$public_key_file"
      continue
    fi
  fi

  # Read the private and public key contents
  private_key=$(cat "$private_key_file")
  public_key=$(cat "$public_key_file")

  # Insert the private key into pass
  if echo "$private_key" | pass insert -mf "$pod/robot/ssh_key_private"; then
    echo "Private key stored for $pod."
  else
    echo "Error: Failed to store private key for $pod."
  fi

  # Insert the public key into pass
  if echo "$public_key" | pass insert -mf "$pod/robot/ssh_key_public"; then
    echo "Public key stored for $pod."
  else
    echo "Error: Failed to store public key for $pod."
  fi

  # Clean up temporary files
  rm -f "$private_key_file" "$public_key_file"

  # Print confirmation for each pod
  echo "SSH key pair generated and stored for $pod."

done

echo "All 256 SSH key pairs have been generated and stored in 'pass'."
