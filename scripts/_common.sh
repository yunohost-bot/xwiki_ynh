#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

super_admin_config='#'
systemd_match_start_line='oxtjl.NotifyListener:main: ----------------------------------'
flavor_version='15.10'
ldap_version='9.12.0'

if [ $install_standard_flavor -eq 1 ]; then
    distribution_default_ui="distribution.defaultUI=org.xwiki.platform:xwiki-platform-distribution-flavor-mainwiki/$flavor_version"
else
    distribution_default_ui='#'
fi

#=================================================
# PERSONAL HELPERS
#=================================================

enable_super_admin() {
    super_admin_pwd=$(ynh_string_random)
    super_admin_config="xwiki.superadminpassword=$super_admin_pwd"
    ynh_add_config --template=xwiki.cfg --destination="$install_dir"/webapps/xwiki/WEB-INF/xwiki.cfg
    chmod 400 "$install_dir"/webapps/xwiki/WEB-INF/xwiki.cfg
    chown "$app:$app" "$install_dir"/webapps/xwiki/WEB-INF/xwiki.cfg
}

disable_super_admin() {
    super_admin_config='#'
    ynh_add_config --template=xwiki.cfg --destination="$install_dir"/webapps/xwiki/WEB-INF/xwiki.cfg
    chmod 400 "$install_dir"/webapps/xwiki/WEB-INF/xwiki.cfg
    chown "$app:$app" "$install_dir"/webapps/xwiki/WEB-INF/xwiki.cfg
}

install_exension() {
    local extension_id=$1
    local extension_version=$2
    local temp_dir=$(mktemp -d)
    local job_id=$(ynh_string_random)
    local xq=$install_dir/xq_tool/xq
    local curl='curl --silent --show-error'

    local status_raw
    local state_request

    chmod 700 $temp_dir
    chown root:root $temp_dir

    ynh_add_config --template=install_extensions.xml --destination=$temp_dir/install_extensions.xml
    status_raw=$($curl -i --user "superadmin:$super_admin_pwd" -X PUT -H 'Content-Type: text/xml' "http://localhost:$port/xwiki/rest/jobs?jobType=install&async=true" --upload-file $temp_dir/install_extensions.xml)
    state_request=$(echo $status_raw | $xq -x '//jobStatus/ns2:state')

    while true; do
        sleep 5

        status_raw=$($curl --user "superadmin:$super_admin_pwd" -X GET -H 'Content-Type: text/xml' "http://localhost:$port/xwiki/rest/jobstatus/extension/provision/$job_id")
        state_request=$(echo "$status_raw" | $xq -x '//jobStatus/state')

        if [ -z "$state_request" ]; then
            ynh_die --message="Invalid answer: '$status_raw'"
        elif [ "$state_request" == FINISHED ]; then
            # Check if error happen
            error_msg=$(echo "$status_raw" | $xq -x '//jobStatus/errorMessage')
            if [ -z "$error_msg" ]; then
                break
            else
                ynh_die --message="Error while installing extension '$extension_id'. Error: $error_msg"
            fi
        elif [ "$state_request" != RUNNING ]; then
            ynh_die --message="Invalid status '$state_request'"
        fi
    done
}

wait_for_flavor_install() {
    local flavor_job_id='org.xwiki.platform%3Axwiki-platform-distribution-flavor-mainwiki/wiki%3Axwiki'
    local status_raw
    local state_request
    local xq=$install_dir/xq_tool/xq
    local curl='curl --silent --show-error'

    # Need to call main page to start xwiki service
    $curl "http://localhost:$port/xwiki/bin/view/Main/" > /dev/null &

    sleep 20

    while true; do
        status_raw=$($curl --user "superadmin:$super_admin_pwd" -X GET -H 'Content-Type: text/xml' "http://localhost:$port/xwiki/rest/jobstatus/extension/action/$flavor_job_id")
        state_request=$(echo "$status_raw" | $xq -x '//jobStatus/state')

        if [ -z "$state_request" ]; then
            ynh_die --message="Invalid answer: '$status_raw'"
        elif [ "$state_request" == FINISHED ]; then
            # Check if error happen
            error_msg=$(echo "$status_raw" | $xq -x '//jobStatus/errorMessage')
            if [ -z "$error_msg" ]; then
                break
            else
                ynh_die --message="Error while installing extension 'org.xwiki.platform%3Axwiki-platform-distribution-flavor-mainwiki'. Error: $error_msg"
            fi
        elif [ "$state_request" != RUNNING ]; then
            ynh_die --message="Invalid status '$state_request'"
        fi
        sleep 10
    done
}


set_permissions() {
    chmod -R u+rwX,o-rwx "$install_dir"
    chown -R "$app:$app" "$install_dir"

    chown "$app:$app" -R /var/log/$app
    chmod u=rwX,g=rX,o= -R /var/log/$app

    find $data_dir \(   \! -perm u=rwX,g=rX,-o= \
                    -o \! -user $YNH_APP_ID \
                    -o \! -group $YNH_APP_ID \) \
                -exec chown $YNH_APP_ID:$YNH_APP_ID {} \; \
                -exec chmod u=rwX,g=rX,o= {} \;
}

#=================================================
# EXPERIMENTAL HELPERS
#=================================================

#=================================================
# FUTURE OFFICIAL HELPERS
#=================================================
