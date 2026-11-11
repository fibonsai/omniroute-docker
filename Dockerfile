FROM node:lts-alpine

RUN apk add --no-cache curl ca-certificates libc6-compat tzdata
RUN npm config set loglevel verbose && npm install -g --dangerously-allow-all-scripts omniroute && omniroute setup --non-interactive

RUN mkdir -p /workspace && chown node:node /workspace
USER node
WORKDIR /workspace

ENV INITIAL_PASSWORD=q1w2e3 \
    OPENROUTER_API_KEY="fake" \
    OPENCODE_API_KEY="fake" \
    CLOUDFLARE_API_KEY="fake" \
    VERCEL_API_KEY="fake" \
    DEEPINFRA_API_KEY="fake" \
    SILICONFLOW_API_KEY="fake" \
    NOVITA_API_KEY="fake"

EXPOSE 20128 20129

RUN omniroute providers list && echo && \
    omniroute providers validate && echo && \
    omniroute providers test-all

ENTRYPOINT ["omniroute"]
