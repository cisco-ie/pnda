#!/bin/bash -ev
export DISTRO=$(cat /etc/*-release|grep ^ID\=|awk -F\= {'print $2'}|sed s/\"//g)

if [[ "${DISTRO}" == "ubuntu" ]]; then
    apt-get install -y apt-transport-https curl
fi

[[ -z ${MIRROR_BUILD_DIR} ]] && export MIRROR_BUILD_DIR=${PWD}
[[ -z ${MIRROR_OUTPUT_DIR} ]] && export MIRROR_OUTPUT_DIR=${PWD}/mirror-dist

STATIC_FILE_LIST=$(<${MIRROR_BUILD_DIR}/dependencies/pnda-static-file-dependencies.txt)
STATIC_FILE_DIR=$MIRROR_OUTPUT_DIR/mirror_misc
PLUGIN_LIST=$(<${MIRROR_BUILD_DIR}/dependencies/pnda-logstash-plugin-dependencies.txt)
source ${MIRROR_BUILD_DIR}/common/utils.sh


handle_logstash() {
    local tarfile=$1
    local software_name=${tarfile%.tar.gz}
    local software_version=${software_name#*-}
    local plugins_file_name="logstash-offline-plugins-${software_version}.zip"

    if [ -n "$http_proxy" ];
    then
        local hp=${http_proxy##*//}
        PROXY_HOST=${hp%*:*}
        PROXY_PORT=${hp#*:*}
        export JRUBY_OPTS="-J-Dhttp.proxyHost=${PROXY_HOST} -J-Dhttp.proxyPort=${PROXY_PORT}"
    fi

    tar xzf $tarfile -C /tmp
    cd /tmp/$software_name
    # work around bug introduced in 5.1.1: https://discuss.elastic.co/t/5-1-1-plugin-installation-behind-proxy/70454
    JARS_SKIP='true' bin/logstash-plugin install $PLUGIN_LIST
    bin/logstash-plugin prepare-offline-pack $PLUGIN_LIST
    chmod a+r $plugins_file_name
    mv $plugins_file_name $STATIC_FILE_DIR/$plugins_file_name
}


mkdir -p $STATIC_FILE_DIR
cd $STATIC_FILE_DIR
echo "$STATIC_FILE_LIST" | while read STATIC_FILE
do
    h=$(dirname "$STATIC_FILE")
    d=${h#*//*/}
    f=${STATIC_FILE##*/}
    echo $STATIC_FILE
    robust_curl "$STATIC_FILE"
    if [[ $f =~ logstash.*\.tar\.gz$ ]];
    then
        handle_logstash $f
    fi
done
# TODO: Get rid of these static names
cat SHASUMS256.txt | grep node-v6.10.2-linux-x64.tar.gz > node-v6.10.2-linux-x64.tar.gz.sha1.txt
sha512sum je-5.0.73.jar > je-5.0.73.jar.sha512.txt
sha512sum Anaconda2-4.0.0-Linux-x86_64.sh > Anaconda2-4.0.0-Linux-x86_64.sh.sha512.txt

if [ "x$DISTRO" == "xrhel" -o "x$DISTRO" == "xcentos" ]; then
    yum install -y java-1.7.0-openjdk
    yum install -y postgresql-devel
elif [ "x$DISTRO" == "xubuntu" ]; then
    apt-get install -y default-jre
    apt-get install -y libpq-dev
fi

