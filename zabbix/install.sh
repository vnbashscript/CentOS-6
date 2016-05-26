#!/bin/bash
#Install Zabbix 3.0 On Centos 6
check_id()
{
	if [ $(id -u) -ne 0 ]
	then
		echo 'Error: User is not root. Please login root'
		exit 1
	fi
}

edit_line()
{
	local a=$(sed -n "$1"p $4 | grep -w "$2")
	if [ "$a" != "" ]
	then
		sed -i "$1 s/$2/$3/g" $4
	else
		echo 'Line' $1 'trong file' $4 'Khong the chinh sua' $2 'thanh' $3 >> /tmp/log_error
	fi
}

random_pass()
{
	< /dev/urandom tr -dc A-Za-z0-9 | head -c32 && echo
}


install_base_package()
{
	#Install apache, httpd 
	yum -y install httpd  mysql-server
	if [ $? -ne 0 ]
	then
		echo 'Error: Can not install package'
		exit 1
	fi
	yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
	yum -y install https://mirror.webtatic.com/yum/el6/latest.rpm
	yum -y install php55w php55w-opcache php55w-mysql php55w-gd php55w-xml php55w-bcmath php55w-mbstring php55w-pear 
	#Install Epel-relase
	yum -y install epel-release
	if [ $? -ne 0 ]
	then
		echo 'Error: Can not install package'
		exit 1
	fi
	
	#Install Epel-zabbix
	yum -y install http://repo.zabbix.com/zabbix/3.0/rhel/6/x86_64/zabbix-release-3.0-1.el6.noarch.rpm
	if [ $? -ne 0 ]
	then
		echo 'Error: Can not install package'
		exit 1
	fi
	
	#install zabbix for mysql
	yum -y install zabbix-get zabbix-server-mysql zabbix-web-mysql zabbix-agent 
	if [ $? -ne 0 ]
	then
		echo 'Error: Can not install package'
		exit 1
	fi
}

base_configure_apache()
{
	rm -rf /tmp/log_error
	rm -rf /etc/httpd/conf.d/welcome.conf
	rm -rf /var/www/error/noindex.html
	file_httpd='/etc/httpd/conf/httpd.conf'
	edit_line 44 OS Prod $file_httpd
	edit_line 76 Off On $file_httpd
	edit_line 262 root@localhost root@server.world $file_httpd
	edit_line 338 None All $file_httpd
	edit_line 276 '#ServerName www.example.com:80' 'ServerName www.server.world:80' $file_httpd
	edit_line 402 index.html.var index.htm $file_httpd
	edit_line 536 On Off $file_httpd
	edit_line 759 AddDefaultCharset '#AddDefaultCharset' $file_httpd
	edit_line 878 2M 20M /etc/php.ini
}

base_configure_mysqld()
{
	local passconf=$1
cat > /root/config.sql <<eof
delete from mysql.user where user='';
update mysql.user set password=password("$passconf");
flush privileges;
eof
mysql -u root -e'source /root/config.sql'
rm -rf /root/config.sql
}

configure_zabbix()
{
	local pass_db=$1
	local pass_db_zabbix=$2
cat > /root/zabbix.sql <<eof
create database zabbix; 
grant all privileges on zabbix.* to zabbix@'localhost' identified by "$pass_db_zabbix"; 
grant all privileges on zabbix.* to zabbix@'%' identified by "$pass_db_zabbix"; 
eof
mysql -u root -p"$pass_db" -e'source /root/zabbix.sql'
rm -rf /root/zabbix.sql
cd /usr/share/doc/zabbix-server-mysql-*/
gunzip create.sql.gz 
mysql -u zabbix -p"$pass_db_zabbix" zabbix < create.sql 

cp /etc/zabbix/zabbix_server.conf /etc/zabbix/zabbix_server.conf.bk
cat > /etc/zabbix/zabbix_server.conf <<eof
LogFile=/var/log/zabbix/zabbix_server.log
LogFileSize=0
PidFile=/var/run/zabbix/zabbix_server.pid
DBHost=localhost 
DBName=zabbix
DBUser=zabbix
DBPassword=$pass_db_zabbix
SNMPTrapperFile=/var/log/snmptrap/snmptrap.log
Timeout=4
AlertScriptsPath=/usr/lib/zabbix/alertscripts
ExternalScripts=/usr/lib/zabbix/externalscripts
LogSlowQueries=3000
eof

cp /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.bk
cat > /etc/zabbix/zabbix_agentd.conf <<eof
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=0
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=$(hostname)
Include=/etc/zabbix/zabbix_agentd.d/
eof

cat > /etc/httpd/conf.d/zabbix.conf <<eof
#
# Zabbix monitoring system php web frontend
#

Alias /zabbix /usr/share/zabbix

<Directory "/usr/share/zabbix">
    Options FollowSymLinks
    AllowOverride None
    Order allow,deny
    Allow from all

    <IfModule mod_php5.c>
        php_value max_execution_time 300
        php_value memory_limit 128M
        php_value post_max_size 16M
        php_value upload_max_filesize 2M
        php_value max_input_time 300
        php_value always_populate_raw_post_data -1
        php_value date.timezone Asia/Ho_Chi_Minh
    </IfModule>
</Directory>

<Directory "/usr/share/zabbix/conf">
    Order deny,allow
    Deny from all
    <files *.php>
        Order deny,allow
        Deny from all
    </files>
</Directory>

<Directory "/usr/share/zabbix/app">
    Order deny,allow
    Deny from all
    <files *.php>
        Order deny,allow
        Deny from all
    </files>
</Directory>

<Directory "/usr/share/zabbix/include">
    Order deny,allow
    Deny from all
    <files *.php>
        Order deny,allow
        Deny from all
    </files>
</Directory>

<Directory "/usr/share/zabbix/local">
    Order deny,allow
    Deny from all
    <files *.php>
        Order deny,allow
        Deny from all
    </files>
</Directory>
eof
}


configure_firewall()
{
	setenforce 0
	edit_line 7 'enforcing' 'permissive' /etc/selinux/config 
	iptables -P INPUT ACCEPT
	iptables -P OUTPUT ACCEPT
	iptables -P FORWARD DROP
	iptables -F
	iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 
	iptables -A INPUT -p icmp -j ACCEPT 
	iptables -A INPUT -i lo -j ACCEPT 
	iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT 
	iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT 
	iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT 
	iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 3306 -j ACCEPT 
	iptables -P INPUT DROP
	service iptables save
}


start_service()
{
	service httpd start
	chkconfig httpd on
	service mysqld start
	chkconfig mysqld on
	service zabbix-server start
	chkconfig zabbix-server on
	service zabbix-agent start
	chkconfig zabbix-agent on
}



main()
{
	clear
	check_id
	install_base_package
	password_msql=$(random_pass)
	password_sql_zabbix=$(random_pass)
	service mysqld start
	base_configure_apache
	base_configure_mysqld $password_msql
	configure_zabbix $password_msql $password_sql_zabbix
	configure_firewall
	start_service
	clear
	echo "ROOT DATABASE: $password_msql" > ~/.password
	echo "USER ZABBIX: $password_sql_zabbix" >> ~/.password
	echo 'Install Success Full'
	echo "Password Root Database: $password_msql"
	echo "Password user database zabbix: $password_sql_zabbix"
	echo 'Password duoc luu tai file: ~/.password'
}

main