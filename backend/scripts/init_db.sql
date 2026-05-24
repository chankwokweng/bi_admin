-- Run once to create the admin users table and seed the first super admin.
-- After running, log in with the printed credentials and change the password immediately.

CREATE TABLE IF NOT EXISTS admin_users (
    id                  SERIAL PRIMARY KEY,
    email               TEXT UNIQUE NOT NULL,
    password_hash       TEXT NOT NULL,
    role                TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('super_admin', 'user')),
    is_approved         BOOLEAN NOT NULL DEFAULT FALSE,
    must_change_password BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed super admin (password: Admin@1234 — CHANGE IMMEDIATELY after first login)
-- bcrypt hash of "Admin@1234"
INSERT INTO admin_users (email, password_hash, role, is_approved, must_change_password)
VALUES (
    'admin@tyto-solutions.com',
    '$2b$12$F2XGTCnpUH/TEyKUTzmwzepbvgPdeEE.va8kZnjFqlgsITIXrSzKC',
    'super_admin',
    TRUE,
    TRUE
)
ON CONFLICT (email) DO NOTHING;
