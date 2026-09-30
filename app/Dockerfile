FROM node@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6 AS dependencies

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci     --omit=dev     --ignore-scripts     --no-audit     --no-fund  && npm cache clean --force


FROM node@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6 AS runtime

ENV NODE_ENV=production     HOST=0.0.0.0     PORT=3000     LAB_FAULTS_ENABLED=false

WORKDIR /app

COPY --from=dependencies     --chown=node:node     /app/node_modules     ./node_modules

COPY --chown=node:node     package.json     package-lock.json     ./

COPY --chown=node:node     src     ./src

USER node

EXPOSE 3000

HEALTHCHECK   --interval=10s   --timeout=3s   --start-period=5s   --retries=3   CMD ["node", "-e", "fetch('http://127.0.0.1:3000/healthz').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]

CMD ["node", "src/server.js"]
