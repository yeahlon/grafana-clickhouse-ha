-- Create Grafana database
CREATE DATABASE grafana;

-- Create user (if not exists from environment)
DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = 'grafana') THEN
      CREATE ROLE grafana LOGIN PASSWORD 'grafana_password';
   END IF;
END
$$;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;

-- Connect to grafana database
\c grafana

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO grafana;
