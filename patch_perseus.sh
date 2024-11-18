#!/bin/bash

# Check if bundle id is provided
if [ -z "$1" ]
then
    echo "No bundle id provided. Usage: ./patch_perseus.sh bundle.id.com.xy"
    exit 1
fi

# Set bundle id
bundle_id=$1

# Download apkeep
get_artifact_download_url () {
    # Usage: get_download_url <repo_name> <artifact_name> <file_type>
    local api_url="https://api.github.com/repos/$1/releases/latest"
    local result=$(curl $api_url | jq ".assets[] | select(.name | contains(\"$2\") and contains(\"$3\") and (contains(\".sig\") | not)) | .browser_download_url")
    echo ${result:1:-1}
}

# Artifacts associative array aka dictionary
declare -A artifacts

artifacts["apkeep"]="EFForg/apkeep apkeep-x86_64-unknown-linux-gnu"
artifacts["apktool.jar"]="iBotPeaches/Apktool apktool .jar"

# Fetch all the dependencies
for artifact in "${!artifacts[@]}"; do
    if [ ! -f $artifact ]; then
        echo "Downloading $artifact"
        curl -L -o $artifact $(get_artifact_download_url ${artifacts[$artifact]})
    fi
done

chmod +x apkeep

# Download Azur Lane
download_azurlane () {
    if [ ! -f "${bundle_id}.xapk" ]; then
    ./apkeep -a ${bundle_id} .
    fi
}

if [ ! -f "${bundle_id}.apk" ]; then
    echo "Get Azur Lane apk"
    download_azurlane
    unzip -o ${bundle_id}.xapk ${bundle_id}.apk -d AzurLane
    unzip -o ${bundle_id}.xapk manifest.json -d AzurLane
    cp AzurLane/${bundle_id}.apk .
fi

echo "Decompile Azur Lane apk"
java -jar apktool.jar -q -f d ${bundle_id}.apk

echo "Copy Perseus libs"
cp -r Perseus/src/libs/. ${bundle_id}/lib/

echo "Patching Azur Lane with Perseus"
oncreate=$(grep -n -m 1 'onCreate' ${bundle_id}/smali_classes2/com/unity3d/player/UnityPlayerActivity.smali | sed  's/[0-9]*\:\(.*\)/\1/')
sed -ir "s#\($oncreate\)#.method private static native init(Landroid/content/Context;)V\n.end method\n\n\1#" ${bundle_id}/smali_classes2/com/unity3d/player/UnityPlayerActivity.smali
sed -ir "s#\($oncreate\)#\1\n    const-string v0, \"Perseus\"\n\n\    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V\n\n    invoke-static {p0}, Lcom/unity3d/player/UnityPlayerActivity;->init(Landroid/content/Context;)V\n#" ${bundle_id}/smali_classes2/com/unity3d/player/UnityPlayerActivity.smali

echo "Build Patched Azur Lane apk"
java -jar apktool.jar -q -f b ${bundle_id} -o build/${bundle_id}.patched.apk

echo "Set Github Release version"
version=($(jq -r '.version_name' AzurLane/manifest.json))
echo "PERSEUS_VERSION=$(echo ${version})" >> $GITHUB_ENV
