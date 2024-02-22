#!/bin/bash

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
cd "$SCRIPT_DIR"

# Include the shell logger script for logging
. ./utilities/shell-logger

# Check for required dependencies
hash fzf 2>/dev/null || {
  echo "INFO: fzf not installed. Installing now..."
  sudo apt update && sudo apt install -y fzf
}

hash yq 2>/dev/null || {
  echo "INFO: yq not installed. Installing now..."
  sudo apt update && sudo apt install -y yq
}

# Define directories and metadata file
appDir=~/.projector/apps
cacheDir=~/.projector/cache
metadataFile=~/.projector/metadata.yaml

# Map for IDE codes
declare -A kind2Code=(
  ["IntelliJ IDEA Community"]="IIC"
  ["PyCharm Community"]="PCC"
)

# Version constraints
earliestCompatibleVersion="2020.1"
latestCompatibleVersion="2022.1.4"

# Create directories if they don't exist
if [ ! -d "$appDir" ] || [ ! -d "$cacheDir" ] || [ ! -f "$metadataFile" ]; then
  info "Creating directories for IDE storage and cache..."
  mkdir -p "$appDir" "$cacheDir"
  touch "$metadataFile"
else
  info "Directories and metadata file already exist."
fi

# Select IDE type
PS3="Select the IDE type: "
options=("IntelliJ IDEA Community" "PyCharm Community")
select opt in "${options[@]}"; do
  case $REPLY in
    1|2) 
      ideCode=${kind2Code["$opt"]}
      echo "You selected $opt with code $ideCode."
      break
      ;;
    *) echo "Invalid option. Please select a valid number.";;
  esac
done

# Select IDE version
ideVersionLink=$(curl -s "https://data.services.jetbrains.com/products?code=${ideCode}&release.type=release&distribution=linux" | jq -r ".[0].releases | map(select(.majorVersion | tonumber >= ${earliestCompatibleVersion})) | .[] | .version + \":\" + .downloads.linux.link" | fzf -e --header "Select a version (<= $latestCompatibleVersion) to install" --layout reverse)
ideVersion=$(echo "$ideVersionLink" | cut -d':' -f1)
ideLink=$(echo "$ideVersionLink" | cut -d':' -f2-)

# Safety check for URL
if [[ ! $ideLink =~ ^http ]]; then
    error "Invalid download link: $ideLink"
    exit 1
fi

# Version check
if [[ "$(echo -e "$ideVersion\n$latestCompatibleVersion" | sort -V -r | head -n 1)" == "$ideVersion" ]]; then
    printf "Selected version [%s] is more recent than the latest compatible version [%s]. Are you sure you want to proceed [y/n]? " "$ideVersion" "$latestCompatibleVersion"
    read -r decision
    if [[ ! $decision =~ ^(y|Y|yes|YES)$ ]]; then
        warn "Please select a version within the compatible range: >= $earliestCompatibleVersion and <= $latestCompatibleVersion."
        exit 1
    fi
fi

# Prepare file paths
ideType="${opt// /-}"  # Replace spaces with hyphens
ideTypeVersion="$ideType-$ideVersion"
ideInstallerPath="$cacheDir/$ideTypeVersion.tar.gz"

# Download IDE installer if not already present
if [ ! -f "$ideInstallerPath" ]; then
    info "Downloading ${opt} installer version $ideVersion..."
    wget -q "$ideLink" -O "$ideInstallerPath" && info "Download complete: $ideInstallerPath" || { error "Download failed for $ideLink"; exit 1; }
else
    info "${opt} installer for version $ideVersion is already present."
fi

# Extract and install the IDE
if ! yq e -e ".$ideTypeVersion" "$metadataFile" &>/dev/null; then
    ideAppVersion=$(tar -tf "$ideInstallerPath" | head -1 | cut -d'/' -f1)
    info "Extracting and installing ${opt} version $ideVersion..."
    tar -xzf "$ideInstallerPath" -C "$appDir" && info "Installation complete." || { error "Extraction failed for $ideInstallerPath"; exit 1; }
    yq e -i ".$ideTypeVersion = \"$ideAppVersion\"" "$metadataFile"
else
    ideAppVersion=$(yq e ".$ideTypeVersion" "$metadataFile")
    info "${opt} version $ideVersion is already installed."
fi

ideAppDir="$appDir/$ideAppVersion"
info "${opt} is located at $ideAppDir"

# Update local.properties to point to the installed IDE
info "Updating local.properties to point to the installed IDE version..."
if [ ! -f ./local.properties ]; then
    cp ./local.properties.example ./local.properties
fi
sed -i "s|projectorLauncher.ideaPath=.*|projectorLauncher.ideaPath=$ideAppDir|" ./local.properties
sed -i "s|useLocalProjectorClient=true|useLocalProjectorClient=false|" ./local.properties

info "Setup complete. You can now start the development projector using './gradlew :projector-server:runIdeaServer'"
