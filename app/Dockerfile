FROM node@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20 AS dependencies

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci     --omit=dev     --ignore-scripts     --no-audit     --no-fund  && npm cache clean --force


FROM node@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20 AS runtime

# Runtime security remediation:
# - update only the vulnerable Debian perl-base package
# - remove npm/npx because the production runtime does not require them
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        perl-base=5.36.0-7+deb12u4; \
    rm -rf /var/lib/apt/lists/*; \
    rm -rf /usr/local/lib/node_modules/npm; \
    rm -f /usr/local/bin/npm /usr/local/bin/npx

ENV NODE_ENV=production     HOST=0.0.0.0     PORT=3000     LAB_FAULTS_ENABLED=false

WORKDIR /app

COPY --from=dependencies     --chown=node:node     /app/node_modules     ./node_modules

COPY --chown=node:node     package.json     package-lock.json     ./

COPY --chown=node:node     src     ./src

RUN mkdir -p /var/log/sre-api \
    && chown node:node /var/log/sre-api \
    && chmod 0755 /var/log/sre-api

USER node

EXPOSE 3000

HEALTHCHECK   --interval=10s   --timeout=3s   --start-period=5s   --retries=3   CMD ["node", "-e", "fetch('http://127.0.0.1:3000/healthz').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]

CMD ["node", "src/server.js"]
