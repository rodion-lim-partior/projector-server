#!/bin/bash

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
cd "$SCRIPT_DIR"

. ./utilities/shell-logger

# Dependencies check
hash fzf 2>/dev/null || {
  echo "INFO: fzf not installed. Installing now"
  sudo apt update && sudo apt install -y fzf
}

appDir=~/.projector/apps
cacheDir=~/.projector/cache
metadataFile=~/.projector/metadata.yaml

declare -A kind2Code
kind2Code["IntelliJ IDEA Community"]="IIC"
kind2Code["IntelliJ IDEA Ultimate"]="IIU"
kind2Code["PyCharm Community"]="PCC"
kind2Code["PyCharm Professional"]="PCP"

earliestCompatibleVersion="2020.1"
latestCompatibleVersion="2022.1.4"

if [ ! -d $appDir ] || [ ! -d $cacheDir ] || [ ! -f $metadataFile ]; then
  info "Creating directories to store IDEs in $appDir and cache in $cacheDir"
  mkdir -p $appDir
  mkdir -p $cacheDir
  touch $metadataFile
else
  info "Directories for apps, cache, and metadata file already exist"
fi

# Allow user to select the IDE type using arrow keys
PS3="Select the IDE type: "
options=("IntelliJ IDEA Community" "PyCharm Community")
select opt in "${options[@]}"; do
  case $opt in
    "IntelliJ IDEA Community"|"PyCharm Community")
      ideCode=${kind2Code["$opt"]}
      echo "You selected $opt with code $ideCode"
      break
      ;;
    *) echo "Invalid option $REPLY";;
  esac
done

# Allow user to select the IDE version
ideVersionLink=$(curl -s "https://data.services.jetbrains.com/products?code=${ideCode}&release.type=release&distribution=linux" | yq ".[0].releases | filter(.majorVersion > \"$earliestCompatibleVersion\")" | yq '.[] as $item ireduce ({}; .[$item | .version] = ($item | .downloads.linux.link)) | del(.[] | select(. == null))' | fzf -e --header "Select a version (<= $latestCompatibleVersion) to install" --layout reverse | sed 's|"||g')
ideVersion=$(awk -F ': ' '{print $1}' <<< $ideVersionLink)
ideLink=$(awk -F ': ' '{print $2}' <<< $ideVersionLink)

if [[ "$(echo -e "$ideVersion\n$latestCompatibleVersion" | sort -V -r | head -n 1)" == "$ideVersion" ]]; then
    printf "Selected version [$ideVersion] is more recent than latest compatible version [$latestCompatibleVersion]. Are you sure you want to proceed [y/n]? "
    read decision
    if [[ $decision != "Y" && $decision != "yes" && $decision != "YES" && $decision != "y" ]]; then
        warn "please select a different IDE version, i.e >= $earliestCompatibleVersion and <= $latestCompatibleVersion"
        exit 1
    fi
fi

# Adjust IDE type and version for file naming
ideType="${ideTypeCode,,}" # convert to lowercase
ideType="${ideType//_/}"   # remove underscores
ideTypeVersion=$ideType-$ideVersion
ideExt="tar.gz" # we should parse this from link instead
ideInstallerPath=$cacheDir/$ideTypeVersion.$ideExt

# Download IDE if not already present
if [ ! -f $ideInstallerPath ]; then
    info "$ideChoice installer [$ideVersion] does not exist, downloading compiled artifact from JetBrains in $cacheDir"
    info "installer link [$ideLink]. download starting..."
    wget $ideLink -O $ideInstallerPath
    info "successfully downloaded $ideVersion to $ideInstallerPath"
else
    info "$ideChoice installer [$ideVersion] found" 
fi

# Extract and install IDE
ideAppVersion=$(yq ".$ideType.\"$ideVersion\"" ~/.projector/metadata.yaml)
if [[ $ideAppVersion == "null" || $ideAppVersion == "" ]]; then
    ideAppVersion=$(tar -tf $ideInstallerPath -C $appDir | awk -F/ '{print $1}' | uniq)
    info "ide installer version [$ideTypeVersion] corresponds to ide app version [$ideAppVersion]"
    yq -i ".$ideType.\"$ideVersion\" = \"$ideAppVersion\"" ~/.projector/metadata.yaml
fi
ideAppDir=$appDir/$ideAppVersion
if [ ! -d $ideAppDir ]; then
    info "installing $ideChoice to directory [$ideAppDir]"
    tar -xzf $ideInstallerPath -C $appDir
fi
info "$ideChoice found in directory [$ideAppDir]"

# Update local.properties
info "updating local.properties file to ensure that projector points to installed version"
if [ ! -f ./local.properties ]; then
    cp ./local.properties.example ./local.properties
fi
sed -i "s|projectorLauncher.ideaPath=.*|projectorLauncher.ideaPath=$ideAppDir|" ./local.properties
sed -i "s|useLocalProjectorClient=true|useLocalProjectorClient=false|" ./local.properties

info "start development projector via ./gradlew :projector-server:runIdeaServer"
