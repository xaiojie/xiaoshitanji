FROM node:24-bookworm-slim
WORKDIR /app

RUN npm install --global pnpm@12.15.0
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --prod --frozen-lockfile

COPY bootstrap.js ./
COPY dist ./dist
COPY public ./public
COPY typings ./typings
RUN mkdir -p /home/node/.cool-admin /app/logs /app/run \
    && chown node:node /home/node/.cool-admin /app/logs /app/run

ENV NODE_ENV=production MIDWAY_SERVER_ENV=prod TZ=Asia/Shanghai
USER node
EXPOSE 8002
CMD ["node", "bootstrap.js"]
