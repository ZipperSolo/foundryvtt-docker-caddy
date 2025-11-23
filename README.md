# FoundryVTT Docker Setup

A production-ready FoundryVTT deployment using Docker, Caddy for automatic HTTPS/TLS, and Docker secrets for credential management.

## Features

- **Automated TLS/SSL**: Caddy automatically obtains and renews Let's Encrypt certificates
- **Secure Credentials**: Docker secrets for sensitive data management
- **Easy Updates**: Pull new images to upgrade FoundryVTT
- **Reverse Proxy**: Caddy handles SSL termination and proxying
- **Persistent Data**: All game data stored in mounted volumes

## Prerequisites

- Docker and Docker Compose installed
- A domain name (e.g., `foundry.yourdomain.com`)
- Ports 80 and 443 open and forwarded to your server
- FoundryVTT account credentials from [foundryvtt.com](https://foundryvtt.com)

## Quick Start

### 1. Clone or Create Project Directory

```bash
mkdir foundry-vtt
cd foundry-vtt
```

### 2. Create Directory Structure

```bash
mkdir -p data
```

Your structure should look like:

```txt
foundry-vtt/
├── docker-compose.yml
├── Caddyfile
├── secrets.json
├── data/
└── .gitignore
```

### 3. Create secrets.json

Create a `secrets.json` file with your credentials:

```json
{
  "foundry_admin_key": "your_secure_admin_key_here",
  "foundry_password": "your_foundryvtt_com_password",
  "foundry_username": "your_foundryvtt_com_username"
}
```

**Notes:**

- `foundry_username` and `foundry_password` are your credentials from foundryvtt.com (where you purchased the license)
- `foundry_admin_key` is a password you create to access the FoundryVTT setup screen
- Special characters in passwords work fine in JSON format

Set proper permissions:

```bash
chmod 600 secrets.json
```

### 4. Create docker-compose.yml

```yaml
version: '3.8'

secrets:
  config_json:
    file: ./secrets.json

services:
  foundryvtt:
    image: felddy/foundryvtt:release
    hostname: foundry_host
    init: true
    restart: unless-stopped
    volumes:
      - ./data:/data
    environment:
      - FOUNDRY_MINIFY_STATIC_FILES=true
      - FOUNDRY_HOSTNAME=foundry.yourdomain.com
      - FOUNDRY_PROXY_SSL=true
      - FOUNDRY_PROXY_PORT=443
    secrets:
      - source: config_json
        target: config.json
    networks:
      - foundry_network

  caddy:
    image: caddy:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - foundry_network

networks:
  foundry_network:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
```

**Important:** Replace `foundry.yourdomain.com` with your actual domain name.

### 5. Create Caddyfile

```Caddyfile
foundry.yourdomain.com {
    reverse_proxy foundryvtt:30000 {
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

**Important:** Replace `foundry.yourdomain.com` with your actual domain name.

### 6. Create .gitignore (Optional but Recommended)

```gitignore
secrets.json
data/
.env
```

### 7. Start the Services

```bash
docker-compose up -d
```

### 8. Access Your Instance

Navigate to `https://foundry.yourdomain.com` (or your domain) and enter your `foundry_admin_key` when prompted.

## Configuration

### Environment Variables

The following environment variables can be configured in `docker-compose.yml`:

| Variable | Purpose | Default |
|----------|---------|---------|
| `FOUNDRY_HOSTNAME` | Your domain name | - |
| `FOUNDRY_PROXY_SSL` | Tells FoundryVTT it's behind HTTPS proxy | `true` |
| `FOUNDRY_PROXY_PORT` | External HTTPS port | `443` |
| `FOUNDRY_MINIFY_STATIC_FILES` | Compress static files for better performance | `true` |

### Docker Secrets

Secrets are stored in `secrets.json` and support the following keys:

| Key | Purpose | Required |
|-----|---------|----------|
| `foundry_admin_key` | Admin password for setup screen | Yes |
| `foundry_username` | Your foundryvtt.com username | Yes |
| `foundry_password` | Your foundryvtt.com password | Yes |
| `foundry_license_key` | Specific license key to use | No |
| `foundry_password_salt` | Custom password salt | No |

## Management

### View Logs

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f foundryvtt
docker-compose logs -f caddy
```

### Restart Services

```bash
# Restart all services
docker-compose restart

# Restart specific service
docker-compose restart foundryvtt
docker-compose restart caddy
```

### Stop Services

```bash
docker-compose down
```

### Update FoundryVTT

```bash
# Pull latest image
docker-compose pull

# Recreate containers with new image
docker-compose up -d
```

## Local Network Access

### Option 1: Use Your Domain (Recommended)

If you have DNS properly configured (including local DNS or split DNS), simply access via:

```txt
https://foundry.yourdomain.com
```

### Option 2: pfSense Split DNS

If using pfSense:

1. Go to **Services > DNS Resolver**
2. Add a **Host Override**:
   - Host: `foundry` (or your subdomain)
   - Domain: `yourdomain.com`
   - IP: Your server's local IP (e.g., `192.168.1.100`)
3. Save and apply changes
4. Clear DNS cache on client machines
5. Access via `https://foundry.yourdomain.com`

### Option 3: Direct Port Access

For troubleshooting, you can expose port 30000 directly:

Add to `docker-compose.yml` under `foundryvtt` service:

```yaml
ports:
  - "30000:30000"
```

Then access via `http://SERVER_IP:30000`

## Troubleshooting

### Cannot Access Locally

**Problem:** Getting DNS rebind errors from pfSense

**Solution:** Add your domain to pfSense DNS Resolver host overrides (see Local Network Access above)

### Certificate Errors

**Problem:** Browser shows SSL/TLS certificate errors

**Solution:**

- Ensure ports 80 and 443 are accessible from the internet for Let's Encrypt validation
- Check Caddy logs: `docker-compose logs caddy | grep -i certificate`
- Verify your domain points to your public IP

### Container Won't Start

**Problem:** FoundryVTT container fails to start

**Solution:**

- Check credentials in `secrets.json` are correct
- View logs: `docker-compose logs foundryvtt`
- Ensure the `data` directory has proper permissions

### Port Conflicts

**Problem:** Ports 80 or 443 already in use

**Solution:**

```bash
# Check what's using the ports
sudo netstat -tlnp | grep -E ':(80|443)'

# Stop conflicting services or change port mappings
```

## Backup

### Backup Your Data

All FoundryVTT data is stored in the `./data` directory. To backup:

```bash
# Stop the container
docker-compose stop foundryvtt

# Create backup
tar -czf foundry-backup-$(date +%Y%m%d).tar.gz data/

# Restart the container
docker-compose start foundryvtt
```

### Automated Backups

Consider setting up a cron job for automated backups:

```bash
# Edit crontab
crontab -e

# Add daily backup at 3 AM
0 3 * * * cd /path/to/foundry-vtt && tar -czf /backups/foundry-$(date +\%Y\%m\%d).tar.gz data/
```

## Security Considerations

1. **Never commit secrets.json** - Always add it to `.gitignore`
2. **Set proper file permissions** - `chmod 600 secrets.json`
3. **Use strong passwords** - Especially for `foundry_admin_key`
4. **Keep images updated** - Regularly pull new versions
5. **Firewall rules** - Only expose ports 80 and 443 to the internet
6. **Regular backups** - Back up your data directory regularly

## Updating Configuration

### Change Domain Name

1. Update `FOUNDRY_HOSTNAME` in `docker-compose.yml`
2. Update domain in `Caddyfile`
3. Restart services: `docker-compose up -d`

### Change Admin Password

1. Update `foundry_admin_key` in `secrets.json`
2. Restart FoundryVTT: `docker-compose restart foundryvtt`

## Additional Resources

- [FoundryVTT Documentation](https://foundryvtt.com/kb/)
- [felddy/foundryvtt-docker GitHub](https://github.com/felddy/foundryvtt-docker)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## License

This setup configuration is provided as-is for use with FoundryVTT. FoundryVTT itself requires a valid license from foundryvtt.com.

## Support

For issues with:

- **This Docker setup**: Check the troubleshooting section above
- **FoundryVTT software**: Visit the [FoundryVTT community](https://discord.gg/foundryvtt)
- **felddy Docker image**: Check the [GitHub repository](https://github.com/felddy/foundryvtt-docker)
- **Caddy**: Visit [Caddy community](https://caddy.community/)
