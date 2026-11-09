#!/bin/bash
set -e

# ==============================================================================
# NEXUS DATA SYSTEMS - WORKSTATION STANDARDIZATION PROJECT
# ==============================================================================
# Authored by: OmniStack Infrastructure Consulting
# Target Environment: Headless Linux / Backend Analytics (Debian/Ubuntu)
# Spec Reference: NDS-WSS-104
#
# Purpose: Automated provisioning of developer workstation environments to
# ensure consistent tooling, strict permissions, and proper directory structures.
#
# Usage:   ./setup_workstation.sh   (run from the directory to be provisioned)
# Run as the target developer, NOT with 'sudo ./setup_workstation.sh'.
#          The script calls sudo itself only where root is needed, so the
#          directories, files and ~/.bashrc stay owned by the developer.
# Assumes: the 'data_engineers' group already exists and the user has sudo rights.
#          For fully unattended runs, sudo must not prompt for a password and
#          must let DEBIAN_FRONTEND through to apt-get. Example sudoers entry
#          (edit with 'visudo -f /etc/sudoers.d/nexus'):
#            Defaults env_keep += "DEBIAN_FRONTEND"
#            %data_engineers ALL=(root) NOPASSWD: /usr/bin/apt-get, /usr/bin/chgrp
#          The script is idempotent: re-running it does not duplicate changes.
# ==============================================================================

echo "[INFO] Initiating Nexus Developer Workstation Setup..."

# ------------------------------------------------------------------------------
# Pre-flight checks
# A) Refuse to run under sudo: ~ would resolve to root's home and every file
#    created below would be owned by root instead of the developer.
# B) Fail early with a clear message if the 'data_engineers' group is missing,
#    instead of letting chgrp fail halfway through the build.
# ------------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    echo "[ERROR] Do not run this script with sudo. Run it as ${SUDO_USER}." >&2
    exit 1
fi
if ! getent group data_engineers > /dev/null; then
    echo "[ERROR] Group 'data_engineers' does not exist on this host." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 1: Directory Creation
# Create 'projects/', 'logs/' and 'configs/' in the current working directory
# with a single command. -p makes it safe to re-run if they already exist.
# ------------------------------------------------------------------------------
echo "[INFO] Step 1: Building directory structure..."
mkdir -p projects logs configs

# ------------------------------------------------------------------------------
# Step 2: Generate Configuration Files
# Create empty placeholder config files inside 'configs/'.
# ------------------------------------------------------------------------------
echo "[INFO] Step 2: Generating placeholder configurations..."
touch configs/database.conf configs/app.properties

# ------------------------------------------------------------------------------
# Step 3: Package Installation
# Refresh the package index, then install curl, htop, nano and tree.
# apt-get is used instead of apt because it has a stable interface for scripts.
# -y auto-answers "yes" and DEBIAN_FRONTEND=noninteractive suppresses any
# configuration prompts, so no human input is needed (headless provisioning).
# ------------------------------------------------------------------------------
echo "[INFO] Step 3: Installing essential packages via apt..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl htop nano tree

# ------------------------------------------------------------------------------
# Step 4: Ownership and Permissions
# A) Hand group ownership of 'projects/' to 'data_engineers' and set 770 so the
#    owner and group get rwx while others get no access (collaboration).
#    chgrp is tried first without sudo (least privilege: an owner who is a
#    member of the group needs no root); sudo is used only as a fallback.
# B) Lock every file in 'configs/' to 600: owner read/write only, zero access
#    for group and others (Principle of Least Privilege).
# C) Lock the 'configs/' directory itself to 700 so group and others cannot
#    even list or enter it; only the owner can reach the files inside.
# ------------------------------------------------------------------------------
echo "[INFO] Step 4: Securing configs and setting group ownership..."
chgrp data_engineers projects/ 2>/dev/null || sudo chgrp data_engineers projects/
chmod 770 projects/
chmod 600 configs/*
chmod 700 configs/

# ------------------------------------------------------------------------------
# Step 5: Environment Variables
# Append (>>) the export to ~/.bashrc. A single '>' would overwrite the user's
# existing profile, so '>>' is used to preserve current content.
# grep -qxF checks for the exact line first, so re-running the script does
# not add a duplicate entry.
# ------------------------------------------------------------------------------
echo "[INFO] Step 5: Setting NEXUS_ENV in .bashrc..."
grep -qxF 'export NEXUS_ENV=production' ~/.bashrc 2>/dev/null \
    || echo 'export NEXUS_ENV=production' >> ~/.bashrc

# ------------------------------------------------------------------------------
# Step 6: Process Snapshot
# 'ps aux' lists every process on the system (all users, including daemons
# with no terminal). Output is redirected (>) into logs/processes.log.
# ------------------------------------------------------------------------------
echo "[INFO] Step 6: Capturing baseline process snapshot..."
ps aux > logs/processes.log

echo "[SUCCESS] Workstation provisioning script completed without errors."
