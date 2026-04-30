FROM node:20

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY . .

# Cloud Run injects the PORT environment variable automatically
ENV PORT 8080

CMD ["node", "index.js"]