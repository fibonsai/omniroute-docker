#!/bin/sh
BLACKLIST_PROVIDERS=",openai,"
for p in `omniroute providers available --category api-key --json 2> /dev/null | grep -v 'Loaded' | jq -rc '.providers[].id'|sort`; do
  if echo "$BLACKLIST_PROVIDERS" | grep -qi ",${p},"; then
    echo "$p blacklisted. Ignoring"
    continue
  fi
  P_API_KEY="`printenv $(echo $p | tr a-z A-Z | sed 's/-/_/g')_API_KEY`"
  if [ "x$P_API_KEY" != "x" ]; then
    omniroute setup --non-interactive --add-provider --provider $p --api-key "$P_API_KEY" --test-provider
  else
    echo "$p api-key not defined. Ignoring."
  fi
done
EOF
