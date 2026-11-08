FROM mcr.microsoft.com/playwright:v1.49.0-jammy

WORKDIR /tests

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

CMD ["npx", "playwright", "test"]
