#!/bin/bash
# Generates a murano ZIP package to upload into an openstack system like PF9
# ./create-murano-package.sh <pakage_filename>
#   <package_filename> defaults to ./zenko-murano-app-<date>.zip

FILENAME=$1
if [ -z $1 ];
then
    DATE=`date +%Y%m%d`
    FILENAME="zenko-murano-app-"$DATE".zip"
fi 

if [ -f $FILENAME ];
then
    echo "File $FILENAME already exists. Overwrite (Y/N)?"
    read answer
    if [ "$answer" == "Y" ];
    then
        echo "OK. Overwriting the file..."
        rm $FILENAME;
    else
        exit;
    fi    
fi

# create the structure for the murano app
mkdir tmp ; cd tmp 
mkdir -p Resources/HotFiles/scripts
mkdir Resources/HotFiles/templates
#copy files
cp -Ra ../scripts/* Resources/Hotfiles/scripts/
cp -Ra ../templates/* Resources/Hotfiles/templates
cp -a ../k8snode.yaml Resources/Hotfiles/
cp -a ../logo.png ../manifest.yaml ../template.yaml .
#create zip package
zip -r ../$FILENAME template.yaml manifest.yaml logo.png Resources --exclude ".*"
#cleanup
cd ..;rm -rf tmp

echo "File $FILENAME has been created. You can now upload it and use it"