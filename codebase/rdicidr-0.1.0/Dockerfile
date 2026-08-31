FROM node:15-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm install \
    && rm -rf node_modules/prettier \
    && npm install --no-save eslint-plugin-prettier@3.4.1 eslint-config-prettier@8.3.0 prettier@2.8.8

COPY . .
RUN npx prettier --write ./src \
    && npm run build

FROM nginx:1.21-alpine

COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
