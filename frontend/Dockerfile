# frontend/Dockerfile

# ================================
# Stage 1: Base
# ================================
FROM node:24-alpine AS base

WORKDIR /app

# ================================
# Stage 2: Dependencies
# ================================
FROM base AS dependencies

COPY frontend/package*.json ./

# Separate prod and dev deps for caching
RUN npm ci

# ================================
# Stage 3: Development
# ================================
FROM base AS development

# Copy all node_modules (including dev deps for hot reload)
COPY --from=dependencies /app/node_modules ./node_modules
COPY frontend/ .

EXPOSE 5173

# Vite dev server — listens on all interfaces so Docker can forward
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]

# ================================
# Stage 4: Builder — builds static assets
# ================================
FROM base AS builder

# Accept build arg to inject at build time
ARG VITE_API_URL
ARG VITE_ENV

ENV VITE_API_URL=$VITE_API_URL
ENV VITE_ENV=$VITE_ENV

COPY --from=dependencies /app/node_modules ./node_modules
COPY frontend/ .

RUN npm run build
# Output is in /app/dist

# ================================
# Stage 5: Production / Staging — serve with nginx
# ================================
FROM nginx:1.25-alpine AS production

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our nginx config
COPY frontend/nginx/nginx.conf /etc/nginx/conf.d/

# Copy built assets from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Non-root nginx
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]

# Staging is identical to production — env vars differ at runtime
FROM production AS staging

