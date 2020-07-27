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

os=$(awk -F= '/^NAME/{print $2}' /etc/os-release)

if [[ $os = *CentOS* ]]
then 

  echo "### You are running on CentOS"
  echo "### Copy repo files for InfluxDB and Grafana"
  cp -r $CYCLECLOUD_SPEC_PATH/files/yum.repos.d/* /etc/yum.repos.d/

  echo "### InfluxDB installation"
  yum -y install influxdb

  echo "### Grafana installation"
  yum -y install grafana

elif [[ $os = *Ubuntu* ]]
then 
  echo "### You are running on Ubuntu"
  echo "### Config repo for InfluxDB"
  #Add key of archive
  wget -qO- https://repos.influxdata.com/influxdb.key | apt-key add -

  #Add repository and update package sources
  source /etc/lsb-release
  echo "deb https://repos.influxdata.com/${DISTRIB_ID,,} ${DISTRIB_CODENAME} stable" | tee /etc/apt/sources.list.d/influxdb.list
  apt update

  echo "### InfluxDB installation"
  apt install -y influxdb

  echo "### Config repo for Grafana"
  apt install -y apt-transport-https
  #Add key of archive
  wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -

  #Add repository and update package sources
  add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
  apt update

  echo "### Grafana installation"
  apt install -y grafana

else
  echo "You are running on non-support OS" 
  exit 1
fi

echo "#### Starting InfluxDB services"
systemctl daemon-reload
systemctl start influxdb
systemctl enable influxdb

echo "#### Starting Grafana services"
systemctl start grafana-server
systemctl enable grafana-server

#echo "#### Opening InfluxDB firewalld port 80(83|86):"
#sudo firewall-cmd --permanent --zone=public --add-port=8086/tcp
#sudo firewall-cmd --permanent --zone=public --add-port=8083/tcp
#echo "#### Opening Grafana firewalld port 3000:"
#sudo firewall-cmd --permanent --zone=public --add-port=3000/tcp
#echo "#### Reload firewall rules:"
#sudo firewall-cmd --reload

echo "#### Configuration of InfluxDB"
curl "http://localhost:8086/query" --data-urlencode "q=CREATE USER admindb WITH PASSWORD '$INFLUXDB_PWD' WITH ALL PRIVILEGES"
curl "http://localhost:8086/query" --data-urlencode "q=CREATE USER $INFLUXDB_USER WITH PASSWORD '$INFLUXDB_PWD'"
curl "http://localhost:8086/query" --data-urlencode "q=CREATE DATABASE monitor"
curl "http://localhost:8086/query" --data-urlencode "q=GRANT ALL ON monitor to $INFLUXDB_USER"

echo "### Copy Grafana datasources"
grafana_etc_root=/etc/grafana/provisioning
cp -r $CYCLECLOUD_SPEC_PATH/files/grafana/datasource/* $grafana_etc_root/datasources/
chown grafana:grafana $grafana_etc_root/datasources/*

echo "### Restart Grafana Server"
systemctl stop grafana-server
systemctl start grafana-server

echo "### Write Grafana server IP to a shared directory (to be read from clients)"
mkdir -p $GRAFANA_SHARED/grafana
hostname -i > $GRAFANA_SHARED/grafana/grafana_server.conf

echo "### Finished Grafana server setup with Telegraf and InfluxDB"