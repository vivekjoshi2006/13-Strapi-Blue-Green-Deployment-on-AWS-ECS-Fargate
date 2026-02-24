FROM node:18-bullseye-slim
ENV NODE_ENV=production
WORKDIR /opt/app

RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    make \
    python3 \
    libpng-dev \
    libvips-dev \
    && rm -rf /var/lib/apt/lists/*


COPY package*.json ./
RUN npm install --network-timeout=100000

COPY . .
RUN npm run build

EXPOSE 1337
CMD ["npm", "run", "start"]