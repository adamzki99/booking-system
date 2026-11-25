FROM mcr.microsoft.com/playwright:v1.65.1-jammy

WORKDIR /tests

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

CMD ["npx", "playwright", "test"]
