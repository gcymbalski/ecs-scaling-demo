#!/bin/sh
exec /backend/backend  >>/var/log/backend.log 2>&1
