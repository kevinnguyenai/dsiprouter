#!/usr/bin/env bash

# Debug this script if in debug mode
(( $DEBUG == 1 )) && set -x

# Import dsip_lib utility / shared functions if not already
if [[ "$DSIP_LIB_IMPORTED" != "1" ]]; then
    . ${DSIP_PROJECT_DIR}/dsiprouter/dsip_lib.sh
fi

function install {
    # create dsiprouter user and group
    # sometimes locks aren't properly removed (this seems to happen often on VM's)
    rm -f /etc/passwd.lock /etc/shadow.lock /etc/group.lock /etc/gshadow.lock &>/dev/null
    userdel dsiprouter &>/dev/null; groupdel dsiprouter &>/dev/null
    useradd --system --user-group --shell /bin/false --comment "dSIPRouter SIP Provider Platform" dsiprouter

    # Install dependencies for dSIPRouter
    yum remove -y rs-epel-release*

    yum install -y yum-utils
    yum --setopt=group_package_types=mandatory,default,optional groupinstall -y "Development Tools"
    yum install -y firewalld
    yum install -y python36 python36-libs python36-devel python36-pip MySQL-python
    yum install -y logrotate rsyslog perl libev-devel util-linux postgresql-devel mariadb-devel

    # reset python cmd in case it was just installed
    setPythonCmd

    # make sure the nginx user has access to dsiprouter directories
    usermod -a -G dsiprouter nginx
    # make dsiprouter user has access to kamailio files
    usermod -a -G kamailio dsiprouter

    # setup runtime directorys for dsiprouter
    mkdir -p ${DSIP_RUN_DIR}
    chown -R dsiprouter:dsiprouter ${DSIP_RUN_DIR}

    # give dsiprouter permissions in SELINUX
    semanage port -a -t http_port_t -p tcp ${DSIP_PORT} ||
        semanage port -m -t http_port_t -p tcp ${DSIP_PORT}

    # Fix for bug: https://bugzilla.redhat.com/show_bug.cgi?id=1575845
    if (( $? != 0 )); then
        systemctl restart dbus
        systemctl restart firewalld
    fi

    # Setup Firewall for DSIP_PORT
    firewall-offline-cmd --zone=public --add-port=${DSIP_PORT}/tcp

   # Enable and start firewalld if not already running
    systemctl enable firewalld
    systemctl restart firewalld

    ${PYTHON_CMD} -m pip install -r ${DSIP_PROJECT_DIR}/gui/requirements.txt
    if (( $? == 1 )); then
        printerr "dSIPRouter install failed: Couldn't install required python libraries"
        exit 1
    fi

    # setup dsiprouter nginx configs
    perl -e "\$dsip_port='${DSIP_PORT}'; \$dsip_unix_sock='${DSIP_UNIX_SOCK}'; \$dsip_ssl_cert='${DSIP_SSL_CERT}'; \$dsip_ssl_key='${DSIP_SSL_KEY}';" \
        -pe 's%DSIP_UNIX_SOCK%${dsip_unix_sock}%g; s%DSIP_PORT%${dsip_port}%g; s%DSIP_SSL_CERT%${dsip_ssl_cert}%g; s%DSIP_SSL_KEY%${dsip_ssl_key}%g;' \
        ${DSIP_PROJECT_DIR}/nginx/configs/dsiprouter.conf >/etc/nginx/sites-available/dsiprouter.conf
    ln -sf /etc/nginx/sites-available/dsiprouter.conf /etc/nginx/sites-enabled/dsiprouter.conf
    systemctl enable nginx
    systemctl restart nginx

    # Configure rsyslog defaults
    if ! grep -q 'dSIPRouter rsyslog.conf' /etc/rsyslog.conf 2>/dev/null; then
        cp -f ${DSIP_PROJECT_DIR}/resources/syslog/rsyslog.conf /etc/rsyslog.conf
    fi

    # Setup dSIPRouter Logging
    cp -f ${DSIP_PROJECT_DIR}/resources/syslog/dsiprouter.conf /etc/rsyslog.d/dsiprouter.conf
    touch /var/log/dsiprouter.log
    systemctl restart rsyslog

    # Setup logrotate
    cp -f ${DSIP_PROJECT_DIR}/resources/logrotate/dsiprouter /etc/logrotate.d/dsiprouter

    # Install dSIPRouter as a service
    perl -p \
        -e "s|'DSIP_RUN_DIR\=.*'|'DSIP_RUN_DIR=$DSIP_RUN_DIR'|;" \
        -e "s|'DSIP_PROJECT_DIR\=.*'|'DSIP_PROJECT_DIR=$DSIP_PROJECT_DIR'|;" \
        -e "s|'DSIP_SYSTEM_CONFIG_DIR\=.*'|'DSIP_SYSTEM_CONFIG_DIR=$DSIP_SYSTEM_CONFIG_DIR'|;" \
        -e "s|ExecStart\=.*|ExecStart=${PYTHON_CMD} "'\${DSIP_PROJECT_DIR}'"/gui/dsiprouter.py|;" \
        ${DSIP_PROJECT_DIR}/dsiprouter/systemd/dsiprouter-v1.service > /lib/systemd/system/dsiprouter.service
    chmod 644 /lib/systemd/system/dsiprouter.service
    systemctl daemon-reload
    systemctl enable dsiprouter

    # add hook to bash_completion in the standard debian location
    echo '. /usr/share/bash-completion/bash_completion' > /etc/bash_completion
}


function uninstall {
    # Uninstall dependencies for dSIPRouter
    cat ${DSIP_PROJECT_DIR}/gui/requirements.txt | xargs -n 1 $PYTHON_CMD -m pip uninstall --yes
    if (( $? == 1 )); then
        printerr "dSIPRouter uninstall failed or the libraries are already uninstalled"
        exit 1
    else
        printdbg "DSIPRouter uninstall was successful"
        exit 0
    fi

    yum remove -y python36u\*
    yum remove -y ius-release
    yum groupremove -y "Development Tools"

    # Remove the repos
    rm -f /etc/yum.repos.d/ius*
    rm -f /etc/pki/rpm-gpg/IUS-COMMUNITY-GPG-KEY
    yum clean all

    # Remove Firewall for DSIP_PORT
    firewall-cmd --zone=public --remove-port=${DSIP_PORT}/tcp --permanent
    firewall-cmd --reload

    # Remove dSIPRouter Logging
    rm -f /etc/rsyslog.d/dsiprouter.conf

    # Remove logrotate settings
    rm -f /etc/logrotate.d/dsiprouter

    # Remove dSIProuter as a service
    systemctl stop dsiprouter.service
    systemctl disable dsiprouter.service
    rm -f /lib/systemd/system/dsiprouter.service
    systemctl daemon-reload
}


case "$1" in
    uninstall)
        uninstall
        ;;
    install)
        install
        ;;
    *)
        printerr "usage $0 [install | uninstall]"
        ;;
esac
