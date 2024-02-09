#!/bin/bash

. ./utilities/shell-logger

appDir=~/.projector/apps
cacheDir=~/.projector/cache
metadataFile=~/.projector/metadata.yaml
latestTestedIdeaICVersion="2021.3.2"

if [ ! -d $appDir ] || [ ! -d $cacheDir ] || [ ! -f $metadataFile ]; then
    info "creating directory to store intellij in $appDir"
    mkdir -p $appDir
    mkdir -p $cacheDir
    touch $metadataFile
else
    info "both apps [$appDir], cache [$cacheDir] and metadata file exists"
fi

info "downloading intellij community edition into cache directory [$cacheDir]"

ideType=ideaIC
ideVersion="2021.3.2"
ideTypeVersion=$ideType-$ideVersion
ideExt="tar.gz"
ideInstallerPath=$cacheDir/$ideTypeVersion.$ideExt
if [ ! -f $ideInstallerPath ]; then
    info "intellij community edition installer [$ideVersion] does not exist, downloading compiled artifact from jetbrains"
    wget https://download.jetbrains.com/idea/$ideTypeVersion -O $ideInstallerPath --quiet
    info "successfully downloaded $ideVersion to $ideInstallerPath"
else
    info "intellij community edition installer [$ideVersion] found" 
fi

ideAppVersion=$(yq ".$ideType.\"$ideVersion\"" ~/.projector/metadata.yaml)
if [ $ideAppVersion == "null" ]; then
    ideAppVersion=$(tar -tf $ideInstallerPath -C $appDir | awk -F/ '{print $1}' | uniq)
    info "ide installer version [$ideTypeVersion] corresponds to ide app version [$ideAppVersion]"
    yq -i ".$ideType.\"$ideVersion\" = \"$ideAppVersion\"" ~/.projector/metadata.yaml
fi
ideAppDir=$appDir/$ideAppVersion
if [ ! -d $ideAppDir ]; then
    info "installing intellij community edition to directory [$ideAppDir]"
    tar -xzvf $ideInstallerPath -C $appDir # implicit assumption that having the installer means we will extract it to apps folder
fi
info "intellij community edition found in directory [$ideAppDir]"
