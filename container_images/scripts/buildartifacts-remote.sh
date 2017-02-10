#!/bin/bash
. /etc/profile
cd /home/ubuntu/repo
bundle
bundle exec rake build:artifacts && touch /tmp/done
