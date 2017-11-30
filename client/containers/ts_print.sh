#!/bin/bash

telnet localhost $1 | while IFS= read -r line; do printf '{\"@timestamp\":\"%s\",\"trace\":\"%s\"}\n' "$(date '+%Y-%m-%dT%H:%M:%S.%NZ')" "$line"; done

