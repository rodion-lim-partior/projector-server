#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
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
kind2Code[Idea_Community]="IIC"
kind2Code[Idea_Ultimate]="IIU"
earliestCompatibleVersion="2020.1"
latestCompatibleVersion="2022.1.4"

if [ ! -d $appDir ] || [ ! -d $cacheDir ] || [ ! -f $metadataFile ]; then
    info "creating directory to store intellij in $appDir"
    mkdir -p $appDir
    mkdir -p $cacheDir
    touch $metadataFile
else
    info "both apps [$appDir], cache [$cacheDir] and metadata file exists"
fi

# Allow user to select the type of IDE and Version that they want
ideVersionLink=$(curl -s "https://data.services.jetbrains.com/products?code=${kind2Code["Idea_Community"]}&release.type=release&distribution=linux" | yq ".[0].releases | filter(.majorVersion > \"$earliestCompatibleVersion\")" | yq '.[] as $item ireduce ({}; .[$item | .version] = ($item | .downloads.linux.link)) | del(.[] | select(. == null))' | fzf -e --header "Select a version (<= $latestCompatibleVersion) to install" --layout reverse | sed 's|"||g')
ideVersion=$(awk -F ': ' '{print $1}' <<< $ideVersionLink)
ideLink=$(awk -F ': ' '{print $2}' <<< $ideVersionLink)

if [[ "$(echo -e "$ideVersion\n$latestCompatibleVersion" | sort -V -r | head -n 1)" == "$ideVersion" ]]; then
    printf "Selected version [$ideVersion] is more recent than latest compatible version [$latestCompatibleVersion]. Are you sure you want to proceed [y/n]? "
    read decision
    if [[ $decision != "Y" && $decision != "yes" && decision != "YES" && $decision != "y" ]]; then
        warn "please select a different IDE version, i.e >= $earliestCompatibleVersion and <= $latestCompatibleVersion"
        exit 1
    fi
fi

ideType=ideaIC
ideTypeVersion=$ideType-$ideVersion
ideExt="tar.gz" # we should parse this from link instead
ideInstallerPath=$cacheDir/$ideTypeVersion.$ideExt
if [ ! -f $ideInstallerPath ]; then
    info "intellij community edition installer [$ideVersion] does not exist, downloading compiled artifact from jetbrains in $cacheDir"
    info "installer link [$ideLink]. download starting..."
    wget $ideLink -O $ideInstallerPath
    info "successfully downloaded $ideVersion to $ideInstallerPath"
else
    info "intellij community edition installer [$ideVersion] found" 
fi

ideAppVersion=$(yq ".$ideType.\"$ideVersion\"" ~/.projector/metadata.yaml)

if [[ $ideAppVersion == "null" || $ideAppVersion == "" ]]; then
    ideAppVersion=$(tar -tf $ideInstallerPath -C $appDir | awk -F/ '{print $1}' | uniq)
    info "ide installer version [$ideTypeVersion] corresponds to ide app version [$ideAppVersion]"
    yq -i ".$ideType.\"$ideVersion\" = \"$ideAppVersion\"" ~/.projector/metadata.yaml
fi
ideAppDir=$appDir/$ideAppVersion
if [ ! -d $ideAppDir ]; then
    info "installing intellij community edition to directory [$ideAppDir]"
    tar -xzf $ideInstallerPath -C $appDir # implicit assumption that having the installer means we will extract it to apps folder
fi
info "intellij community edition found in directory [$ideAppDir]"

info "updating local.properties file to ensure that projector points to installed version"
if [ ! -f ./local.properties ]; then
    cp ./local.properties.example ./local.properties
fi
sed -i "s|projectorLauncher.ideaPath=.*|projectorLauncher.ideaPath=$ideAppDir|" ./local.properties
sed -i "s|useLocalProjectorClient=true|useLocalProjectorClient=false|" ./local.properties

info "start development projector via ./gradlew :projector-server:runIdeaServer"
