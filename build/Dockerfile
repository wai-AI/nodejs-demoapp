FROM node:22-alpine

LABEL Name="Node.js Demo App" Version="4.9.9"
LABEL org.opencontainers.image.source="https://github.com/wai-AI/nodejs-demoapp"
ENV NODE_ENV=production PORT=3000
WORKDIR /app

COPY --chown=node:node src/package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY --chown=node:node src/. .

USER node
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||3000)+'/healthz',r=>{r.resume();process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))"
CMD ["node", "--expose_gc", "server.mjs"]
