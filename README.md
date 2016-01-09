### Status
[![Build Status](https://travis-ci.org/protofy/erl_zabbix_sender.svg)](https://travis-ci.org/protofy/erl_zabbix_sender)

erl_zabbix_sender
==================

The zabbix_sender module can be used to send data to a zabbix server via the zabbix_sender program.
See http://www.zabbix.com/

Usage
------

If you like to take it for a spin:
After cloning, get the updates and compile:

    > make update && make
    
You should have set up a test host with a test item on your zabbix server. These should match the local_name in your options (or your hostname -f if local_name is omitted) and the test item you send below.
You should also have installed zabbix_sender, which should be available in your PATH.

Now you can run the dev console:

    > bin/dev_console.sh
    erl> Opts = [{server_ref, singleton}, {remote_addr, "your.zabbix.server"}, {local_name, "test_host"}].
    erl> {ok, _} = zabbix_sender:start_link(Opts).
    erl> zabbix_sender:send("test_item", 42).
 
Take a look at the zabbix_sender module for further information about configuration and usage.

