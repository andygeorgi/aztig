#!/bin/bash

#Read aztig configuration file including (at least) INFLUXDB_USER, INFLUXDB_PWD and GRAFANA_SHARED
source $CYCLECLOUD_SPEC_PATH/files/config/aztig.conf

if [ -z "$GRAFANA_SHARED" ]; then
    echo "Grafana shared folder parameter is required"
    exit 1
fi
if [ -z "$INFLUXDB_USER" ]; then
    echo "InfluxDB user parameter is required"
    exit 1
fi
if [ -z "$INFLUXDB_PWD" ]; then
    echo "InfluxDB password parameter is required"
    exit 1
fi

GRAFANA_SERVER=$(cat $GRAFANA_SHARED/grafana/grafana_server.conf)
if [ -z "$GRAFANA_SERVER" ]; then
    echo "Grafana server information could not be found. Make sure the ${GRAFANA_SHARED}/grafana/grafana_server.conf is accessible."
    exit 1
fi

os=$(awk -F= '/^NAME/{print $2}' /etc/os-release)

if [[ $os = *CentOS* ]]
then 
  echo "You are running on CentOS"
  echo "#### Configuration repo for InfluxDB:"
  cat <<EOF | tee /etc/yum.repos.d/influxdb.repo
[influxdb]
name = InfluxDB Repository - RHEL \$releasever
baseurl = https://repos.influxdata.com/centos/\$releasever/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdb.key
EOF

  echo "#### Telegraf Installation:"
  yum -y install telegraf

elif [[ $os = *Ubuntu* ]]
then
  echo "You are running on Ubuntu"
  echo "### Config repo for InfluxDB"
  #Add key of archive
  wget -qO- https://repos.influxdata.com/influxdb.key | apt-key add -

  #Add repository and update package sources
  source /etc/lsb-release
  echo "deb https://repos.influxdata.com/${DISTRIB_ID,,} ${DISTRIB_CODENAME} stable" | tee /etc/apt/sources.list.d/influxdb.list
  apt update

  echo "### Telegraf Install:"
  apt install -y telegraf
else
  echo "You are running on non-support OS" 
  exit 1
fi  


echo "Push right config .... "
# Update telegraph.conf
cp /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf.origin

cat << EOF > /etc/telegraf/telegraf.conf
[global_tags]
[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false
[[outputs.influxdb]]
  urls = ["http://$GRAFANA_SERVER:8086"]
  database = "monitor"
  username = "$INFLUXDB_USER"
  password = "$INFLUXDB_PWD"
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false
[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]
[[inputs.diskio]]
[[inputs.kernel]]
[[inputs.mem]]
[[inputs.processes]]
[[inputs.swap]]
[[inputs.system]]
[[inputs.net]]
EOF

echo "#### Starting Telegraf services:"
systemctl daemon-reload
systemctl stop telegraf
systemctl start telegraf
systemctl enable telegraf